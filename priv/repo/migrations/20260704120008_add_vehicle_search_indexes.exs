defmodule Sahla.Repo.Migrations.AddVehicleSearchIndexes do
  use Ecto.Migration

  # Accent-insensitive trigram search: the plain `name gin_trgm_ops` indexes
  # from CreateVehicle* can't fold accents, so autocomplete matches against an
  # unaccented, index-backed expression instead.
  @tables [:vehicle_makes, :vehicle_models, :vehicle_versions]

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS unaccent"

    # `unaccent(text)` is only STABLE (depends on the default dictionary), so it
    # can't back a functional index. The two-arg form with an explicit
    # dictionary is safe to wrap as IMMUTABLE (the documented pg recipe).
    execute """
    CREATE OR REPLACE FUNCTION sahla_unaccent(text)
    RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT AS
    $$ SELECT public.unaccent('public.unaccent', $1) $$
    """

    for table <- @tables do
      execute "CREATE INDEX #{table}_name_unaccent_trgm_idx ON #{table} USING gin (sahla_unaccent(name) gin_trgm_ops)"
    end
  end

  def down do
    for table <- Enum.reverse(@tables) do
      execute "DROP INDEX IF EXISTS #{table}_name_unaccent_trgm_idx"
    end

    execute "DROP FUNCTION IF EXISTS sahla_unaccent(text)"
    # The unaccent extension is left installed — it is shared and harmless.
  end
end
