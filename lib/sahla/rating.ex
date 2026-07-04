defmodule Sahla.Rating do
  @moduledoc """
  Rating boundary: persists an immutable snapshot of a rating computation at
  funnel completion (§7.3, §9.1) so any displayed price is reproducible.

  `snapshot/3` writes the `Rating.Run` plus all `Quoting.Offer`s and links the
  quote — all in one transaction. It stores only a **non-PII** projection of the
  inputs (`safe_inputs/1`). There is deliberately no update or delete path:
  runs and offers are append-only.
  """
  import Ecto.Changeset, only: [change: 2]

  alias Sahla.Quoting.Offer
  alias Sahla.Rating.Run
  alias Sahla.Repo

  # Never persisted with the reproduction inputs.
  @pii_keys ~w(phone phone_enc phone_hash first_name last_name email plate ip user_agent)a
  @drop_keys @pii_keys ++ [:catalog]

  @doc """
  Persists a rating run and its offers atomically and links the quote.

  `meta` is `%{engine_version, table_versions, inputs, duration_us}`. A failure
  on any insert rolls the whole thing back and returns `{:error, changeset}`.
  """
  def snapshot(quote, offers, meta) do
    Repo.transaction(fn ->
      with {:ok, run} <- insert_run(quote, meta),
           :ok <- insert_offers(offers, run, quote),
           {:ok, _quote} <- Repo.update(change(quote, rating_run_id: run.id)) do
        run
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Projects an inputs map to a JSON-safe, PII-free form: drops contact fields and
  the catalog, and stringifies Decimals/Dates.
  """
  def safe_inputs(inputs) when is_map(inputs) do
    inputs
    |> Map.drop(@drop_keys)
    |> Map.new(fn {key, value} -> {to_string(key), json_safe(value)} end)
  end

  defp insert_run(quote, meta) do
    %Run{}
    |> Run.changeset(%{
      quote_id: quote.id,
      engine_version: meta.engine_version,
      table_versions: meta.table_versions,
      inputs: safe_inputs(meta.inputs || %{}),
      duration_us: meta.duration_us
    })
    |> Repo.insert()
  end

  defp insert_offers(offers, run, quote) do
    Enum.reduce_while(offers, :ok, fn offer, :ok ->
      case insert_offer(offer, run, quote) do
        {:ok, _offer} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp insert_offer(offer, run, quote) do
    %Offer{}
    |> Offer.changeset(%{
      rating_run_id: run.id,
      quote_id: quote.id,
      insurer_id: Map.get(offer.insurer, :id),
      product_id: Map.get(offer.product, :id),
      formula: offer.formula,
      annual_premium_centimes: offer.annual_premium_centimes,
      monthly_equiv_centimes:
        offer.monthly_equiv_centimes || round(offer.annual_premium_centimes / 12),
      breakdown: offer.breakdown,
      badges: Enum.map(offer.badges, &to_string(&1.kind)),
      rank: offer.rank
    })
    |> Repo.insert()
  end

  defp json_safe(%Decimal{} = value), do: Decimal.to_string(value)
  defp json_safe(%Date{} = value), do: Date.to_iso8601(value)
  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_map(value) and not is_struct(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), json_safe(v)} end)

  defp json_safe(value) when is_atom(value) and value not in [nil, true, false],
    do: to_string(value)

  defp json_safe(value), do: value
end
