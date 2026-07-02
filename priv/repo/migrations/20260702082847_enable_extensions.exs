defmodule Sahla.Repo.Migrations.EnableExtensions do
  use Ecto.Migration

  # Shared PostgreSQL extensions relied on across the schema:
  #   * pg_trgm — trigram indexes for fuzzy text search (makes, models, cities…)
  #   * citext  — case-insensitive text for tokens/emails (quotes.token, emails)
  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    execute("CREATE EXTENSION IF NOT EXISTS citext")
  end

  def down do
    execute("DROP EXTENSION IF EXISTS citext")
    execute("DROP EXTENSION IF EXISTS pg_trgm")
  end
end
