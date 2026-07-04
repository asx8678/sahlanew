defmodule Sahla.Migration do
  @moduledoc """
  Reusable helpers for migrations that follow the shared schema conventions.

  Import into a migration alongside `Ecto.Migration`:

      use Ecto.Migration
      import Sahla.Migration

      def change do
        create trigram_index(:vehicle_models, :name)
      end
  """

  import Ecto.Migration, only: [index: 3]

  @doc """
  Builds a trigram GIN index on `column` of `table` for fuzzy text search.

  Returns an `%Ecto.Migration.Index{}` (a pure value — no migration context
  required), so wrap it in `create/1`:

      create trigram_index(:vehicle_models, :name)

  Requires the `pg_trgm` extension (enabled by the `EnableExtensions` migration).
  The index uses the `gin_trgm_ops` operator class, which powers `ILIKE '%…%'`
  and similarity searches on `name`-style columns.

  Options:

    * `:name` — override the generated index name
      (default `"<table>_<column>_trgm_idx"`).
  """
  def trigram_index(table, column, opts \\ []) do
    # String name (not an interpolated atom) — same SQL identifier, no atom churn.
    name = Keyword.get(opts, :name, "#{table}_#{column}_trgm_idx")
    index(table, ["#{column} gin_trgm_ops"], using: :gin, name: name)
  end
end
