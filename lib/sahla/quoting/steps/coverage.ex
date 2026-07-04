defmodule Sahla.Quoting.Steps.Coverage do
  @moduledoc """
  Step 3 — couverture (§5.2). Pure embedded schema; no Repo.

  The formula is required; selected `options` must be known guarantee codes; the
  effect date may not be in the past.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sahla.Quoting.{Enums, Steps}

  @required [:formula]
  @optional [:options, :franchise_pref, :effect_date]

  @primary_key false
  embedded_schema do
    field :formula, Ecto.Enum, values: Enums.formulas()
    field :options, {:array, :string}, default: []
    field :franchise_pref, Ecto.Enum, values: Enums.franchise_prefs()
    field :effect_date, :date
  end

  @doc "Validates step 3. `opts[:today]` (defaults to today) anchors the effect-date check."
  def changeset(coverage, attrs, opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())

    coverage
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_subset(:options, Enums.option_codes())
    |> Steps.validate_not_past(:effect_date, today)
  end
end
