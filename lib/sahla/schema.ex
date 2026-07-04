defmodule Sahla.Schema do
  @moduledoc """
  Shared base for every Ecto schema in the catalog and beyond.

  `use Sahla.Schema` in place of `use Ecto.Schema` to inherit the
  project-wide conventions from §8 of the data model:

    * **UUID primary keys** — `@primary_key {:id, :binary_id, autogenerate: true}`.
      IDs are generated application-side by Ecto (semantically equivalent to the
      spec's `gen_random_uuid()` default) so associations are known before insert
      without a `RETURNING` round-trip. `@foreign_key_type :binary_id` keeps every
      reference a UUID too.
    * **Timestamps** — `@timestamps_opts [type: :utc_datetime]`. This is
      *second precision*: any "newest first" query MUST add a `desc: :id`
      tiebreaker, otherwise rows inserted in the same second sort arbitrarily.

  ## Conventions this module encodes (documentation, not code)

  ### Money

  Money is stored as **integer centimes (MAD)** — never floats. Columns are named
  `*_centimes` (e.g. `annual_premium_centimes`). Use `Sahla.Money` to convert to
  and from MAD and to format for display.

  ### Enums

  Enumerations are **`Ecto.Enum`-backed strings** paired with a database
  `CHECK` constraint, not Postgres enum types (which are painful to alter):

      # schema
      field :formula, Ecto.Enum, values: [:rc, :tiers_etendu, :tous_risques]

      # migration
      add :formula, :string, null: false
      create constraint(:products, :formula_must_be_valid,
        check: "formula IN ('rc', 'tiers_etendu', 'tous_risques')")

  `Ecto.Enum` guards the application boundary; the `CHECK` constraint guards
  against writes that bypass Ecto (raw SQL, seeds, migrations).

  ### Bilingual text

  French/Arabic text pairs are stored as two plain columns — `name_fr` /
  `name_ar` (and `description_fr` / `description_ar`, …) — rather than a single
  jsonb blob. Plain columns stay simple to query and directly indexable (see
  `Sahla.Migration.trigram_index/3` for fuzzy search on names).
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime]
    end
  end
end
