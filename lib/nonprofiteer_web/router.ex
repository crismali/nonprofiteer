defmodule NonprofiteerWeb.Router do
  use NonprofiteerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NonprofiteerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Health probe — no pipeline (no `:accepts`/CSRF) so monitors get a response regardless of
  # request headers, and it stays open even once the feed is gated (see TODO).
  scope "/", NonprofiteerWeb do
    get "/health", HealthController, :index
  end

  # Raw source-document access (D11) — the R2-mirrored 990 XML for a filing. Declared *before*
  # the AshJsonApi forward below, which otherwise swallows every `/api/v1/*` path. No pipeline
  # (like `/health`) so `:accepts ["json"]` doesn't reject the XML response's content negotiation.
  scope "/api/v1", NonprofiteerWeb do
    get "/filings/:id/source", FilingSourceController, :show
  end

  # Public JSON:API sync feed (D3/D16). Unauthenticated by design (ARCHITECTURE); an interim
  # Basic-auth gate is a follow-up (see TODO) for the early-access window.
  scope "/api/v1" do
    pipe_through [:api]

    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/v1/open_api",
      default_model_expand_depth: 4

    forward "/", NonprofiteerWeb.AshJsonApiRouter
  end

  scope "/", NonprofiteerWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", NonprofiteerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:nonprofiteer, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: NonprofiteerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  if Application.compile_env(:nonprofiteer, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
