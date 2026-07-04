defmodule Sahla.Vehicles.Import do
  @moduledoc """
  Bulk ingestion of the make → model → version catalog from broker/market
  spreadsheets (§7.3, §10.5).

  Each CSV row is upserted idempotently by natural key — make by `name`, model by
  `(make, name)`, version by `(model, name)` — so re-importing the same file
  never duplicates rows; a version's attributes (`fiscal_power`, `fuel`, `seats`,
  `new_value_centimes`, `years`) are refreshed in place.

  Ingestion is **safe**: a row missing a make/model/version, carrying an unknown
  fuel, an unparseable number, or a half-specified year span is reported and
  skipped — never fatal. The summary carries per-outcome counts and a row-level
  error list.

  Expected columns (header names, order-independent):

    * `make`, `model`, `version` (required)
    * `fiscal_power`, `seats`, `new_value_centimes` (optional integers)
    * `fuel` (optional; one of `Version.fuels/0`)
    * `year_from`, `year_to` (optional; both or neither)
    * `popular` (optional make flag)
  """
  alias Sahla.CSV
  alias Sahla.Repo
  alias Sahla.Vehicles.{Make, Model, Version}

  @truthy ~w(1 true vrai oui yes y)
  @falsy ~w(0 false faux non no n)

  @empty %{
    makes_created: 0,
    models_created: 0,
    versions_inserted: 0,
    versions_updated: 0,
    failed: 0,
    errors: []
  }

  @type summary :: %{
          makes_created: non_neg_integer(),
          models_created: non_neg_integer(),
          versions_inserted: non_neg_integer(),
          versions_updated: non_neg_integer(),
          failed: non_neg_integer(),
          errors: [%{row: pos_integer(), error: String.t()}]
        }

  @doc "Parses `csv` text and imports it. See `import_rows/1`."
  @spec import_csv(String.t()) :: summary()
  def import_csv(csv) when is_binary(csv), do: csv |> CSV.parse() |> import_rows()

  @doc """
  Imports a list of row maps (string-keyed, as `CSV.parse/1` returns). Returns a
  summary with insert/update/failure counts and a row-level error report.
  """
  @spec import_rows([map()]) :: summary()
  def import_rows(rows) when is_list(rows) do
    rows
    |> Enum.with_index(1)
    |> Enum.reduce(@empty, fn {row, index}, acc -> import_row(row, index, acc) end)
    |> Map.update!(:errors, &Enum.reverse/1)
  end

  # --- per-row ---------------------------------------------------------------

  defp import_row(row, index, acc) do
    with {:ok, make_name} <- required(row, "make"),
         {:ok, model_name} <- required(row, "model"),
         {:ok, version_name} <- required(row, "version"),
         {:ok, attrs} <- parse_attrs(row) do
      upsert(make_name, model_name, version_name, attrs, index, acc)
    else
      {:error, reason} -> add_error(acc, index, reason)
    end
  end

  defp upsert(make_name, model_name, version_name, attrs, index, acc) do
    Repo.transaction(fn ->
      with {:ok, make, make_op} <- upsert_make(make_name, attrs),
           {:ok, model, model_op} <- upsert_model(make, model_name),
           {:ok, _version, version_op} <- upsert_version(model, version_name, attrs) do
        {make_op, model_op, version_op}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {make_op, model_op, version_op}} -> tally(acc, make_op, model_op, version_op)
      {:error, reason} -> add_error(acc, index, reason)
    end
  end

  defp upsert_make(name, attrs) do
    case Repo.get_by(Make, name: name) do
      nil ->
        %Make{}
        |> Make.changeset(%{name: name, popular: attrs.popular || false})
        |> Repo.insert()
        |> tag(:created)

      make ->
        # Only touch `popular` when the row actually carries it.
        changes = if is_nil(attrs.popular), do: %{}, else: %{popular: attrs.popular}

        make
        |> Make.changeset(Map.put(changes, :name, name))
        |> Repo.update()
        |> tag(:existing)
    end
  end

  defp upsert_model(make, name) do
    case Repo.get_by(Model, make_id: make.id, name: name) do
      nil ->
        %Model{}
        |> Model.changeset(%{make_id: make.id, name: name})
        |> Repo.insert()
        |> tag(:created)

      model ->
        {:ok, model, :existing}
    end
  end

  defp upsert_version(model, name, attrs) do
    version_attrs = %{
      model_id: model.id,
      name: name,
      fiscal_power: attrs.fiscal_power,
      fuel: attrs.fuel,
      seats: attrs.seats,
      new_value_centimes: attrs.new_value_centimes,
      years: attrs.years
    }

    case Repo.get_by(Version, model_id: model.id, name: name) do
      nil ->
        %Version{}
        |> Version.changeset(version_attrs)
        |> Repo.insert()
        |> tag(:inserted)

      version ->
        version
        |> Version.changeset(version_attrs)
        |> Repo.update()
        |> tag(:updated)
    end
  end

  defp tag({:ok, record}, op), do: {:ok, record, op}
  defp tag({:error, changeset}, _op), do: {:error, changeset_error(changeset)}

  # --- field parsing ---------------------------------------------------------

  defp required(row, column) do
    case trimmed(row[column]) do
      nil -> {:error, "missing #{column}"}
      value -> {:ok, value}
    end
  end

  defp parse_attrs(row) do
    with {:ok, fiscal_power} <- parse_int(row["fiscal_power"], "fiscal_power"),
         {:ok, seats} <- parse_int(row["seats"], "seats"),
         {:ok, value} <- parse_int(row["new_value_centimes"], "new_value_centimes"),
         {:ok, fuel} <- parse_fuel(row["fuel"]),
         {:ok, years} <- parse_years(row),
         {:ok, popular} <- parse_popular(row["popular"]) do
      {:ok,
       %{
         fiscal_power: fiscal_power,
         seats: seats,
         new_value_centimes: value,
         fuel: fuel,
         years: years,
         popular: popular
       }}
    end
  end

  defp parse_fuel(value) do
    case trimmed(value) do
      nil ->
        {:ok, nil}

      fuel ->
        case Enum.find(Version.fuels(), &(Atom.to_string(&1) == fuel)) do
          nil -> {:error, "unknown fuel: #{fuel}"}
          atom -> {:ok, atom}
        end
    end
  end

  # Both bounds present -> an inclusive year range; neither -> nil; one -> error.
  defp parse_years(row) do
    with {:ok, from} <- parse_int(row["year_from"], "year_from"),
         {:ok, to} <- parse_int(row["year_to"], "year_to") do
      case {from, to} do
        {nil, nil} -> {:ok, nil}
        {from, to} when is_integer(from) and is_integer(to) and from <= to -> {:ok, from..to}
        {from, to} when is_integer(from) and is_integer(to) -> {:error, "year_from > year_to"}
        _ -> {:error, "year_from and year_to must both be set"}
      end
    end
  end

  defp parse_popular(value) do
    case value |> to_string() |> String.trim() |> String.downcase() do
      "" -> {:ok, nil}
      v when v in @truthy -> {:ok, true}
      v when v in @falsy -> {:ok, false}
      other -> {:error, "invalid boolean for popular: #{other}"}
    end
  end

  defp parse_int(value, column) do
    case value |> to_string() |> String.replace(~r/[\s_]/, "") do
      "" ->
        {:ok, nil}

      digits ->
        case Integer.parse(digits) do
          {int, ""} -> {:ok, int}
          _ -> {:error, "invalid integer for #{column}: #{String.trim(to_string(value))}"}
        end
    end
  end

  # --- summary accumulation --------------------------------------------------

  defp tally(acc, make_op, model_op, version_op) do
    acc
    |> maybe_bump(:makes_created, make_op == :created)
    |> maybe_bump(:models_created, model_op == :created)
    |> bump(version_key(version_op))
  end

  defp version_key(:inserted), do: :versions_inserted
  defp version_key(:updated), do: :versions_updated

  defp maybe_bump(acc, _key, false), do: acc
  defp maybe_bump(acc, key, true), do: bump(acc, key)

  defp bump(acc, key), do: Map.update!(acc, key, &(&1 + 1))

  defp add_error(acc, index, reason) do
    acc
    |> Map.update!(:failed, &(&1 + 1))
    |> Map.update!(:errors, &[%{row: index, error: reason} | &1])
  end

  defp changeset_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp trimmed(nil), do: nil

  defp trimmed(value) do
    case String.trim(to_string(value)) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
