defmodule Sahla.Release do
  @moduledoc """
  Tasks that run inside the built release, where Mix is not available.

  Invoked from the release binary (see `rel/overlays/bin/migrate`):

      bin/sahla eval "Sahla.Release.migrate()"
      bin/sahla eval "Sahla.Release.rollback(Sahla.Repo, 20260702082847)"

  `deploy.sh` runs `migrate/0` before flipping the `current` symlink so a
  release never serves against an unmigrated schema (§13.5).
  """

  alias Ecto.Migrator

  @app :sahla

  @doc "Runs all pending migrations for every configured repo."
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _fun_return, _apps} = Migrator.with_repo(repo, &Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc "Rolls the given repo back down to (and including) `version`."
  def rollback(repo, version) do
    load_app()
    {:ok, _fun_return, _apps} = Migrator.with_repo(repo, &Migrator.run(&1, :down, to: version))
    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  # Load (not start) the app so config — including runtime.exs — is
  # available; Migrator.with_repo starts only what the repo needs.
  defp load_app do
    Application.ensure_loaded(@app)
  end
end
