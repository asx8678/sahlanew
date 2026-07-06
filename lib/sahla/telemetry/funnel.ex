defmodule Sahla.Telemetry.Funnel do
  @moduledoc """
  Emission-only funnel telemetry (§11). Emits `:telemetry` events at the key
  funnel transitions so the launch/analytics epic can attach handlers without
  coupling to `DevisLive` or `Quoting` internals. This module owns emission
  only — no handlers are attached here.

  ## Events

  All events share the `[:sahla, :funnel, :*]` prefix:

    * `[:sahla, :funnel, :step_completed]` — a funnel step advanced.
      metadata: `%{token: String.t(), step: atom(), step_number: pos_integer(),
                  locale: String.t()}`.
    * `[:sahla, :funnel, :otp_verified]` — a contact phone was verified.
      metadata: `%{token: String.t(), locale: String.t()}`.
    * `[:sahla, :funnel, :lead_created]` — a lead was created from a quote.
      metadata: `%{lead_id: String.t(), quote_id: String.t(),
                  source: String.t()}`.

  Metadata is **non-PII only** — tokens, step/locale and IDs, never phone or
  name. Measurements are `%{count: 1}` (a counter-style event).
  """

  @prefix [:sahla, :funnel]

  @doc "Emits `[:sahla, :funnel, :step_completed]` on each step advance."
  @spec step_completed(String.t(), atom(), pos_integer(), String.t()) :: :ok
  def step_completed(token, step, step_number, locale)
      when is_binary(token) and is_atom(step) and is_integer(step_number) and
             step_number > 0 and is_binary(locale) do
    :telemetry.execute(
      @prefix ++ [:step_completed],
      %{count: 1},
      %{token: token, step: step, step_number: step_number, locale: locale}
    )
  end

  @doc "Emits `[:sahla, :funnel, :otp_verified]` when the contact phone is verified."
  @spec otp_verified(String.t(), String.t()) :: :ok
  def otp_verified(token, locale) when is_binary(token) and is_binary(locale) do
    :telemetry.execute(
      @prefix ++ [:otp_verified],
      %{count: 1},
      %{token: token, locale: locale}
    )
  end

  @doc "Emits `[:sahla, :funnel, :lead_created]` when a lead is created from a quote."
  @spec lead_created(String.t(), String.t(), String.t()) :: :ok
  def lead_created(lead_id, quote_id, source)
      when is_binary(lead_id) and is_binary(quote_id) and is_binary(source) do
    :telemetry.execute(
      @prefix ++ [:lead_created],
      %{count: 1},
      %{lead_id: lead_id, quote_id: quote_id, source: source}
    )
  end
end
