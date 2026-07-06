defmodule Sahla.Settings do
  @moduledoc """
  Runtime settings (§10.9): feature flags, contact numbers, working hours,
  disclaimer texts and the display brand name — all changeable by ops without a
  deploy, and the backbone that gates every external integration behind a flag
  (Lessons).

  Reads are served from an in-memory cache (`Sahla.Settings.Cache`); writes
  persist to the `settings` table, refresh the cache and broadcast an
  invalidation so other nodes drop stale entries. Feature flags default OFF, so
  an integration stays dark until it is explicitly enabled.
  """
  alias Sahla.Settings.{Cache, Store}

  @feature_prefix "feature."

  @doc "Reads a setting by key, returning `default` (nil) when unset."
  def get(key, default \\ nil), do: Cache.get(key, default)

  @doc """
  Writes an arbitrary jsonb value for `key`, refreshing the cache. Returns
  `{:ok, value}` or `{:error, changeset}`.
  """
  def put(key, value) do
    case Store.upsert(key, value) do
      {:ok, _setting} ->
        Cache.put(key, value)
        {:ok, value}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Whether a feature flag is on. Returns `false` for an unknown or unset flag —
  a missing flag never reads as enabled.
  """
  def feature_enabled?(flag), do: get(feature_key(flag)) == true

  @doc "Enables or disables a feature flag."
  def put_feature(flag, enabled?) when is_boolean(enabled?), do: put(feature_key(flag), enabled?)

  @doc "The display brand name (never hardcoded in message bodies)."
  def display_name, do: get("display_name", Application.get_env(:sahla, :brand_name, "Sahla"))

  @doc """
  Inserts default keys that are not already set (idempotent): feature flags OFF,
  the display name and placeholder disclaimers. Safe to run repeatedly; never
  clobbers a value ops has already changed.
  """
  def seed_defaults do
    existing = Store.all() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

    for {key, value} <- default_settings(), not MapSet.member?(existing, key) do
      put(key, value)
    end

    :ok
  end

  defp default_settings do
    %{
      "feature.sms" => false,
      "feature.whatsapp" => false,
      "feature.payments" => false,
      "feature.turnstile" => false,
      "display_name" => Application.get_env(:sahla, :brand_name, "Sahla"),
      "disclaimer_fr" => "Devis indicatif et sans valeur contractuelle.",
      "disclaimer_ar" => "عرض تقديري وليس له قيمة تعاقدية."
    }
  end

  defp feature_key(flag), do: @feature_prefix <> to_string(flag)
end
