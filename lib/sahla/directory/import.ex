defmodule Sahla.Directory.Import do
  @moduledoc """
  Bulk ingestion of the product/guarantee coverage matrix from insurer baremes
  (§8, §10.5).

  A CSV row identifies a product by `(insurer_slug, kind, formula)` and a
  coverage line by its `guarantee_code`, carrying the ceiling/franchise (integer
  centimes, nullable) and `included` flag. Each row is upserted idempotently:
  the product is found-or-created per `(insurer, kind, formula)` and the
  `product_guarantee` per `(product, guarantee_code)` — so re-importing the same
  file never duplicates rows.

  Ingestion is **safe**: a row with an unknown insurer slug or guarantee code,
  or an unparseable number, is reported and skipped — never fatal. The returned
  summary carries per-outcome counts and a row-level error list.

  Expected columns (header names, order-independent):

    * `insurer_slug` (required) — must resolve to an existing insurer
    * `formula` (required) — one of `Product.formulas/0`
    * `kind` (optional, default `auto`) — one of `Product.kinds/0`
    * `product_name_fr`, `product_name_ar` — required only when creating a product
    * `guarantee_code` (required) — one of `Guarantee.codes/0`
    * `included` (optional, default `true`)
    * `ceiling_centimes`, `franchise_centimes` (optional; blank → `nil`)
    * `notes_fr`, `notes_ar` (optional)
  """
  import Ecto.Query

  alias Sahla.CSV
  alias Sahla.Directory.{Guarantee, Insurer, Product, ProductGuarantee}
  alias Sahla.Repo

  @truthy ~w(1 true vrai oui yes y)
  @falsy ~w(0 false faux non no n)

  @empty %{
    products_created: 0,
    products_updated: 0,
    guarantees_inserted: 0,
    guarantees_updated: 0,
    failed: 0,
    errors: []
  }

  @type summary :: %{
          products_created: non_neg_integer(),
          products_updated: non_neg_integer(),
          guarantees_inserted: non_neg_integer(),
          guarantees_updated: non_neg_integer(),
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
    with {:ok, insurer} <- fetch_insurer(row),
         {:ok, formula} <- fetch_enum(row, "formula", Product.formulas(), required: true),
         {:ok, kind} <- fetch_enum(row, "kind", Product.kinds(), default: :auto),
         {:ok, code} <- fetch_enum(row, "guarantee_code", Guarantee.codes(), required: true),
         {:ok, values} <- parse_values(row) do
      upsert(insurer, kind, formula, code, values, index, acc)
    else
      {:error, reason} -> add_error(acc, index, reason)
    end
  end

  defp upsert(insurer, kind, formula, code, values, index, acc) do
    Repo.transaction(fn ->
      with {:ok, product, product_op} <- upsert_product(insurer, kind, formula, values),
           {:ok, _pg, guarantee_op} <- upsert_guarantee(product, code, values) do
        {product_op, guarantee_op}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {product_op, guarantee_op}} -> tally(acc, product_op, guarantee_op)
      {:error, reason} -> add_error(acc, index, reason)
    end
  end

  defp upsert_product(insurer, kind, formula, values) do
    attrs = %{
      insurer_id: insurer.id,
      kind: kind,
      formula: formula,
      name_fr: values.product_name_fr,
      name_ar: values.product_name_ar
    }

    case Repo.one(
           from p in Product,
             where: p.insurer_id == ^insurer.id and p.kind == ^kind and p.formula == ^formula
         ) do
      nil ->
        %Product{}
        |> Product.changeset(attrs)
        |> Repo.insert()
        |> tag(:created)

      product ->
        # Keep existing names when the row leaves them blank.
        product
        |> Product.changeset(%{
          attrs
          | name_fr: values.product_name_fr || product.name_fr,
            name_ar: values.product_name_ar || product.name_ar
        })
        |> Repo.update()
        |> tag(:updated)
    end
  end

  defp upsert_guarantee(product, code, values) do
    attrs = %{
      product_id: product.id,
      guarantee_code: code,
      included: values.included,
      ceiling_centimes: values.ceiling_centimes,
      franchise_centimes: values.franchise_centimes,
      notes_fr: values.notes_fr,
      notes_ar: values.notes_ar
    }

    case Repo.one(
           from pg in ProductGuarantee,
             where: pg.product_id == ^product.id and pg.guarantee_code == ^code
         ) do
      nil ->
        %ProductGuarantee{}
        |> ProductGuarantee.changeset(attrs)
        |> Repo.insert()
        |> tag(:inserted)

      existing ->
        existing
        |> ProductGuarantee.changeset(attrs)
        |> Repo.update()
        |> tag(:updated)
    end
  end

  defp tag({:ok, record}, op), do: {:ok, record, op}
  defp tag({:error, changeset}, _op), do: {:error, changeset_error(changeset)}

  # --- field extraction ------------------------------------------------------

  defp fetch_insurer(row) do
    case trimmed(row["insurer_slug"]) do
      nil ->
        {:error, "missing insurer_slug"}

      slug ->
        case Repo.get_by(Insurer, slug: slug) do
          nil -> {:error, "unknown insurer slug: #{slug}"}
          insurer -> {:ok, insurer}
        end
    end
  end

  # Resolves a string cell to a member of `allowed` (a list of atoms). `required:`
  # errors on a blank cell; `default:` supplies a value for one.
  defp fetch_enum(row, column, allowed, opts) do
    case trimmed(row[column]) do
      nil ->
        cond do
          Keyword.get(opts, :required, false) -> {:error, "missing #{column}"}
          Keyword.has_key?(opts, :default) -> {:ok, Keyword.fetch!(opts, :default)}
          true -> {:ok, nil}
        end

      value ->
        case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
          nil -> {:error, "unknown #{column}: #{value}"}
          atom -> {:ok, atom}
        end
    end
  end

  defp parse_values(row) do
    with {:ok, included} <- parse_bool(row["included"]),
         {:ok, ceiling} <- parse_centimes(row["ceiling_centimes"], "ceiling_centimes"),
         {:ok, franchise} <- parse_centimes(row["franchise_centimes"], "franchise_centimes") do
      {:ok,
       %{
         included: included,
         ceiling_centimes: ceiling,
         franchise_centimes: franchise,
         notes_fr: trimmed(row["notes_fr"]),
         notes_ar: trimmed(row["notes_ar"]),
         product_name_fr: trimmed(row["product_name_fr"]),
         product_name_ar: trimmed(row["product_name_ar"])
       }}
    end
  end

  defp parse_bool(value) do
    case value |> to_string() |> String.trim() |> String.downcase() do
      "" -> {:ok, true}
      v when v in @truthy -> {:ok, true}
      v when v in @falsy -> {:ok, false}
      other -> {:error, "invalid boolean for included: #{other}"}
    end
  end

  defp parse_centimes(value, column) do
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

  defp tally(acc, product_op, guarantee_op) do
    acc
    |> bump(product_key(product_op))
    |> bump(guarantee_key(guarantee_op))
  end

  defp product_key(:created), do: :products_created
  defp product_key(:updated), do: :products_updated
  defp guarantee_key(:inserted), do: :guarantees_inserted
  defp guarantee_key(:updated), do: :guarantees_updated

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
