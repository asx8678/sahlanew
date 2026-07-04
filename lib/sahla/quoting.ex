defmodule Sahla.Quoting do
  @moduledoc """
  The funnel boundary (§7.2, §7.3). LiveViews never touch the Repo: every create,
  resume and autosave flows through this context.

  Autosave is per step — `upsert_step/3` validates one step with its embedded
  schema and persists only that step's fields onto the `quotes` row, returning
  field-keyed errors on failure. Expired quotes are not resumable.
  """
  import Ecto.Query, only: [from: 2]

  alias Sahla.Leads.Lead
  alias Sahla.Quoting.{Quote, Steps}
  alias Sahla.Repo

  # Ordered funnel steps. The atom is the public API; the integer is `current_step`.
  @steps [vehicle: 1, driver: 2, coverage: 3, contact: 4]
  @step_names Keyword.keys(@steps)

  # Marketing attribution keys we keep; everything else in a raw param map is dropped.
  @utm_keys ~w(utm_source utm_medium utm_campaign utm_term utm_content gclid fbclid)
  @utm_value_max 255

  @doc """
  Creates a draft quote with a generated unique token. Accepts `:locale`, `:ip`,
  `:user_agent` and a raw `:utm` map (sanitized to a known projection). The
  citext unique index on `token` makes concurrent creates collision-safe.
  """
  def create_quote(attrs \\ %{}) do
    attrs = Map.new(attrs)

    %Quote{}
    |> Quote.create_changeset(%{
      locale: Map.get(attrs, :locale, "fr"),
      ip: Map.get(attrs, :ip),
      user_agent: Map.get(attrs, :user_agent),
      utm: sanitize_utm(Map.get(attrs, :utm, %{}))
    })
    |> Repo.insert()
  end

  @doc """
  Fetches a resumable quote by token. Returns `nil` for an unknown token or an
  expired quote (an expired quote is not resumable).
  """
  def get_quote_by_token(token) when is_binary(token) do
    case Repo.get_by(Quote, token: token) do
      %Quote{status: :expired} -> nil
      %Quote{} = quote -> quote
      nil -> nil
    end
  end

  @doc """
  Autosaves one funnel step. Validates `params` with the step's embedded schema
  (`step` is `:vehicle | :driver | :coverage | :contact`), then persists only
  that step's changed fields and advances `current_step`. Returns
  `{:ok, quote}` or `{:error, changeset}` with field-keyed errors.
  """
  def upsert_step(%Quote{} = quote, step, params) when step in @step_names do
    step_changeset = validate_step(quote, step, params)

    if step_changeset.valid? do
      quote
      |> Quote.changeset(Map.put(step_changeset.changes, :current_step, advance(quote, step)))
      |> Repo.update()
    else
      {:error, step_changeset}
    end
  end

  @doc "Builds (without persisting) the validated changeset for a single step."
  def validate_step(%Quote{} = quote, :vehicle, params) do
    Steps.Vehicle.changeset(%Steps.Vehicle{}, params, formula: quote.formula)
  end

  def validate_step(%Quote{}, :driver, params) do
    Steps.Driver.changeset(%Steps.Driver{}, params)
  end

  def validate_step(%Quote{}, :coverage, params) do
    Steps.Coverage.changeset(%Steps.Coverage{}, params)
  end

  def validate_step(%Quote{}, :contact, params) do
    Steps.Contact.changeset(%Steps.Contact{}, params)
  end

  @doc "Marks a quote expired (used by the abandonment sweeper). No longer resumable."
  def expire_quote(%Quote{} = quote) do
    quote
    |> Ecto.Changeset.change(status: :expired)
    |> Repo.update()
  end

  @doc "Returns the ordered `{step_atom, number}` pairs of the funnel."
  def steps, do: @steps

  @doc """
  A locale-correct absolute resume URL for `quote`. The token is itself the
  resume credential (no separate secret); Arabic resumes on the `/ar` mirror.
  """
  def resume_url(quote, locale \\ "fr")

  def resume_url(%Quote{token: token}, locale) do
    SahlaWeb.Endpoint.url() <> resume_path(token, locale)
  end

  defp resume_path(token, "ar"), do: "/ar/devis/#{token}"
  defp resume_path(token, _locale), do: "/devis/#{token}"

  @doc """
  Abandoned draft quotes for the notifications follow-up job: `status == :draft`,
  no lead attached, and untouched since `cutoff` (`updated_at < cutoff`).
  Newest-first with a `desc: :id` tiebreaker (Lessons). Completed and expired
  quotes are excluded.
  """
  def list_abandoned_drafts(cutoff) do
    Repo.all(
      from q in Quote,
        left_join: l in Lead,
        on: l.quote_id == q.id,
        where: q.status == :draft and is_nil(l.id) and q.updated_at < ^cutoff,
        order_by: [desc: q.updated_at, desc: q.id]
    )
  end

  # current_step only moves forward, so editing an earlier step never rewinds progress.
  defp advance(%Quote{current_step: current}, step) do
    max(current || 1, Keyword.fetch!(@steps, step))
  end

  defp sanitize_utm(raw) when is_map(raw) do
    raw
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.take(@utm_keys)
    |> Map.new(fn {key, value} ->
      {key, value |> to_string() |> String.slice(0, @utm_value_max)}
    end)
  end

  defp sanitize_utm(_), do: %{}
end
