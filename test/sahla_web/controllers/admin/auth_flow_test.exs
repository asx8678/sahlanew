defmodule SahlaWeb.Admin.AuthFlowTest do
  # async: false — login goes through the shared Hammer rate-limit buckets.
  use SahlaWeb.ConnCase, async: false

  alias Sahla.Accounts

  @password "correct horse battery"

  defp admin_fixture do
    {:ok, admin} =
      Accounts.register_admin(%{
        email: "flow-#{System.unique_integer([:positive])}@sahla.ma",
        password: @password,
        role: :ops
      })

    admin
  end

  # Enrolled admin + its secret. Confirms with a previous-period code so a
  # current-period login code is not rejected as a replay.
  defp enrolled_fixture do
    {:ok, admin, secret} = Accounts.setup_totp(admin_fixture())
    {:ok, admin} = Accounts.activate_totp(admin, code(secret, -30))
    {admin, secret}
  end

  defp code(secret, offset),
    do: NimbleTOTP.verification_code(secret, time: System.os_time(:second) + offset)

  # Pulls the hidden CSRF token out of a rendered form (browser-faithful posting).
  defp form_csrf(html) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, html)
    token
  end

  defp password_login(conn, admin) do
    conn = get(conn, ~p"/admin/login")
    token = form_csrf(html_response(conn, 200))

    post(conn, ~p"/admin/login", %{
      "_csrf_token" => token,
      "admin" => %{"email" => admin.email, "password" => @password}
    })
  end

  describe "protected routes require a full session" do
    test "an anonymous visitor is redirected to login", %{conn: conn} do
      conn = get(conn, ~p"/admin")
      assert redirected_to(conn) == ~p"/admin/login"
    end

    test "a password-only (pre-2FA) session still cannot reach /admin", %{conn: conn} do
      admin = admin_fixture()
      conn = password_login(conn, admin)
      # half-authenticated: routed into 2FA, not granted a full session
      assert redirected_to(conn) == ~p"/admin/totp/setup"

      conn = get(conn, ~p"/admin")
      assert redirected_to(conn) == ~p"/admin/login"
    end
  end

  describe "the 2FA stage cannot be entered cold" do
    test "setup redirects to login without a pending admin", %{conn: conn} do
      assert redirected_to(get(conn, ~p"/admin/totp/setup")) == ~p"/admin/login"
    end

    test "verify redirects to login without a pending admin", %{conn: conn} do
      assert redirected_to(get(conn, ~p"/admin/totp")) == ~p"/admin/login"
    end
  end

  describe "first-time enrollment flow" do
    test "an unenrolled admin is forced through setup, then reaches /admin", %{conn: conn} do
      admin = admin_fixture()

      conn = password_login(conn, admin)
      assert redirected_to(conn) == ~p"/admin/totp/setup"

      conn = get(conn, ~p"/admin/totp/setup")
      body = html_response(conn, 200)
      assert body =~ "<svg"

      secret = Accounts.get_admin!(admin.id).totp_secret_enc

      conn =
        post(conn, ~p"/admin/totp/setup", %{
          "_csrf_token" => form_csrf(body),
          "totp" => %{"code" => code(secret, 0)}
        })

      assert redirected_to(conn) == ~p"/admin"
      # the full session now reaches the protected landing
      assert html_response(get(conn, ~p"/admin"), 200) =~ "signed in"
    end
  end

  describe "returning login flow" do
    test "an enrolled admin verifies a code and reaches /admin", %{conn: conn} do
      {admin, secret} = enrolled_fixture()

      conn = password_login(conn, admin)
      assert redirected_to(conn) == ~p"/admin/totp"

      conn = get(conn, ~p"/admin/totp")

      conn =
        post(conn, ~p"/admin/totp", %{
          "_csrf_token" => form_csrf(html_response(conn, 200)),
          "totp" => %{"code" => code(secret, 0)}
        })

      assert redirected_to(conn) == ~p"/admin"
      assert html_response(get(conn, ~p"/admin"), 200) =~ "signed in"
    end

    test "a wrong code re-renders the verification form", %{conn: conn} do
      {admin, _secret} = enrolled_fixture()

      conn = password_login(conn, admin)
      conn = get(conn, ~p"/admin/totp")

      conn =
        post(conn, ~p"/admin/totp", %{
          "_csrf_token" => form_csrf(html_response(conn, 200)),
          "totp" => %{"code" => "000000"}
        })

      assert html_response(conn, 200) =~ "Incorrect code"
    end
  end
end
