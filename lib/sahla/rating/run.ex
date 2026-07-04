defmodule Sahla.Rating.Run do
  @moduledoc """
  An immutable snapshot of one rating computation (§7.3, §9.1). Stores the
  engine version, the `table_versions` (`%{code => version}`) and a **non-PII**
  `inputs` projection — enough to reproduce any displayed price for
  ACAPS/compliance. Append-only: there is no update path.
  """
  use Sahla.Schema

  import Ecto.Changeset

  schema "rating_runs" do
    field :engine_version, :string
    field :table_versions, :map
    field :inputs, :map
    field :duration_us, :integer

    belongs_to :quote, Sahla.Quoting.Quote
    has_many :offers, Sahla.Quoting.Offer, foreign_key: :rating_run_id

    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:quote_id, :engine_version, :table_versions, :inputs, :duration_us])
    |> validate_required([:quote_id, :engine_version])
    |> assoc_constraint(:quote)
  end
end
