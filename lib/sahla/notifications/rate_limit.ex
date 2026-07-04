defmodule Sahla.Notifications.RateLimit do
  @moduledoc """
  Velocity caps over Hammer (ETS backend) guarding against SMS-pumping fraud and
  OTP cost blowout (§15, §12). Each boundary function returns `{:allow}` or
  `{:deny, retry_after}` where `retry_after` is **seconds** until the bucket
  frees up.

  Buckets (limit per window), each overridable via the `:rate_limits` config
  with a safe hardcoded default:

    * `otp_per_phone/1` — OTP sends per phone-hash per day
    * `otp_per_ip/1` — OTP sends per IP per day
    * `funnel_start_per_ip/1` — funnel starts per IP per hour
    * `admin_login/2` — admin login attempts per IP+email per 15 minutes

  The OTP path caps per phone AND per IP (Lessons). Callers live in other epics
  (OTP send, funnel start, admin login); they invoke these functions only.
  """
  use Hammer, backend: :ets

  @type decision :: {:allow} | {:deny, non_neg_integer()}

  @day :timer.hours(24)
  @hour :timer.hours(1)
  @quarter_hour :timer.minutes(15)

  @defaults [
    otp_per_phone_per_day: 5,
    otp_per_ip_per_day: 20,
    funnel_starts_per_ip_per_hour: 30,
    admin_logins_per_15min: 5
  ]

  @spec otp_per_phone(String.t()) :: decision
  def otp_per_phone(phone_hash) do
    check("otp:phone:#{phone_hash}", @day, :otp_per_phone_per_day)
  end

  @spec otp_per_ip(String.t()) :: decision
  def otp_per_ip(ip) do
    check("otp:ip:#{ip}", @day, :otp_per_ip_per_day)
  end

  @spec funnel_start_per_ip(String.t()) :: decision
  def funnel_start_per_ip(ip) do
    check("funnel:ip:#{ip}", @hour, :funnel_starts_per_ip_per_hour)
  end

  @spec admin_login(String.t(), String.t()) :: decision
  def admin_login(ip, email) do
    check("admin-login:#{ip}:#{email}", @quarter_hour, :admin_logins_per_15min)
  end

  defp check(key, scale, limit_key) do
    case hit(key, scale, limit(limit_key)) do
      {:allow, _count} -> {:allow}
      {:deny, retry_after_ms} -> {:deny, ceil(retry_after_ms / 1000)}
    end
  end

  defp limit(key) do
    :sahla
    |> Application.get_env(:rate_limits, [])
    |> Keyword.get(key, Keyword.fetch!(@defaults, key))
  end
end
