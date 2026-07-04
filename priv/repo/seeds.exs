# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Sahla.Repo.insert!(%Sahla.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Runtime settings: feature flags (default OFF), display name, disclaimers.
# Idempotent — never clobbers a value ops has already changed.
Sahla.Settings.seed_defaults()
