defmodule Sahla.Quoting do
  @moduledoc """
  The funnel boundary (§7.2, §7.3). LiveViews never touch the Repo: every create,
  resume and autosave flows through this context.

  Autosave is per step — `upsert_step/3` validates one step with its embedded
  schema and persists only that step's fields onto the `quotes` row, returning
  field-keyed errors on failure. Expired quotes are not resumable.
  """
  import Ecto.Changeset, only: [change: 2]
  import Ecto.Query, only: [from: 2]

  alias Sahla.Compliance
  alias Sahla.Leads.Lead
  alias Sahla.Quoting.{Offer, Quote, Steps}
  alias Sahla.Rating
  alias Sahla.Rating.{Engine, Fixtures, Tables}
  alias Sahla.Repo

  # Ordered funnel steps. The atom is the public API; the integer is `current_step`.
  @steps [vehicle: 1, driver: 2, coverage: 3, contact: 4]
  @step_names Keyword.keys(@steps)

  # Marketing attribution keys we keep; everything else in a raw param map is dropped.
  @utm_keys ~w(utm_source utm_medium utm_campaign utm_term utm_content gclid fbclid)
  @utm_value_max 255

  @doc """
  Creates a draft quote with a generated unique token. Accepts `:locale`,
  `:ip`, `:user_agent`, a raw `:utm` map (sanitized to a known projection),
  and optional vehicle hints (`:plate`, `:is_new_ww`) so the homepage can
  pre-fill the first funnel step. The citext unique index on `token` makes
  concurrent creates collision-safe.
  """
  def create_quote(attrs \\ %{}) do
    attrs = Map.new(attrs)

    base = %{
      locale: Map.get(attrs, :locale, "fr"),
      current_step: Map.get(attrs, :current_step, 1),
      ip: Map.get(attrs, :ip),
      user_agent: Map.get(attrs, :user_agent),
      utm: sanitize_utm(Map.get(attrs, :utm, %{}))
    }

    # The homepage front door may seed the vehicle step (plate or WW toggle);
    # everything else flows through `upsert_step/3`.
    vehicle_hints =
      [:plate, :is_new_ww]
      |> Enum.reject(fn key -> is_nil(Map.get(attrs, key)) end)
      |> Map.new(fn key -> {key, Map.get(attrs, key)} end)

    %Quote{}
    |> Quote.create_changeset(Map.merge(base, vehicle_hints))
    |> Repo.insert()
  end

  @doc """
  Fetches a resumable quote by token. Returns `nil` for an unknown token or an
  expired quote (an expired quote is not resumable).
  """
  def get_quote_by_token(token) when is_binary(token) do
    case get_quote_for_resume(token) do
      {:ok, quote} -> quote
      _ -> nil
    end
  end

  @doc """
  Fetches a quote by token, preserving the expired status so the caller can
  render an appropriate screen. Returns `{:ok, quote}`, `{:error, :expired}`,
  or `{:error, :not_found}`.
  """
  def get_quote_for_resume(token) when is_binary(token) do
    case Repo.get_by(Quote, token: token) do
      %Quote{status: :expired} = quote -> {:error, :expired, quote}
      %Quote{} = quote -> {:ok, quote}
      nil -> {:error, :not_found}
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

    # Progressive autosave: persist whatever the user has entered so far,
    # even if the full step is not yet valid. Step-level validation errors
    # are returned to the LiveView for inline display.
    attrs =
      params
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.put("current_step", advance(quote, step))

    case Repo.update(Quote.changeset(quote, attrs)) do
      {:ok, quote} ->
        if step_changeset.valid? do
          {:ok, quote}
        else
          {:error, step_changeset}
        end

      error ->
        error
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

  @doc """
  Completes a quote if all four steps are valid, runs the rating engine, and
  persists an immutable snapshot plus offers. Sets `status` to `:completed`
  and `rating_run_id` atomically.

  Returns `{:ok, %{quote: quote, run: run, offers: offers}}` on success,
  `{:error, :incomplete}` if any step is invalid, or `{:error, changeset}` if
  the snapshot transaction fails.
  """
  def complete_quote(%Quote{status: :completed, rating_run_id: run_id} = quote)
      when is_binary(run_id) do
    run = Repo.get!(Rating.Run, run_id)
    offers = Repo.all(from o in Offer, where: o.rating_run_id == ^run.id)
    {:ok, %{quote: quote, run: run, offers: offers}}
  end

  def complete_quote(%Quote{} = quote) do
    with :ok <- validate_all_steps(quote) do
      run_and_snapshot(quote)
    end
  end

  defp validate_all_steps(quote) do
    consents = Compliance.consents_for(quote)

    consent_map =
      Map.new([:cgu, :transmission, :marketing], fn kind ->
        granted = Enum.any?(consents, fn c -> c.kind == kind and c.granted end)
        {consent_key(kind), granted}
      end)

    quote_fields =
      quote
      |> Map.from_struct()
      |> Map.put(:phone, phone_from_quote(quote))
      |> Map.merge(consent_map)
      |> Map.take(step_field_names())

    all_valid? =
      Enum.all?(@step_names, fn step ->
        params = Map.take(quote_fields, step_field_names(step))
        validate_step(quote, step, params).valid?
      end)

    if all_valid?, do: :ok, else: {:error, :incomplete}
  end

  defp consent_key(:cgu), do: :consent_cgu
  defp consent_key(:transmission), do: :consent_transmission
  defp consent_key(:marketing), do: :consent_marketing

  defp run_and_snapshot(quote) do
    tables = Tables.load_all()
    catalog = Fixtures.build_catalog()
    inputs = build_engine_inputs(quote, catalog)

    {duration_us, offers} =
      :timer.tc(fn -> Engine.run(inputs, tables) end)

    meta = %{
      engine_version: Mix.Project.config()[:version],
      table_versions: table_versions(tables),
      inputs: inputs,
      duration_us: duration_us
    }

    case Rating.snapshot(quote, offers, meta) do
      {:ok, run} ->
        quote =
          quote
          |> change(status: :completed)
          |> Repo.update!()

        {:ok, %{quote: quote, run: run, offers: offers}}

      error ->
        error
    end
  end

  defp build_engine_inputs(quote, catalog) do
    risk_zone = Sahla.Cities.get_risk_zone(quote.city_id)

    %{
      fiscal_power: quote.fiscal_power,
      fuel: to_string(quote.fuel),
      usage: to_string(quote.usage),
      risk_zone: to_string(risk_zone),
      vehicle_value_centimes: quote.vehicle_value_centimes,
      franchise_pref: to_string(quote.franchise_pref),
      options: quote.options || [],
      is_public_servant: quote.is_public_servant,
      license_date: quote.license_date,
      at_fault_claims_36m: quote.at_fault_claims_36m,
      crm: quote.crm,
      today: Date.utc_today(),
      catalog: catalog
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp table_versions(tables) do
    Map.new(tables, fn {code, data} ->
      {to_string(code), get_in(data, ["version"])}
    end)
  end

  defp step_field_names do
    [
      :plate,
      :is_new_ww,
      :make_id,
      :model_id,
      :version_id,
      :fiscal_power,
      :fuel,
      :first_registration,
      :vehicle_value_centimes,
      :usage,
      :city_id,
      :parking,
      :birth_date,
      :license_date,
      :is_public_servant,
      :current_insurer_id,
      :current_expiry,
      :at_fault_claims_36m,
      :crm,
      :formula,
      :options,
      :franchise_pref,
      :effect_date,
      :first_name,
      :last_name,
      :phone,
      :email,
      :consent_cgu,
      :consent_transmission,
      :consent_marketing
    ]
  end

  @step_fields %{
    vehicle: [
      :is_new_ww,
      :plate,
      :make_id,
      :model_id,
      :version_id,
      :fiscal_power,
      :fuel,
      :first_registration,
      :vehicle_value_centimes,
      :usage,
      :city_id,
      :parking
    ],
    driver: [
      :birth_date,
      :license_date,
      :is_public_servant,
      :current_insurer_id,
      :current_expiry,
      :at_fault_claims_36m,
      :crm
    ],
    coverage: [:formula, :options, :franchise_pref, :effect_date],
    contact: [
      :first_name,
      :last_name,
      :phone,
      :email,
      :city_id,
      :consent_cgu,
      :consent_transmission,
      :consent_marketing
    ]
  }

  defp step_field_names(step) when step in @step_names, do: Map.fetch!(@step_fields, step)

  defp phone_from_quote(quote) do
    case quote.phone_enc do
      nil ->
        nil

      <<1, _::binary>> = enc ->
        case Sahla.Encrypted.Binary.load(enc) do
          {:ok, phone} -> phone
          _ -> nil
        end

      phone ->
        phone
    end
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
