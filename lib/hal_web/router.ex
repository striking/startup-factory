defmodule HalWeb.Router do
  use HalWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HalWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Dashboard routes (browser)
  scope "/", HalWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/mission-control", MissionControlLive, :index
    live "/chat", ChatLive, :index
    live "/agent", AgentStateLive, :index
    live "/sessions", SessionsLive, :index
    live "/sessions/:id", SessionDetailLive, :show
    live "/approvals", ApprovalsLive, :index
    live "/changes", ChangeRequestsLive, :index
    live "/security", SecurityLive, :index
    live "/settings", SettingsLive, :index
  end

  # Health check routes (no authentication required for monitoring)
  scope "/health", HalWeb do
    pipe_through :api

    get "/", HealthController, :index
    get "/ready", HealthController, :ready
    get "/live", HealthController, :live
  end

  # Control-plane tool invocation (disabled unless HAL_CONTROL_PLANE_TOKEN is set)
  scope "/tools", HalWeb do
    pipe_through :api

    post "/invoke", ToolsController, :invoke
  end

  # API routes
  scope "/api", HalWeb do
    pipe_through :api
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:hal, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: HalWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
