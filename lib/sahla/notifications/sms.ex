defmodule Sahla.Notifications.SMS do
  @moduledoc """
  Swappable SMS provider abstraction (§7.3, §11). Every SMS — OTP codes, lead
  notifications — goes through `send/3`, which resolves the configured adapter
  and honors the kill-switch, so callers never couple to a gateway and tests
  run deterministically against `Sahla.Notifications.SMSProvider.Fake`.

  ## Provider resolution

  The adapter is `Application.get_env(:sahla, :sms_adapter)` when set (tests
  override it directly), otherwise derived from the `:sms` provider config:
  `"infobip"` **with an API key present** selects the live adapter, everything
  else falls back to the Fake (the external-provider pattern — a live provider
  is used only when its secret is actually configured).

  ## Kill-switch

  When `:sms_enabled` is false, `send/3` short-circuits to `{:error, :disabled}`
  without touching the provider, so a budget alarm or incident can stop all
  sends at runtime.
  """

  @type to :: String.t()
  @type template :: atom() | String.t()
  @type vars :: map()
  @type ok :: {:ok, %{provider_id: String.t(), cost_centimes: non_neg_integer()}}
  @type result :: ok | {:error, term()}

  @callback send(to, template, vars) :: result

  @doc """
  Sends an SMS through the configured provider.

  Short-circuits to `{:error, :disabled}` if the kill-switch is off and to
  `{:error, :recipient_not_allowed}` for a non-Moroccan number (the +212
  allowlist, enforced before any provider call); otherwise delegates to the
  resolved adapter's `send/3`.
  """
  @spec send(to, template, vars) :: result
  def send(to, template, vars) when is_binary(to) and is_map(vars) do
    cond do
      not enabled?() -> {:error, :disabled}
      not ma_allowed?(to) -> {:error, :recipient_not_allowed}
      true -> adapter().send(to, template, vars)
    end
  end

  @doc """
  Whether `to` is an allowed Moroccan (+212) recipient — the anti-pump allowlist
  (§15). Accepts `+212XXXXXXXXX`, `212XXXXXXXXX` and local `0XXXXXXXXX` forms
  (ignoring spaces, dashes and parentheses); every other number is rejected.
  """
  @spec ma_allowed?(String.t()) :: boolean()
  def ma_allowed?(to) when is_binary(to) do
    normalized = String.replace(to, ~r/[\s\-().]/, "")
    Regex.match?(~r/\A(\+212|212|0)\d{9}\z/, normalized)
  end

  def ma_allowed?(_), do: false

  @doc "The SMS adapter module currently in effect."
  @spec adapter() :: module()
  def adapter do
    Application.get_env(:sahla, :sms_adapter) || derive_adapter()
  end

  @doc "Whether SMS sending is currently enabled (the kill-switch)."
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:sahla, :sms_enabled, true)

  defp derive_adapter do
    sms = Application.get_env(:sahla, :sms, [])

    if sms[:provider] == "infobip" and sms[:api_key] not in [nil, ""] do
      Sahla.Notifications.SMSProvider.Infobip
    else
      Sahla.Notifications.SMSProvider.Fake
    end
  end
end
