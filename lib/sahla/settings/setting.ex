defmodule Sahla.Settings.Setting do
  @moduledoc """
  A single runtime setting (§8, §10.9): a unique `key` and a jsonb `value`.

  The value is stored in an envelope `%{"value" => v}` so any JSON — a boolean
  flag, a string disclaimer, a number, a list or an object — round-trips through
  the `:map` column. Callers use `Sahla.Settings`, which wraps/unwraps for them.
  """
  use Sahla.Schema

  import Ecto.Changeset

  schema "settings" do
    field :key, :string
    field :value, :map

    timestamps()
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key, :value])
    |> unique_constraint(:key)
  end
end
