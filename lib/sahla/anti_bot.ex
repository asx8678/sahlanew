defmodule Sahla.AntiBot do
  @moduledoc """
  Swappable anti-bot verification abstraction (§11, §12): Cloudflare Turnstile
  gates funnel step 1 so an automated client cannot reach the OTP request path
  and pump SMS spend. The widget is rendered on the vehicle step and its token
  is verified server-side through `verify/1` before progression is allowed.

  ## Provider resolution

  The adapter is `Application.get_env(:sahla, :antibot_adapter)` when set (tests
  override it directly), otherwise derived from the `:turnstile` provider
  config: a **secret present** selects the live Turnstile adapter, everything
  else falls back to the Fake (the external-provider pattern — a live provider is
  used only when its secret is actually configured).

  ## Feature flag

  Verification is gated by the `:turnstile` settings feature flag
  (`Settings.feature_enabled?(:turnstile)`). When the flag is off, `verify/1`
  short-circuits to `{:ok, :disabled}` — the Fake default makes the funnel pass
  through in dev/test, so the widget renders inert and progression is never
  blocked. The flag must be ON (and a secret configured) for live verification.
  """

  @type token :: String.t()
  @type result :: {:ok, :verified | :disabled} | {:error, term()}

  @callback verify(token) :: result

  @doc """
  Verifies a Turnstile `token`, honoring the settings feature flag.

  When the flag is off the check is skipped (`{:ok, :disabled}`) — no provider
  call, no widget dependency, the funnel passes through. When the flag is on the
  resolved adapter's `verify/1` is invoked; an empty/missing token short-circuits
  to `{:error, :missing_token}` before any HTTP call.
  """
  @spec verify(token | nil) :: result
  def verify(token) do
    if Sahla.Settings.feature_enabled?(:turnstile) do
      verify_token(token)
    else
      {:ok, :disabled}
    end
  end

  defp verify_token(nil), do: verify_token("")
  defp verify_token(""), do: {:error, :missing_token}

  defp verify_token(token) when is_binary(token) do
    adapter().verify(token)
  end

  @doc "The anti-bot adapter module currently in effect."
  @spec adapter() :: module()
  def adapter do
    Application.get_env(:sahla, :antibot_adapter) || derive_adapter()
  end

  @doc "The Turnstile site key rendered into the widget (nil when unconfigured)."
  @spec site_key() :: String.t() | nil
  def site_key do
    Application.get_env(:sahla, :turnstile, [])[:site_key]
  end

  defp derive_adapter do
    turnstile = Application.get_env(:sahla, :turnstile, [])

    if turnstile[:secret] in [nil, ""] do
      Sahla.AntiBot.Fake
    else
      Sahla.AntiBot.Turnstile
    end
  end
end
