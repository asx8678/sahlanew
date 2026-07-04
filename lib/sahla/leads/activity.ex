defmodule Sahla.Leads.Activity do
  @moduledoc """
  An entry on a lead's timeline (§8, §10.2): a note, a logged call/SMS/email, a
  status change or a scheduled meeting. `admin_id` is null for system-generated
  entries.
  """
  use Sahla.Schema

  import Ecto.Changeset

  @kinds [:note, :appel, :sms, :whatsapp, :email, :statut, :rdv]

  schema "lead_activities" do
    field :kind, Ecto.Enum, values: @kinds
    field :body, :string
    field :metadata, :map, default: %{}
    field :happened_at, :utc_datetime

    belongs_to :lead, Sahla.Leads.Lead
    belongs_to :admin, Sahla.Accounts.Admin

    timestamps()
  end

  @doc "Valid activity kinds."
  def kinds, do: @kinds

  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [:lead_id, :admin_id, :kind, :body, :metadata, :happened_at])
    |> validate_required([:lead_id, :kind])
    |> put_happened_at()
    |> assoc_constraint(:lead)
    |> assoc_constraint(:admin)
    |> check_constraint(:kind, name: :lead_activities_kind_must_be_valid)
  end

  defp put_happened_at(changeset) do
    if get_field(changeset, :happened_at) do
      changeset
    else
      put_change(changeset, :happened_at, DateTime.truncate(DateTime.utc_now(), :second))
    end
  end
end
