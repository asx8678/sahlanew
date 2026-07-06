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
    # Make admin session available on public routes so authenticated-file
    # serving can authorize admins without a separate pipeline.
    plug :fetch_current_admin
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
    get "/sitemap.xml", SitemapController, :sitemap
    get "/robots.txt", SitemapController, :robots
  end

  # Private uploads (§12): served by an authenticated controller, never from
  # the static directory. The quote-token path is used for funnel relevé docs.
  scope "/uploads", SahlaWeb do
    pipe_through :browser

    get "/:basename", UploadController, :show
  end

  # Public routes are mirrored under `/` (French) and `/ar` (Arabic) so every page
  # is a first-class bilingual route (§5.1, §6.3). The two scopes MUST stay in
  # sync — any public route added below is added to both. LiveViews inherit their
  # locale from `SahlaWeb.LocaleHook` via this live_session.
  live_session :public, on_mount: [SahlaWeb.LocaleHook] do
    scope "/", SahlaWeb do
      pipe_through :browser

      live "/", HomeLive, :index
      get "/design-tokens", DesignTokenController, :index
      get "/design/components", ComponentsController, :index
      live "/devis/new", DevisLive, :new
      live "/devis/:token", DevisLive, :show
      live "/offres/:token", OffersLive, :show
      live "/guides", GuidesLive, :index
      live "/guides/:slug", GuidesLive, :show
    end

    scope "/ar", SahlaWeb, as: :ar do
      pipe_through :browser

      live "/", HomeLive, :index
      get "/design-tokens", DesignTokenController, :index
      get "/design/components", ComponentsController, :index
      live "/devis/new", DevisLive, :new
      live "/devis/:token", DevisLive, :show
      live "/offres/:token", OffersLive, :show
      live "/guides", GuidesLive, :index
      live "/guides/:slug", GuidesLive, :show
    end
  end

  # Admin authentication: reachable WITHOUT a session (login + the half-auth 2FA
  # stage). No route here mints a full session except a verified TOTP code.
  pipeline :require_admin do
    plug :require_authenticated_admin
  end

  pipeline :admin_layout do
    plug :put_root_layout, html: {SahlaWeb.Layouts, :admin}
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
    pipe_through [:admin, :require_admin, :admin_layout]

    get "/", DashboardController, :index
  end

  # Protected admin LiveViews: a full (2FA-complete) session and the :leads
  # capability are required. Live updates flow over the `leads` PubSub topic.
  live_session :admin_leads,
    on_mount: [
      {SahlaWeb.AdminAuth, :fetch_current_admin},
      {SahlaWeb.AdminAuthz, :leads}
    ] do
    scope "/admin", SahlaWeb.Admin, as: :admin do
      pipe_through [:admin, :require_admin, :admin_layout]

      live "/leads", LeadsLive.Index, :index
      live "/leads/:id", LeadLive, :show
    end
  end

  # Protected admin settings surface: a full session and the :settings
  # capability are required. The layout pipeline sets the admin root layout
  # and the :breadcrumbs assign is populated inside the LiveView.
  live_session :admin_settings,
    on_mount: [
      {SahlaWeb.AdminAuth, :fetch_current_admin},
      {SahlaWeb.AdminAuthz, :settings}
    ] do
    scope "/admin", SahlaWeb.Admin, as: :admin do
      pipe_through [:admin, :require_admin, :admin_layout]

      live "/settings", SettingsLive, :index
    end
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
