defmodule Sahla.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Version-agnostic Oban migration (hard Lesson): `up/0` with no pinned version
  # always installs the schema the running Oban expects, so upgrades never break.
  def up, do: Oban.Migration.up()

  # `version: 1` unwinds every Oban schema version cleanly on rollback.
  def down, do: Oban.Migration.down(version: 1)
end
