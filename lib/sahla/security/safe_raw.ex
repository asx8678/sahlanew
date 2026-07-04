defmodule Sahla.Security.SafeRaw do
  @moduledoc """
  Non-PII projection for anything headed into a plain jsonb column (§8, §12).

  Lessons: never persist raw external payloads or consent params verbatim — a
  provider callback, a browser param map or a consent snapshot can carry a phone,
  an email, a CIN, a name or an OTP code. `safe_raw/1` recursively strips those
  keys at any depth; `safe_raw/2` is an allowlist mode that keeps only permitted
  top-level keys (and still scrubs PII nested inside them).

  Pure — no DB, no side effects. Reused by:

    * `Sahla.Notifications.DeliveryLog` — the `payload` column projection, so a
      raw provider/OTP payload is never stored.
    * the consents capture (lrs.3) — so a consent snapshot keeps only non-PII
      evidence (utm, timestamps, policy version), never the identity.
  """

  # Keys (case-insensitive, exact after normalization) considered PII/secret and
  # dropped at every depth. Exact-match by design: it drops `code` (an OTP) but
  # keeps `status_code`/`country_code` (a provider status is not PII).
  @denylist MapSet.new(~w(
                phone phone_number mobile msisdn telephone tel
                email e_mail mail
                cin national_id id_card
                name first_name firstname last_name lastname full_name fullname
                otp otp_code code pin verification_code
                token access_token refresh_token session_token
                password passwd secret api_key apikey
                recipient to
              ))

  @doc "The set of denylisted (dropped) keys, normalized."
  def denylist, do: @denylist

  @doc """
  Recursively drops PII/secret keys from `value` (maps, lists and scalars),
  returning a jsonb-safe structure with string keys.
  """
  def safe_raw(value), do: sanitize(value)

  @doc """
  Allowlist projection: keeps only `allowed` top-level keys of `map`, dropping
  everything else, and recursively scrubs PII from the kept values.
  """
  def safe_raw(map, allowed) when is_map(map) and is_list(allowed) do
    allow = MapSet.new(Enum.map(allowed, &to_string/1))

    map
    |> Enum.filter(fn {key, _value} -> MapSet.member?(allow, to_string(key)) end)
    |> Map.new(fn {key, value} -> {to_string(key), sanitize(value)} end)
  end

  defp sanitize(map) when is_map(map) and not is_struct(map) do
    map
    |> Enum.reject(fn {key, _value} -> denylisted?(key) end)
    |> Map.new(fn {key, value} -> {to_string(key), sanitize(value)} end)
  end

  defp sanitize(list) when is_list(list), do: Enum.map(list, &sanitize/1)
  defp sanitize(scalar), do: scalar

  defp denylisted?(key), do: MapSet.member?(@denylist, key |> to_string() |> String.downcase())
end
