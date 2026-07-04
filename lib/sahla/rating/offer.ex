defmodule Sahla.Rating.Offer do
  @moduledoc """
  One computed offer from `Sahla.Rating.Engine` (in-memory; persisted later by
  8vo.6). All amounts are integer centimes. `breakdown` itemizes the premium and
  its lines sum exactly to `annual_premium_centimes` (see `breakdown_total/1`).
  `estimated?` is true when the CRM was derived rather than supplied.
  """
  @enforce_keys [:insurer, :product, :formula, :annual_premium_centimes, :breakdown, :estimated?]
  defstruct [
    :insurer,
    :product,
    :formula,
    :annual_premium_centimes,
    :monthly_equiv_centimes,
    :breakdown,
    :estimated?,
    :rank,
    badges: []
  ]

  @type t :: %__MODULE__{}

  @doc "Sums every breakdown line; must equal `annual_premium_centimes`."
  def breakdown_total(%__MODULE__{breakdown: b}) do
    options_sum = b.options |> Enum.map(& &1.annual_centimes) |> Enum.sum()
    b.rc + options_sum + b.evcat + b.taxes + b.fees + b.rounding
  end
end
