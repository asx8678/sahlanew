defmodule Sahla.Quoting.Quote do
  @moduledoc """
  The funnel's single source of truth (§8): every answer autosaves onto this row.

  PII discipline (Lessons, §12): the phone is stored encrypted in `phone_enc`
  (`Sahla.Encrypted.Binary`) with a **keyed HMAC** `phone_hash` for lookup —
  both derived from the virtual `phone` field. System-managed fields (`status`,
  `phone_verified_at`, `phone_hash`, `phone_enc`, `rating_run_id`) are never cast
  from the autosave changeset; `token` is generated, not user-supplied.
  """
  use Sahla.Schema

  import Ecto.Changeset

  alias Sahla.Quoting.Enums

  # User-editable answers the autosave changeset may cast. Excludes token,
  # status, phone_verified_at, rating_run_id and the derived phone/releve columns.
  @castable [
    :locale,
    :current_step,
    :plate,
    :is_new_ww,
    :make_id,
    :model_id,
    :version_id,
    :fiscal_power,
    :fuel,
    :first_registration,
    :vehicle_value_centimes,
    :usage,
    :city_id,
    :parking,
    :birth_date,
    :license_date,
    :is_public_servant,
    :current_insurer_id,
    :current_expiry,
    :at_fault_claims_36m,
    :crm,
    :releve_doc_path,
    :releve_doc_meta,
    :formula,
    :options,
    :franchise_pref,
    :effect_date,
    :first_name,
    :last_name,
    :phone,
    :email,
    :utm,
    :ip,
    :user_agent
  ]

  schema "quotes" do
    field :token, :string
    field :status, Ecto.Enum, values: Enums.statuses(), default: :draft
    field :current_step, :integer, default: 1
    field :locale, :string, default: "fr"

    # Vehicle
    field :plate, :string
    field :is_new_ww, :boolean, default: false
    field :make_id, :binary_id
    field :model_id, :binary_id
    field :version_id, :binary_id
    field :fiscal_power, :integer
    field :fuel, Ecto.Enum, values: Enums.fuels()
    field :first_registration, :date
    field :vehicle_value_centimes, :integer
    field :usage, Ecto.Enum, values: Enums.usages()
    field :city_id, :binary_id
    field :parking, Ecto.Enum, values: Enums.parkings()

    # Driver
    field :birth_date, :date
    field :license_date, :date
    field :is_public_servant, :boolean, default: false
    field :current_insurer_id, :binary_id
    field :current_expiry, :date
    field :at_fault_claims_36m, :integer
    field :crm, :decimal
    field :releve_doc_path, :string
    field :releve_doc_meta, :map, virtual: true, redact: true
    field :releve_doc_meta_enc, Sahla.Encrypted.Map, redact: true

    # Coverage
    field :formula, Ecto.Enum, values: Enums.formulas()
    field :options, {:array, :string}, default: []
    field :franchise_pref, Ecto.Enum, values: Enums.franchise_prefs()
    field :effect_date, :date

    # Contact (nullable until step 4)
    field :first_name, :string
    field :last_name, :string
    field :phone, :string, virtual: true, redact: true
    field :phone_enc, Sahla.Encrypted.Binary, redact: true
    field :phone_hash, Sahla.Hashed.HMAC, redact: true
    field :email, :string
    field :phone_verified_at, :utc_datetime
    # Set when a data-subject erasure scrubs this row's PII (§12); never cast.
    field :erased_at, :utc_datetime

    # Context
    field :utm, :map, default: %{}
    field :ip, Sahla.Types.IP
    field :user_agent, :string
    # FK to rating_runs is added when that table exists (8vo.6).
    field :rating_run_id, :binary_id

    timestamps()
  end

  @doc "A fresh URL-safe token for a new quote."
  def new_token, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc "Creates a draft quote with a generated token."
  def create_changeset(quote, attrs \\ %{}) do
    quote
    |> changeset(attrs)
    |> put_change(:token, new_token())
    |> unique_constraint(:token)
  end

  @doc """
  Autosave changeset for user answers. Derives the encrypted/hashed phone from
  the virtual `phone` field; never casts system-managed fields.
  """
  def changeset(quote, attrs) do
    quote
    |> cast(attrs, @castable)
    |> validate_number(:vehicle_value_centimes, greater_than_or_equal_to: 0)
    |> validate_number(:crm,
      greater_than_or_equal_to: Decimal.new("0.50"),
      less_than_or_equal_to: Decimal.new("2.50")
    )
    |> validate_length(:options, max: 20)
    |> put_phone()
    |> put_releve_doc_meta()
    |> assoc_checks()
  end

  @doc """
  Marks the phone as verified at `verified_at`. System-managed: set only by the
  OTP flow after a successful, phone-bound verification — never from autosave.
  """
  def mark_phone_verified(quote, verified_at) do
    change(quote, phone_verified_at: verified_at)
  end

  defp put_phone(changeset) do
    case get_change(changeset, :phone) do
      nil ->
        changeset

      phone ->
        changeset
        |> put_change(:phone_enc, phone)
        |> put_change(:phone_hash, phone)
        |> reset_verification_if_phone_changed(phone)
    end
  end

  defp put_releve_doc_meta(changeset) do
    case get_change(changeset, :releve_doc_meta) do
      nil ->
        changeset

      meta when is_map(meta) ->
        put_change(changeset, :releve_doc_meta_enc, meta)
    end
  end

  # The prior bypass bug (§7.3): editing the phone after verifying kept the old
  # verification. Any change to a different number clears `phone_verified_at`.
  defp reset_verification_if_phone_changed(changeset, phone) do
    if changeset.data.phone_enc == phone do
      changeset
    else
      put_change(changeset, :phone_verified_at, nil)
    end
  end

  defp assoc_checks(changeset) do
    changeset
    |> foreign_key_constraint(:make_id)
    |> foreign_key_constraint(:model_id)
    |> foreign_key_constraint(:version_id)
    |> foreign_key_constraint(:city_id)
    |> foreign_key_constraint(:current_insurer_id)
    |> check_constraint(:status, name: :quotes_status_must_be_valid)
    |> check_constraint(:usage, name: :quotes_usage_must_be_valid)
    |> check_constraint(:parking, name: :quotes_parking_must_be_valid)
    |> check_constraint(:formula, name: :quotes_formula_must_be_valid)
    |> check_constraint(:franchise_pref, name: :quotes_franchise_pref_must_be_valid)
  end
end
