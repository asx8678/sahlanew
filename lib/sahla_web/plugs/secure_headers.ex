defmodule SahlaWeb.Plugs.SecureHeaders do
  @moduledoc """
  Strict, LiveView-compatible security headers (§12, §13.6).

  Generates a **per-request CSP nonce**, assigns it as `:csp_nonce` (the root
  layout stamps it on its inline `<script>` so no `unsafe-inline` is needed), and
  sets a Content-Security-Policy that allows `'self'` and the LiveView `ws:`/`wss:`
  socket while blocking un-nonced inline scripts. Also pins `X-Frame-Options:
  DENY`, `Referrer-Policy` and `Permissions-Policy`.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [put_secure_browser_headers: 2]

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    nonce = generate_nonce()

    conn
    |> assign(:csp_nonce, nonce)
    |> put_secure_browser_headers(headers(nonce))
  end

  defp headers(nonce) do
    %{
      "content-security-policy" => content_security_policy(nonce),
      "x-frame-options" => "DENY",
      "referrer-policy" => "strict-origin-when-cross-origin",
      "permissions-policy" => "geolocation=(), microphone=(), camera=()"
    }
  end

  defp content_security_policy(nonce) do
    Enum.join(
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{nonce}'",
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' data:",
        "font-src 'self'",
        "connect-src 'self' ws: wss:",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'"
      ],
      "; "
    )
  end

  defp generate_nonce, do: 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
