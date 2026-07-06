defmodule Sahla.Quoting.Steps.Driver do
  @moduledoc """
  Step 2 — conducteur (§5.2). Pure embedded schema; no Repo.

  Enforces date sanity (birth/license not in the future) and the legal-age rule:
  the licence date must be on or after the driver's 18th birthday. `crm`, when
  the driver knows it, must sit inside the CRM band 0.50–2.50; leaving it blank
  ("je ne sais pas") is allowed and estimated downstream.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sahla.Quoting.Steps

  @required [:birth_date, :license_date]
  @optional [
    :is_public_servant,
    :current_insurer_id,
    :current_expiry,
    :at_fault_claims_36m,
    :crm,
    :releve_doc_path
  ]

  @primary_key false
  embedded_schema do
    field :birth_date, :date
    field :license_date, :date
    field :is_public_servant, :boolean, default: false
    field :current_insurer_id, :binary_id
    field :current_expiry, :date
    field :at_fault_claims_36m, :integer
    field :crm, :decimal
    field :releve_doc_path, :string
  end

  @doc "Validates step 2. `opts[:today]` (defaults to today) anchors the date checks."
  def changeset(driver, attrs, opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())

    attrs =
      attrs
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> maybe_nil_empty(["current_insurer_id", "crm"])

    driver
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> Steps.validate_not_future(:birth_date, today)
    |> Steps.validate_not_future(:license_date, today)
    |> Steps.validate_licensed_of_age(:birth_date, :license_date)
    |> validate_number(:at_fault_claims_36m, greater_than_or_equal_to: 0)
    |> validate_number(:crm,
      greater_than_or_equal_to: Decimal.new("0.50"),
      less_than_or_equal_to: Decimal.new("2.50")
    )
  end

  defp maybe_nil_empty(attrs, keys) do
    Enum.reduce(keys, attrs, fn key, acc ->
      case Map.get(acc, key) do
        "" -> Map.put(acc, key, nil)
        _ -> acc
      end
    end)
  end
end
