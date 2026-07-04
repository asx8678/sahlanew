defmodule Sahla.Accounts.TotpTest do
  # async: false — asserts the Settings-sourced issuer via the shared cache.
  use Sahla.DataCase, async: false

  alias Sahla.Accounts
  alias Sahla.Settings

  @period 30

  defp admin_fixture do
    {:ok, admin} =
      Accounts.register_admin(%{
        email: "totp-#{System.unique_integer([:positive])}@sahla.ma",
        password: "correct horse battery",
        role: :ops
      })

    admin
  end

  # An enrolled admin plus its raw secret (needed to generate valid codes).
  defp enrolled_fixture do
    {:ok, admin, secret} = Accounts.setup_totp(admin_fixture())
    code = NimbleTOTP.verification_code(secret, time: System.os_time(:second))
    {:ok, admin} = Accounts.activate_totp(admin, code)
    {admin, secret}
  end

  defp code_at(secret, offset_seconds) do
    NimbleTOTP.verification_code(secret, time: System.os_time(:second) + offset_seconds)
  end

  describe "setup_totp/1 and enrollment gating" do
    test "stores an encrypted secret but leaves the admin unenrolled" do
      admin = admin_fixture()
      refute Accounts.totp_enrolled?(admin)

      {:ok, admin, secret} = Accounts.setup_totp(admin)

      assert is_binary(secret)
      assert byte_size(secret) == 20
      # persisted (cloak round-trips to the same raw secret) but not yet confirmed
      assert Accounts.get_admin!(admin.id).totp_secret_enc == secret
      refute Accounts.totp_enrolled?(admin)
    end

    test "activate_totp confirms enrollment with a correct code" do
      {:ok, admin, secret} = Accounts.setup_totp(admin_fixture())

      assert {:ok, admin} = Accounts.activate_totp(admin, code_at(secret, 0))
      assert Accounts.totp_enrolled?(admin)
      assert admin.totp_confirmed_at
    end

    test "activate_totp rejects a wrong code and stays unenrolled" do
      {:ok, admin, _secret} = Accounts.setup_totp(admin_fixture())

      assert {:error, :invalid_code} = Accounts.activate_totp(admin, "000000")
      refute Accounts.totp_enrolled?(Accounts.get_admin!(admin.id))
    end
  end

  describe "totp_provisioning_uri/2 and totp_qr_svg/1" do
    test "builds an otpauth:// URI whose issuer comes from settings, not a literal" do
      {:ok, admin, secret} = Accounts.setup_totp(admin_fixture())
      name = Settings.display_name()

      uri = Accounts.totp_provisioning_uri(admin, secret)

      assert String.starts_with?(uri, "otpauth://totp/")
      assert uri =~ "issuer=#{name}"
      assert uri =~ "#{name}:#{admin.email}"
    end

    test "renders a scannable inline SVG with no XML prolog" do
      {:ok, admin, secret} = Accounts.setup_totp(admin_fixture())
      svg = Accounts.totp_qr_svg(Accounts.totp_provisioning_uri(admin, secret))

      assert svg =~ "<svg"
      refute svg =~ "<?xml"
    end
  end

  describe "valid_totp?/2" do
    test "accepts the current code and rejects an incorrect one" do
      {admin, secret} = enrolled_fixture()
      # replay guard was seeded by activation; a fresh (next-period) code verifies
      assert Accounts.valid_totp?(%{admin | totp_last_used_at: nil}, code_at(secret, 0))
      refute Accounts.valid_totp?(admin, "000000")
    end

    test "accepts a code one step of drift back but rejects two steps back" do
      {:ok, admin, secret} = Accounts.setup_totp(admin_fixture())

      # last_used_at is nil, so only the drift window (not replay) is exercised
      assert Accounts.valid_totp?(admin, code_at(secret, -@period))
      refute Accounts.valid_totp?(admin, code_at(secret, -3 * @period))
    end
  end

  describe "verify_totp/2 replay guard" do
    test "accepts a code once then rejects the same code as a replay" do
      {:ok, admin, secret} = Accounts.setup_totp(admin_fixture())
      {:ok, admin} = Accounts.activate_totp(admin, code_at(secret, -@period))

      # A fresh current code verifies and advances the guard...
      code = code_at(secret, 0)
      assert {:ok, admin} = Accounts.verify_totp(admin, code)

      # ...and replaying it is now rejected.
      refute Accounts.valid_totp?(admin, code)
      assert :error = Accounts.verify_totp(admin, code)
    end
  end
end
