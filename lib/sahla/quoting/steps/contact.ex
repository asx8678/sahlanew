defmodule Sahla.Quoting.Steps.Contact do
  @moduledoc """
  Step 4 — coordonnées + consentements (§5.2, §12). Pure embedded schema; no Repo.

  The phone must be a valid Moroccan number (it drives the OTP). Two consents are
  mandatory — the CGU/privacy acceptance and the transmission-to-partners consent
  (Law 09-08); marketing is optional. The consent booleans are captured here and
  persisted as immutable `consents` records by the context (lrs.3).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sahla.Quoting.Steps

  @fields [
    :first_name,
    :last_name,
    :phone,
    :email,
    :consent_cgu,
    :consent_transmission,
    :consent_marketing
  ]

  @primary_key false
  embedded_schema do
    field :first_name, :string
    field :last_name, :string
    field :phone, :string, redact: true
    field :email, :string
    field :consent_cgu, :boolean, default: false
    field :consent_transmission, :boolean, default: false
    field :consent_marketing, :boolean, default: false
  end

  @doc "Validates step 4, including the two mandatory consents."
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, @fields)
    |> validate_required([:first_name, :last_name, :phone])
    |> Steps.validate_ma_phone(:phone)
    |> validate_format(:email, ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/, message: "is not a valid email")
    |> Steps.validate_accepted(:consent_cgu)
    |> Steps.validate_accepted(:consent_transmission)

  end
end
