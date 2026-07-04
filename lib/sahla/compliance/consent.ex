defmodule Sahla.Compliance.Consent do
  @moduledoc """
  A recorded consent (§5.2 step 4, §8, §12) for CNDP (Law 09-08) compliance:
  which `kind` (CGU+privacy, transmission-to-broker, marketing) the user granted
  or refused, the legal `text_version` shown, the request `ip` and `granted_at`.

  Stores **no PII beyond the IP** — only the version, the flag and a SafeRaw'd
  `metadata` projection. Written exclusively by `Sahla.Compliance`.
  """
  use Sahla.Schema

  import Ecto.Changeset

  @kinds [:cgu, :transmission, :marketing]
  @required_kinds [:cgu, :transmission]

  schema "consents" do
    field :kind, Ecto.Enum, values: @kinds
    field :text_version, :string
    field :granted, :boolean, default: false
    field :ip, Sahla.Types.IP
    field :granted_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :quote, Sahla.Quoting.Quote

    timestamps()
  end

  @doc "All consent kinds."
  def kinds, do: @kinds

  @doc "Kinds that must be granted before the lead gate opens."
  def required_kinds, do: @required_kinds

  def changeset(consent, attrs) do
    consent
    |> cast(attrs, [:quote_id, :kind, :text_version, :granted, :ip, :granted_at, :metadata])
    |> validate_required([:quote_id, :kind, :text_version, :granted, :granted_at])
    |> assoc_constraint(:quote)
    |> check_constraint(:kind, name: :consents_kind_must_be_valid)
    |> unique_constraint([:quote_id, :kind])
  end
end
