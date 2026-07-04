defmodule Sahla.Accounts.OTPTest do
  # async: false — exercises the globally-supervised Fake SMS agent and the
  # ETS-backed rate limiter.
  use Sahla.DataCase, async: false

  import Ecto.Query

  alias Sahla.Accounts.OTP
  alias Sahla.Notifications.SMSProvider.Fake
  alias Sahla.Quoting

  setup do
    Fake.clear()
    :ok
  end

  defp phone do
    n = System.unique_integer([:positive]) |> rem(100_000_000)
    "+2126" <> String.pad_leading(Integer.to_string(n), 8, "0")
  end

  defp last_code do
    Fake.sent() |> List.last() |> Map.fetch!(:vars) |> Map.fetch!(:code)
  end

  # A resumable quote whose stored phone is `phone`.
  defp quote_with_phone(phone) do
    {:ok, quote} = Quoting.create_quote()

    {:ok, _} =
      Quoting.upsert_step(quote, :contact, %{
        first_name: "Amina",
        last_name: "El Fassi",
        phone: phone,
        consent_cgu: true,
        consent_transmission: true
      })

    Quoting.get_quote_by_token(quote.token)
  end

  describe "request_otp/2" do
    test "sends a 6-digit code and stores only its hash with a 5-minute TTL" do
      p = phone()
      assert {:ok, otp} = OTP.request_otp(p, ip: "196.200.1.1")

      # code delivered over SMS
      assert %{to: ^p, template: :otp_code} = List.last(Fake.sent())
      assert last_code() =~ ~r/^\d{6}$/

      # stored as an Argon2 hash, never the plaintext code
      assert String.starts_with?(otp.code_hash, "$argon2")
      refute otp.code_hash == last_code()

      # 5-minute expiry
      assert_in_delta DateTime.diff(otp.expires_at, DateTime.utc_now()), OTP.ttl_seconds(), 5
    end

    test "the phone is stored only as a keyed HMAC, never raw" do
      p = phone()
      {:ok, otp} = OTP.request_otp(p, ip: "196.200.1.1")

      %{rows: [[raw]]} =
        Repo.query!("SELECT phone_hash FROM otp_codes WHERE id = $1", [Ecto.UUID.dump!(otp.id)])

      refute String.contains?(to_string(raw), String.trim_leading(p, "+"))
    end

    test "a new request supersedes the phone's earlier unused code" do
      p = phone()
      {:ok, first} = OTP.request_otp(p, ip: "196.200.1.1")
      {:ok, _second} = OTP.request_otp(p, ip: "196.200.1.1")

      assert Repo.get!(OTP, first.id).used_at, "the earlier code should be marked used"
    end
  end

  describe "verify_otp/3 — success and phone binding" do
    test "a correct code marks the quote's phone_verified_at, bound to that phone" do
      p = phone()
      quote = quote_with_phone(p)
      {:ok, _otp} = OTP.request_otp(p, ip: "196.200.1.1")

      assert {:ok, verified} = OTP.verify_otp(quote, p, last_code())
      assert verified.phone_verified_at

      # persisted
      assert Quoting.get_quote_by_token(quote.token).phone_verified_at
    end

    test "success is refused when the quote's stored phone differs from the verified one" do
      otp_phone = phone()
      quote = quote_with_phone(phone())
      {:ok, _} = OTP.request_otp(otp_phone, ip: "196.200.1.1")

      assert {:error, :phone_mismatch} = OTP.verify_otp(quote, otp_phone, last_code())
      refute Quoting.get_quote_by_token(quote.token).phone_verified_at
    end
  end

  describe "verify_otp/3 — attempts, TTL and reuse" do
    test "three wrong attempts lock the code, even against the correct one afterwards" do
      p = phone()
      quote = quote_with_phone(p)
      {:ok, _} = OTP.request_otp(p, ip: "196.200.1.1")
      good = last_code()

      assert {:error, :invalid} = OTP.verify_otp(quote, p, "000000")
      assert {:error, :invalid} = OTP.verify_otp(quote, p, "000000")
      assert {:error, :locked} = OTP.verify_otp(quote, p, "000000")
      # correct code no longer helps once locked
      assert {:error, :locked} = OTP.verify_otp(quote, p, good)
    end

    test "an expired code is rejected" do
      p = phone()
      quote = quote_with_phone(p)
      {:ok, _} = OTP.request_otp(p, ip: "196.200.1.1")
      good = last_code()

      past = DateTime.add(DateTime.utc_now(), -1, :second) |> DateTime.truncate(:second)
      Repo.update_all(from(o in OTP, where: o.phone_hash == ^p), set: [expires_at: past])

      assert {:error, :expired} = OTP.verify_otp(quote, p, good)
    end

    test "re-verifying an already-used code is a no-op" do
      p = phone()
      quote = quote_with_phone(p)
      {:ok, _} = OTP.request_otp(p, ip: "196.200.1.1")
      good = last_code()

      assert {:ok, _} = OTP.verify_otp(quote, p, good)
      assert {:error, :already_used} = OTP.verify_otp(quote, p, good)
    end

    test "an unknown phone has no code to verify" do
      assert {:error, :invalid} = OTP.verify_otp(quote_with_phone(phone()), phone(), "123456")
    end
  end

  describe "rate limiting" do
    test "per-phone sends are capped" do
      Application.put_env(:sahla, :rate_limits, otp_per_phone_per_day: 2, otp_per_ip_per_day: 100)
      on_exit(fn -> Application.delete_env(:sahla, :rate_limits) end)

      p = phone()
      assert {:ok, _} = OTP.request_otp(p, ip: "10.0.0.1")
      assert {:ok, _} = OTP.request_otp(p, ip: "10.0.0.1")
      assert {:error, {:rate_limited, retry_after}} = OTP.request_otp(p, ip: "10.0.0.1")
      assert is_integer(retry_after) and retry_after > 0
    end

    test "per-IP sends are capped across different phones" do
      Application.put_env(:sahla, :rate_limits, otp_per_phone_per_day: 100, otp_per_ip_per_day: 2)
      on_exit(fn -> Application.delete_env(:sahla, :rate_limits) end)

      ip = "10.0.0.2"
      assert {:ok, _} = OTP.request_otp(phone(), ip: ip)
      assert {:ok, _} = OTP.request_otp(phone(), ip: ip)
      assert {:error, {:rate_limited, _}} = OTP.request_otp(phone(), ip: ip)
    end
  end
end
