defmodule Sahla.Leads.Lead do
  @moduledoc """
  A lead — the conversion record for a completed quote (§8, §10.2). One lead per
  quote.

  `status`, `assigned_admin_id` and `commission_centimes` are **admin-only**:
  the base `changeset/2` (creation) never casts them; dedicated changesets do.
  A `perdu` lead must carry a `loss_reason` and no other status may — enforced in
  both the changeset and a DB CHECK.
  """
  use Sahla.Schema

  import Ecto.Changeset

  # ASCII, no accents, so code/DB keys stay stable.
  @statuses [:nouveau, :rdv_planifie, :contacte, :devis_envoye, :relance, :gagne, :perdu]

  schema "leads" do
    field :status, Ecto.Enum, values: @statuses, default: :nouveau
    field :loss_reason, :string
    field :callback_at, :utc_datetime
    field :source, :string
    field :priority, :integer, default: 0
    field :converted_policy_ref, :string
    field :commission_centimes, :integer
    # FK to offers is added when that table exists (8vo.6/offers).
    field :offer_id, :binary_id

    belongs_to :quote, Sahla.Quoting.Quote
    belongs_to :assigned_admin, Sahla.Accounts.Admin
    has_many :activities, Sahla.Leads.Activity

    timestamps()
  end

  @doc "Valid lead statuses."
  def statuses, do: @statuses

  @doc "Creation changeset — never casts admin-only status/assignment/commission."
  def changeset(lead, attrs) do
    lead
    |> cast(attrs, [:quote_id, :offer_id, :source, :priority, :callback_at])
    |> validate_required([:quote_id])
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> assoc_constraint(:quote)
    |> unique_constraint(:quote_id)
  end

  @doc "Status transition changeset with the perdu/loss_reason guard."
  def status_changeset(lead, attrs) do
    lead
    |> cast(attrs, [:status, :loss_reason])
    |> validate_required([:status])
    |> validate_loss_reason()
    |> check_constraint(:status, name: :leads_status_must_be_valid)
    |> check_constraint(:loss_reason, name: :leads_loss_reason_guard)
  end

  @doc "Assignment changeset (admin, callback, priority)."
  def assignment_changeset(lead, attrs) do
    lead
    |> cast(attrs, [:assigned_admin_id, :callback_at, :priority])
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> assoc_constraint(:assigned_admin)
  end

  @doc "Conversion changeset — commission and policy reference on a won lead."
  def conversion_changeset(lead, attrs) do
    lead
    |> cast(attrs, [:commission_centimes, :converted_policy_ref])
    |> validate_number(:commission_centimes, greater_than_or_equal_to: 0)
  end

  defp validate_loss_reason(changeset) do
    status = get_field(changeset, :status)
    loss_reason = get_field(changeset, :loss_reason)

    cond do
      status == :perdu ->
        validate_required(changeset, [:loss_reason])

      loss_reason in [nil, ""] ->
        changeset

      true ->
        add_error(changeset, :loss_reason, "is only allowed when status is perdu")
    end
  end
end
