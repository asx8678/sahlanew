defmodule SahlaWeb.AdminAuthz do
  @moduledoc """
  Central per-role authorization for admin routes (§10), as both a plug and a
  LiveView `on_mount` hook so HTTP and LiveView paths share one policy
  (`Sahla.Accounts.Policy`).

  Usage:

      plug SahlaWeb.AdminAuthz, capability: :leads
      live_session :ops, on_mount: [{SahlaWeb.AdminAuthz, :leads}]

  Denied requests halt with 403 rendered via the error view; denied mounts halt
  with a redirect. An optional IP allowlist (Settings-gated, feature-flag
  pattern) blocks non-listed source IPs at the HTTP layer.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Sahla.Accounts.Policy
  alias Sahla.Settings

  @ip_flag "admin_ip_allowlist"

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    capability = Keyword.fetch!(opts, :capability)

    if ip_allowed?(conn) and authorized?(conn.assigns[:current_admin], capability) do
      conn
    else
      forbid(conn)
    end
  end

  @doc "LiveView hook: `on_mount: [{SahlaWeb.AdminAuthz, :leads}]`."
  def on_mount(capability, _params, _session, socket) when is_atom(capability) do
    if authorized?(socket.assigns[:current_admin], capability) do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end

  defp authorized?(nil, _capability), do: false
  defp authorized?(%{role: role}, capability), do: Policy.can?(role, capability)

  defp ip_allowed?(conn) do
    if Settings.feature_enabled?(@ip_flag) do
      client_ip(conn) in Settings.get(@ip_flag, [])
    else
      true
    end
  end

  defp client_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp forbid(conn) do
    conn
    |> put_status(:forbidden)
    |> put_view(SahlaWeb.ErrorHTML)
    |> render("403.html")
    |> halt()
  end
end
