defmodule SummonerWeb.Router do
  use SummonerWeb, :router

  import SummonerWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SummonerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SummonerWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Authenticated LiveView routes
  live_session :authenticated,
    on_mount: [{SummonerWeb.UserAuth, :ensure_authenticated}] do
    scope "/", SummonerWeb do
      pipe_through [:browser, :require_authenticated_user]

      live "/guilds", TenantLive.Index, :index
      live "/guilds/new", TenantLive.New, :new
      live "/themes", ThemeLive.Index, :index
    end
  end

  # Admin LiveView routes (require auth + admin role)
  live_session :admin,
    on_mount: [
      {SummonerWeb.UserAuth, :ensure_authenticated},
      {SummonerWeb.AdminAuth, :ensure_admin}
    ] do
    scope "/archon", SummonerWeb do
      pipe_through [:browser, :require_authenticated_user]

      live "/", AdminLive.Dashboard, :index
      live "/users", AdminLive.UserIndex, :index
      live "/users/:id", AdminLive.UserShow, :show
      live "/realms", AdminLive.WorkspaceIndex, :index
      live "/invites", AdminLive.InvitationIndex, :index
      live "/quotas", AdminLive.QuotaIndex, :index
    end
  end

  # Tenant-scoped LiveView routes (require auth + tenant membership)
  live_session :tenant,
    on_mount: [
      {SummonerWeb.UserAuth, :ensure_authenticated},
      {SummonerWeb.TenantAuth, :ensure_tenant_member}
    ] do
    scope "/guilds/:tenant_id", SummonerWeb do
      pipe_through [:browser, :require_authenticated_user]

      live "/realms", WorkspaceLive.Index, :tenant_index
      live "/realms/new", WorkspaceLive.New, :new
      live "/edit", TenantLive.Edit, :edit

      live "/gateways", TenantProviderLive.Index, :index
      live "/gateways/new", TenantProviderLive.Form, :new
      live "/gateways/:id/edit", TenantProviderLive.Form, :edit
      live "/seals", TenantSecretLive.Index, :index
      live "/seals/new", TenantSecretLive.Form, :new
      live "/seals/:id/edit", TenantSecretLive.Form, :edit
      live "/runes", TenantMcpServerLive.Index, :index
      live "/runes/new", TenantMcpServerLive.Form, :new
      live "/runes/:id/edit", TenantMcpServerLive.Form, :edit
      live "/spells", TenantSkillLive.Index, :index
      live "/spells/new", TenantSkillLive.Form, :new
      live "/spells/:id/edit", TenantSkillLive.Form, :edit
      live "/forges", TenantMediaProviderLive.Index, :index
      live "/forges/new", TenantMediaProviderLive.Form, :new
      live "/forges/:id/edit", TenantMediaProviderLive.Form, :edit
      live "/invites", TenantInvitationLive.Index, :index
    end
  end

  # Workspace-scoped LiveView routes (require auth + tenant + workspace membership)
  live_session :workspace,
    on_mount: [
      {SummonerWeb.UserAuth, :ensure_authenticated},
      {SummonerWeb.TenantAuth, :ensure_tenant_member},
      {SummonerWeb.WorkspaceAuth, :ensure_workspace_member}
    ] do
    scope "/guilds/:tenant_id", SummonerWeb do
      pipe_through [:browser, :require_authenticated_user]

      live "/realms/:workspace_id", WorkspaceLive.Show, :show
      live "/realms/:workspace_id/settings", WorkspaceLive.Settings, :settings
      live "/realms/:workspace_id/members", WorkspaceLive.Members, :members
      live "/realms/:workspace_id/gateways", ProviderLive.Index, :index
      live "/realms/:workspace_id/gateways/new", ProviderLive.Form, :new
      live "/realms/:workspace_id/gateways/:id", ProviderLive.Show, :show
      live "/realms/:workspace_id/gateways/:id/edit", ProviderLive.Form, :edit
      live "/realms/:workspace_id/summons", AgentLive.Index, :index
      live "/realms/:workspace_id/summons/new", AgentLive.Form, :new
      live "/realms/:workspace_id/summons/:id", AgentLive.Show, :show
      live "/realms/:workspace_id/summons/:id/edit", AgentLive.Form, :edit
      live "/realms/:workspace_id/summons/:id/runes", AgentLive.Tools, :tools
      live "/realms/:workspace_id/summons/:id/skills", AgentLive.Skills, :skills
      live "/realms/:workspace_id/channels", ConversationLive.Index, :index
      live "/realms/:workspace_id/channels/:conversation_id", ConversationLive.Show, :show
      live "/realms/:workspace_id/runes", McpServerLive.Index, :index
      live "/realms/:workspace_id/runes/new", McpServerLive.Form, :new
      live "/realms/:workspace_id/runes/:id/edit", McpServerLive.Form, :edit
      live "/realms/:workspace_id/quests", PipelineLive.Index, :index
      live "/realms/:workspace_id/quests/new", PipelineLive.Form, :new
      live "/realms/:workspace_id/quests/:id/edit", PipelineLive.Form, :edit
      live "/realms/:workspace_id/quests/:id", PipelineLive.Show, :show
      live "/realms/:workspace_id/quests/:id/runs/:run_id", PipelineLive.RunShow, :run_show
      live "/realms/:workspace_id/parties", SwarmLive.Index, :index
      live "/realms/:workspace_id/parties/new", SwarmLive.Form, :new
      live "/realms/:workspace_id/parties/:id/edit", SwarmLive.Form, :edit
      live "/realms/:workspace_id/parties/:id", SwarmLive.Show, :show
      live "/realms/:workspace_id/parties/:id/channels", SwarmLive.Conversations, :index

      live "/realms/:workspace_id/parties/:id/channels/:conversation_id",
           SwarmLive.Session,
           :show

      live "/realms/:workspace_id/forges", MediaProviderLive.Index, :index
      live "/realms/:workspace_id/forges/new", MediaProviderLive.Form, :new
      live "/realms/:workspace_id/forges/:id/edit", MediaProviderLive.Form, :edit
      live "/realms/:workspace_id/seals", SecretLive.Index, :index
      live "/realms/:workspace_id/seals/new", SecretLive.Form, :new
      live "/realms/:workspace_id/seals/:id/edit", SecretLive.Form, :edit
      live "/realms/:workspace_id/spells", SkillLive.Index, :index
      live "/realms/:workspace_id/spells/new", SkillLive.Form, :new
      live "/realms/:workspace_id/spells/:id/edit", SkillLive.Form, :edit
      live "/realms/:workspace_id/gallery", GalleryLive.Index, :index
      live "/realms/:workspace_id/scrolls", FileBrowserLive.Index, :index
      live "/realms/:workspace_id/scrolls/*path", FileBrowserLive.Index, :show
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", SummonerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:summoner, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard",
        metrics: SummonerWeb.Telemetry,
        additional_pages: [oban: Oban.LiveDashboard]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", SummonerWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/guilds/:tenant_id/register", UserRegistrationController, :new
    post "/guilds/:tenant_id/register", UserRegistrationController, :create
  end

  scope "/", SummonerWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email

    get "/guilds/:tenant_id/realms/:workspace_id/files/download/*path",
        FileDownloadController,
        :download

    get "/guilds/:tenant_id/realms/:workspace_id/files/archive",
        FileDownloadController,
        :archive
  end

  scope "/", SummonerWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
