defmodule Sahla.Repo.Migrations.CreateAuditEntries do
  use Ecto.Migration

  def up do
    create table(:audit_entries) do
      add :admin_id, references(:admins, on_delete: :nilify_all)
      add :action, :string, null: false
      add :entity, :string, null: false
      add :entity_id, :string
      # Non-PII projections only (SafeRaw); never raw encrypted/external payloads.
      add :before, :map, null: false, default: %{}
      add :after, :map, null: false, default: %{}
      add :ip, :inet
      add :at, :utc_datetime, null: false
    end

    # Newest-first with a second-precision tiebreaker (Lessons).
    create index(:audit_entries, ["at DESC", "id DESC"], name: :audit_entries_recency_index)
    create index(:audit_entries, [:entity, :entity_id])

    # Append-only: a DB trigger rejects any UPDATE/DELETE so history can't be
    # rewritten — stronger than app-only discipline (§10.10, §12).
    execute """
    CREATE OR REPLACE FUNCTION audit_entries_immutable() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'audit_entries is append-only; % is not permitted', TG_OP;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER audit_entries_no_mutation
      BEFORE UPDATE OR DELETE ON audit_entries
      FOR EACH ROW EXECUTE FUNCTION audit_entries_immutable();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS audit_entries_no_mutation ON audit_entries"
    execute "DROP FUNCTION IF EXISTS audit_entries_immutable()"
    drop table(:audit_entries)
  end
end
