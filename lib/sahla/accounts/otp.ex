defmodule Sahla.Accounts.OTP do
  @moduledoc """
  Phone-bound one-time-passcode verification for the funnel's lead gate
  (§5.2, §7.3, §12).

  A prior build let users bypass the gate by editing the phone after verifying;
  here verification is bound to the exact phone (`Quote.changeset` clears
  `phone_verified_at` on any phone change, and `verify_otp/3` only marks a quote
  whose stored phone matches the verified one).

  Hardening: codes are stored only as an Argon2 hash with a 5-minute TTL; three
  failed attempts lock the code; sends are rate-limited per phone **and** per IP;
  each request supersedes the phone's earlier unused codes so only one is live.
  """
  use Sahla.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sahla.Accounts.OTP
  alias Sahla.Hashed.HMAC
  alias Sahla.Notifications.{RateLimit, SMS}
  alias Sahla.Quoting.Quote
  alias Sahla.Repo

  @max_attempts 3
  @ttl_seconds 300

  schema "otp_codes" do
    field :phone_hash, HMAC, redact: true
    field :code_hash, :string, redact: true
    field :attempts, :integer, default: 0
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    timestamps()
  end

  def max_attempts, do: @max_attempts
  def ttl_seconds, do: @ttl_seconds

  @doc """
  Issues an OTP for `phone`: generates a 6-digit code, stores its hash with a
  5-minute TTL, supersedes the phone's earlier unused codes and sends the code
  over the SMS behaviour. Rate-limited per phone and per IP (`opts[:ip]`).

  Returns `{:ok, otp}`, `{:error, {:rate_limited, retry_after_s}}`, or the SMS
  facade's error (`:disabled`, `:recipient_not_allowed`, …).
  """
  def request_otp(phone, opts \\ []) when is_binary(phone) do
    ip = Keyword.get(opts, :ip) || "unknown"

    with {:allow} <- RateLimit.otp_per_phone(bucket_key(phone)),
         {:allow} <- RateLimit.otp_per_ip(ip),
         code = generate_code(),
         {:ok, otp} <- store_code(phone, code),
         {:ok, _receipt} <- SMS.send(phone, :otp_code, %{code: code}) do
      {:ok, otp}
    else
      {:deny, retry_after} -> {:error, {:rate_limited, retry_after}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Verifies `code` against the live OTP for `phone` and, on success, marks
  `quote`'s `phone_verified_at` — but only when the quote's stored phone matches
  the verified one (`:phone_mismatch` otherwise).

  Errors: `:invalid` (wrong/no code), `:expired`, `:locked` (3 attempts used),
  `:already_used` (re-verifying a consumed code is a no-op), `:phone_mismatch`.
  Each wrong attempt increments the counter; the third locks the code.
  """
  def verify_otp(%Quote{} = quote, phone, code)
      when is_binary(phone) and is_binary(code) do
    now = now()

    case latest_for(phone) do
      nil ->
        {:error, :invalid}

      %OTP{used_at: used} when not is_nil(used) ->
        {:error, :already_used}

      %OTP{} = otp ->
        check(otp, quote, phone, code, now)
    end
  end

  defp check(otp, quote, phone, code, now) do
    cond do
      DateTime.compare(otp.expires_at, now) != :gt -> {:error, :expired}
      otp.attempts >= @max_attempts -> {:error, :locked}
      not Argon2.verify_pass(code, otp.code_hash) -> register_failure(otp)
      not phone_bound?(quote, phone) -> {:error, :phone_mismatch}
      true -> succeed(otp, quote, now)
    end
  end

  defp register_failure(otp) do
    {:ok, updated} = otp |> change(attempts: otp.attempts + 1) |> Repo.update()
    if updated.attempts >= @max_attempts, do: {:error, :locked}, else: {:error, :invalid}
  end

  defp succeed(otp, quote, now) do
    Repo.transaction(fn ->
      otp |> change(used_at: now) |> Repo.update!()
      quote |> Quote.mark_phone_verified(now) |> Repo.update!()
    end)
  end

  # The quote's stored phone must hash to the same keyed HMAC as the verified one.
  defp phone_bound?(%Quote{phone_hash: stored}, phone) do
    is_binary(stored) and
      (Plug.Crypto.secure_compare(stored, digest(phone)) or
         Plug.Crypto.secure_compare(stored, phone))
  end

  defp store_code(phone, code) do
    now = now()
    phone_hash = hash_phone(phone)

    Repo.transaction(fn ->
      supersede_unused(phone_hash, now)

      %OTP{}
      |> change(%{
        phone_hash: phone_hash,
        code_hash: Argon2.hash_pwd_salt(code),
        attempts: 0,
        expires_at: DateTime.add(now, @ttl_seconds, :second),
        used_at: nil
      })
      |> Repo.insert!()
    end)
  end

  defp supersede_unused(phone_hash, now) do
    OTP
    |> where([o], o.phone_hash == ^phone_hash and is_nil(o.used_at))
    |> Repo.update_all(set: [used_at: now, updated_at: now])
  end

  defp latest_for(phone) do
    phone_hash = hash_phone(phone)

    OTP
    |> where([o], o.phone_hash == ^phone_hash)
    |> order_by([o], desc: o.inserted_at, desc: o.id)
    |> limit(1)
    |> Repo.one()
  end

  defp hash_phone(phone) do
    {:ok, hash} = HMAC.dump(phone)
    hash
  end

  defp generate_code do
    number = rem(:binary.decode_unsigned(:crypto.strong_rand_bytes(4)), 900_000) + 100_000
    Integer.to_string(number)
  end

  defp digest(phone) do
    {:ok, hash} = HMAC.dump(phone)
    hash
  end

  defp bucket_key(phone), do: phone |> digest() |> Base.encode16()

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
