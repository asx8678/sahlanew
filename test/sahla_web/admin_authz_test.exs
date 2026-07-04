defmodule SahlaWeb.AdminAuthzTest do
  # async: false — the IP-allowlist path uses the shared settings cache.
  use Sahla.DataCase, async: false

  import Plug.Test
  import Plug.Conn

  alias Phoenix.LiveView.Socket
  alias Sahla.Accounts.Admin
  alias Sahla.Settings
  alias Sahla.Settings.Cache
  alias SahlaWeb.AdminAuthz

  setup do
    Cache.clear()
    :ok
  end

  defp admin(role), do: %Admin{id: Ecto.UUID.generate(), role: role}

  defp run(conn, capability), do: AdminAuthz.call(conn, AdminAuthz.init(capability: capability))

  defp conn_for(role), do: conn(:get, "/admin") |> assign(:current_admin, admin(role))

  describe "plug" do
    test "permits an authorized role" do
      refute run(conn_for(:ops), :leads).halted
    end

    test "denies an unauthorized role with 403" do
      result = run(conn_for(:ops), :cms)
      assert result.halted
      assert result.status == 403
    end

    test "denies an unauthenticated request with 403" do
      conn = conn(:get, "/admin") |> assign(:current_admin, nil)
      result = run(conn, :leads)
      assert result.halted
      assert result.status == 403
    end
  end

  describe "on_mount" do
    defp socket_for(role), do: %Socket{assigns: %{current_admin: admin(role)}}

    test "continues for an authorized role" do
      assert {:cont, _socket} = AdminAuthz.on_mount(:cms, %{}, %{}, socket_for(:editor))
    end

    test "halts with a redirect for an unauthorized role" do
      assert {:halt, socket} = AdminAuthz.on_mount(:leads, %{}, %{}, socket_for(:editor))
      assert socket.redirected
    end
  end

  describe "IP allowlist (Settings-gated)" do
    setup do
      {:ok, _} = Settings.put_feature("admin_ip_allowlist", true)
      {:ok, _} = Settings.put("admin_ip_allowlist", ["41.0.0.1"])
      :ok
    end

    test "blocks a non-listed source IP when enabled" do
      conn = conn_for(:superadmin) |> Map.put(:remote_ip, {10, 0, 0, 9})
      result = run(conn, :leads)
      assert result.halted
      assert result.status == 403
    end

    test "allows a listed source IP when enabled" do
      conn = conn_for(:ops) |> Map.put(:remote_ip, {41, 0, 0, 1})
      refute run(conn, :leads).halted
    end

    test "is ignored when the flag is disabled" do
      {:ok, _} = Settings.put_feature("admin_ip_allowlist", false)
      conn = conn_for(:ops) |> Map.put(:remote_ip, {10, 0, 0, 9})
      refute run(conn, :leads).halted
    end
  end
end
