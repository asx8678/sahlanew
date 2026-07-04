defmodule Sahla.AccountsTest do
  # async: false — authenticate/1 uses the shared Hammer rate-limit buckets.
  use Sahla.DataCase, async: false

  alias Sahla.Accounts
  alias Sahla.Accounts.Admin

  @password "correct horse battery"

  defp admin_fixture(attrs \\ %{}) do
    {:ok, admin} =
      Accounts.register_admin(
        Enum.into(attrs, %{
          email: "admin-#{System.unique_integer([:positive])}@sahla.ma",
          password: @password,
          role: :ops
        })
      )

    admin
  end

  defp uid_ip, do: "203.0.113.#{System.unique_integer([:positive])}"

  describe "register_admin/1" do
    test "hashes the password with Argon2 and never stores plaintext" do
      admin = admin_fixture()

      assert admin.password_hash
      assert String.starts_with?(admin.password_hash, "$argon2")
      refute admin.password_hash == @password
      # the virtual field is cleared after hashing
      assert admin.password == nil
    end

    test "rejects an invalid role via the Ecto.Enum" do
      assert {:error, changeset} =
               Accounts.register_admin(%{email: "x@sahla.ma", password: @password, role: :hacker})

      assert %{role: ["is invalid"]} = errors_on(changeset)
    end

    test "enforces email uniqueness case-insensitively (citext)" do
      admin_fixture(email: "dup@sahla.ma")

      assert {:error, changeset} =
               Accounts.register_admin(%{email: "DUP@sahla.ma", password: @password, role: :ops})

      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "get_admin_by_email_and_password/2" do
    test "returns the admin on the correct password" do
      admin = admin_fixture()
      assert %Admin{id: id} = Accounts.get_admin_by_email_and_password(admin.email, @password)
      assert id == admin.id
    end

    test "returns nil on a wrong password" do
      admin = admin_fixture()
      refute Accounts.get_admin_by_email_and_password(admin.email, "wrong password!")
    end

    test "an unknown email still runs a hash (constant-time, no leak)" do
      # Admin.valid_password?(nil, _) must invoke Argon2.no_user_verify and return false.
      refute Accounts.get_admin_by_email_and_password("nobody@sahla.ma", "whatever password")
    end
  end

  describe "authenticate_admin/3 with throttling" do
    test "succeeds for an active admin under the limit" do
      admin = admin_fixture()
      assert {:ok, %Admin{}} = Accounts.authenticate_admin(admin.email, @password, uid_ip())
    end

    test "wrong password returns :invalid_credentials" do
      admin = admin_fixture()

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_admin(admin.email, "nope nope nope", uid_ip())
    end

    test "blocks after too many attempts per email+IP" do
      admin = admin_fixture()
      ip = uid_ip()
      Application.put_env(:sahla, :rate_limits, admin_logins_per_15min: 3)
      on_exit(fn -> Application.delete_env(:sahla, :rate_limits) end)

      for _ <- 1..3, do: Accounts.authenticate_admin(admin.email, "bad", ip)

      assert {:error, {:rate_limited, retry_after}} =
               Accounts.authenticate_admin(admin.email, @password, ip)

      assert retry_after > 0
    end
  end

  describe "sessions and role changes" do
    test "get_admin_for_session/2 matches only the current version of an active admin" do
      admin = admin_fixture()
      assert Accounts.get_admin_for_session(admin.id, admin.session_version)
      refute Accounts.get_admin_for_session(admin.id, admin.session_version + 1)
    end

    test "changing a role bumps session_version, killing old-version sessions" do
      admin = admin_fixture(role: :agent)
      old_version = admin.session_version

      # a session issued now would carry old_version
      assert Accounts.get_admin_for_session(admin.id, old_version)

      {:ok, updated} = Accounts.change_admin_role(admin, :ops)
      assert updated.role == :ops
      assert updated.session_version == old_version + 1

      # the old-version session is now dead; the new one lives
      refute Accounts.get_admin_for_session(admin.id, old_version)
      assert Accounts.get_admin_for_session(admin.id, updated.session_version)
    end

    test "an inactive admin has no valid session" do
      admin = admin_fixture()
      {:ok, admin} = admin |> Ecto.Changeset.change(active: false) |> Repo.update()
      refute Accounts.get_admin_for_session(admin.id, admin.session_version)
    end
  end
end
