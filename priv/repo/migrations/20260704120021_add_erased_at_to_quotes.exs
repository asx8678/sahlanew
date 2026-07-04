defmodule Sahla.Repo.Migrations.AddErasedAtToQuotes do
  use Ecto.Migration

  # Tombstone marker for the §12/§10.3 erase-person action: set when a quote's
  # PII is scrubbed, so an erased row is distinguishable from one that never held
  # that field. The row itself is retained for anonymous stats.
  def change do
    alter table(:quotes) do
      add :erased_at, :utc_datetime
    end
  end
end
