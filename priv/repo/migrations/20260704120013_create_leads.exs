defmodule Sahla.Repo.Migrations.CreateLeads do
  use Ecto.Migration

  @statuses ~w(nouveau rdv_planifie contacte devis_envoye relance gagne perdu)
  @kinds ~w(note appel sms whatsapp email statut rdv)

  def change do
    create table(:leads) do
      add :quote_id, references(:quotes, on_delete: :restrict), null: false
      add :offer_id, :binary_id
      add :status, :string, null: false, default: "nouveau"
      add :loss_reason, :string
      add :assigned_admin_id, references(:admins, on_delete: :nilify_all)
      add :callback_at, :utc_datetime
      add :source, :string
      add :priority, :integer, null: false, default: 0
      add :converted_policy_ref, :string
      add :commission_centimes, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:leads, [:quote_id])
    create index(:leads, [:status, :assigned_admin_id])
    create index(:leads, [:callback_at])

    # Fast lookup of still-active leads.
    create index(:leads, [:status],
             where: "status NOT IN ('gagne','perdu')",
             name: :leads_active_status_index
           )

    statuses = Enum.map_join(@statuses, ",", &"'#{&1}'")

    create constraint(:leads, :leads_status_must_be_valid, check: "status IN (#{statuses})")

    # A perdu lead must have a loss_reason; no other status may.
    create constraint(:leads, :leads_loss_reason_guard,
             check:
               "(status = 'perdu' AND loss_reason IS NOT NULL) OR (status <> 'perdu' AND loss_reason IS NULL)"
           )

    create table(:lead_activities) do
      add :lead_id, references(:leads, on_delete: :delete_all), null: false
      add :admin_id, references(:admins, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :body, :text
      add :metadata, :map, null: false, default: %{}
      add :happened_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:lead_activities, [:lead_id])

    kinds = Enum.map_join(@kinds, ",", &"'#{&1}'")

    create constraint(:lead_activities, :lead_activities_kind_must_be_valid,
             check: "kind IN (#{kinds})"
           )
  end
end
