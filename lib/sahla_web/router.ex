defmodule SahlaWeb.Router do
  use SahlaWeb, :router

  import SahlaWeb.AdminAuth, only: [fetch_current_admin: 2, require_authenticated_admin: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug SahlaWeb.Plugs.Locale
    plug :fetch_live_flash
    plug :put_root_layout, html: {SahlaWeb.Layouts, :root}
    plug :protect_from_forgery
    # Strict, LiveView-safe CSP with a per-request nonce, plus frame/referrer/
    # permissions headers (§12).
    plug SahlaWeb.Plugs.SecureHeaders
  end

  # Admin tier: a distinct pipeline so authentication/authorization (r5o.3,
  # r5o.5) and an admin layout can be layered on independently of the public
  # site (§10).
  pipeline :admin do
    plug :accepts, ["html"]
    plug :fetch_session
    plug SahlaWeb.Plugs.Locale
    plug :fetch_live_flash
    plug :put_root_layout, html: {SahlaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug SahlaWeb.Plugs.SecureHeaders
    plug :fetch_current_admin
  end

  # Provider callbacks (SMS/payment/WhatsApp) can't carry our CSRF token, so
  # this pipeline is deliberately CSRF-exempt. Each webhook is signature-verified
  # in its context via Plug.Crypto.secure_compare (Lessons) — not here.
  pipeline :webhook do
    plug :accepts, ["json"]
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Health probe: no session/CSRF so it stays cheap and always reachable for
  # uptime monitors and the deploy rollback gate.
  scope "/", SahlaWeb do
    get "/health", HealthController, :index
  end

  # Public routes are mirrored under `/` (French) and `/ar` (Arabic) so every page
  # is a first-class bilingual route (§5.1, §6.3). The two scopes MUST stay in
  # sync — any public route added below is added to both. LiveViews inherit their
  # locale from `SahlaWeb.LocaleHook` via this live_session.
  live_session :public, on_mount: [SahlaWeb.LocaleHook] do
    scope "/", SahlaWeb do
      pipe_through :browser

      get "/", PageController, :home
      get "/design-tokens", DesignTokenController, :index
      get "/design/components", ComponentsController, :index
    end

    scope "/ar", SahlaWeb, as: :ar do
      pipe_through :browser

      get "/", PageController, :home
      get "/design-tokens", DesignTokenController, :index
      get "/design/components", ComponentsController, :index
    end
  end

  # Admin authentication: reachable WITHOUT a session (login + the half-auth 2FA
  # stage). No route here mints a full session except a verified TOTP code.
  pipeline :require_admin do
    plug :require_authenticated_admin
  end

  scope "/admin", SahlaWeb.Admin, as: :admin do
    pipe_through :admin

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete

    # Stage two — pending (password-verified) admin only; enforced in-controller.
    get "/totp/setup", TotpController, :setup
    post "/totp/setup", TotpController, :confirm
    get "/totp", TotpController, :verify
    post "/totp", TotpController, :submit
  end

  # Protected admin surfaces: a full (2FA-complete) session is mandatory.
  scope "/admin", SahlaWeb.Admin, as: :admin do
    pipe_through [:admin, :require_admin]

    get "/", DashboardController, :index
  end

  scope "/webhooks", SahlaWeb.Webhooks, as: :webhook do
    pipe_through :webhook
    # Signature-verified provider callbacks land here later.
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:sahla, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SahlaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
