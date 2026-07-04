defmodule Sahla.Quoting.Enums do
  @moduledoc """
  Canonical enum value lists for the funnel (§5.2), shared by `Quoting.Quote`
  and the per-step embedded schemas so the two never drift. ASCII, no accents,
  for stable code/DB keys.
  """

  def statuses, do: [:draft, :completed, :expired]

  # personnel / trajet domicile-travail / professionnel / taxi-VTC
  def usages, do: [:personnel, :trajet_domicile_travail, :professionnel, :taxi_vtc]

  # garage fermé / parking surveillé / rue
  def parkings, do: [:garage, :parking_surveille, :rue]

  def fuels, do: [:essence, :diesel, :hybride, :electrique]

  def formulas, do: [:rc, :tiers_etendu, :tous_risques]

  # basse / standard / élevée
  def franchise_prefs, do: [:basse, :standard, :elevee]

  @doc "Formulas that require a declared vehicle value."
  def valued_formulas, do: [:tiers_etendu, :tous_risques]

  @doc "The 10 guarantee option codes selectable in step 3 (§8)."
  def option_codes do
    ~w(rc vol incendie bris_glace pta defense_recours assistance individuelle evenements_climatiques evcat)
  end
end
