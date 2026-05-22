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
    plug OpenApiSpex.Plug.PutApiSpec, module: SummonerWeb.API.ApiSpec
  end

  pipeline :scoped_api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: SummonerWeb.API.ApiSpec
    plug SummonerWeb.Plugs.ScopeFromPath
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

      live "/tenants", TenantLive.Index, :index
      live "/tenants/new", TenantLive.New, :new
      live "/themes", ThemeLive.Index, :index
    end
  end

  # Admin LiveView routes (require auth + admin role)
  live_session :admin,
    on_mount: [
      {SummonerWeb.UserAuth, :ensure_authenticated},
      {SummonerWeb.AdminAuth, :ensure_admin}
    ] do
    scope "/admin", SummonerWeb do
      pipe_through [:browser, :require_authenticated_user]

      live "/", AdminLive.Dashboard, :index
      live "/users", AdminLive.UserIndex, :index
      live "/users/:id", AdminLive.UserShow, :show
      live "/workspaces", AdminLive.WorkspaceIndex, :index
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
    scope "/tenants/:tenant_id", SummonerWeb do
      pipe_through [:browser, :require_authenticated_user]

      live "/workspaces", WorkspaceLive.Index, :tenant_index
      live "/workspaces/new", WorkspaceLive.New, :new
      live "/edit", TenantLive.Edit, :edit

      live "/providers", TenantProviderLive.Index, :index
      live "/providers/new", TenantProviderLive.Form, :new
      live "/providers/:id/edit", TenantProviderLive.Form, :edit
      live "/secrets", TenantSecretLive.Index, :index
      live "/secrets/new", TenantSecretLive.Form, :new
      live "/secrets/:id/edit", TenantSecretLive.Form, :edit
      live "/mcp-servers", TenantMcpServerLive.Index, :index
      live "/mcp-servers/new", TenantMcpServerLive.Form, :new
      live "/mcp-servers/:id/edit", TenantMcpServerLive.Form, :edit
      live "/skills", TenantSkillLive.Index, :index
      live "/skills/new", TenantSkillLive.Form, :new
      live "/skills/:id/edit", TenantSkillLive.Form, :edit
      live "/media-providers", TenantMediaProviderLive.Index, :index
      live "/media-providers/new", TenantMediaProviderLive.Form, :new
      live "/media-providers/:id/edit", TenantMediaProviderLive.Form, :edit
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
    scope "/tenants/:tenant_id", SummonerWeb do
      pipe_through [:browser, :require_authenticated_user]

      live "/workspaces/:workspace_id", WorkspaceLive.Show, :show
      live "/workspaces/:workspace_id/settings", WorkspaceLive.Settings, :settings
      live "/workspaces/:workspace_id/members", WorkspaceLive.Members, :members
      live "/workspaces/:workspace_id/providers", ProviderLive.Index, :index
      live "/workspaces/:workspace_id/providers/new", ProviderLive.Form, :new
      live "/workspaces/:workspace_id/providers/:id", ProviderLive.Show, :show
      live "/workspaces/:workspace_id/providers/:id/edit", ProviderLive.Form, :edit
      live "/workspaces/:workspace_id/agents", AgentLive.Index, :index
      live "/workspaces/:workspace_id/agents/new", AgentLive.Form, :new
      live "/workspaces/:workspace_id/agents/:id", AgentLive.Show, :show
      live "/workspaces/:workspace_id/agents/:id/edit", AgentLive.Form, :edit
      live "/workspaces/:workspace_id/agents/:id/mcp-servers", AgentLive.Tools, :tools
      live "/workspaces/:workspace_id/agents/:id/skills", AgentLive.Skills, :skills
      live "/workspaces/:workspace_id/agents/:id/memories", AgentLive.Memories, :memories
      live "/workspaces/:workspace_id/conversations", ConversationLive.Index, :index

      live "/workspaces/:workspace_id/conversations/:conversation_id",
           ConversationLive.Show,
           :show

      live "/workspaces/:workspace_id/mcp-servers", McpServerLive.Index, :index
      live "/workspaces/:workspace_id/mcp-servers/new", McpServerLive.Form, :new
      live "/workspaces/:workspace_id/mcp-servers/:id/edit", McpServerLive.Form, :edit
      live "/workspaces/:workspace_id/pipelines", PipelineLive.Index, :index
      live "/workspaces/:workspace_id/pipelines/new", PipelineLive.Form, :new
      live "/workspaces/:workspace_id/pipelines/:id/edit", PipelineLive.Form, :edit
      live "/workspaces/:workspace_id/pipelines/:id", PipelineLive.Show, :show
      live "/workspaces/:workspace_id/pipelines/:id/runs/:run_id", PipelineLive.RunShow, :run_show
      live "/workspaces/:workspace_id/swarms", SwarmLive.Index, :index
      live "/workspaces/:workspace_id/swarms/new", SwarmLive.Form, :new
      live "/workspaces/:workspace_id/swarms/:id/edit", SwarmLive.Form, :edit
      live "/workspaces/:workspace_id/swarms/:id", SwarmLive.Show, :show
      live "/workspaces/:workspace_id/swarms/:id/conversations", SwarmLive.Conversations, :index

      live "/workspaces/:workspace_id/swarms/:id/conversations/:conversation_id",
           SwarmLive.Session,
           :show

      live "/workspaces/:workspace_id/media-providers", MediaProviderLive.Index, :index
      live "/workspaces/:workspace_id/media-providers/new", MediaProviderLive.Form, :new
      live "/workspaces/:workspace_id/media-providers/:id/edit", MediaProviderLive.Form, :edit
      live "/workspaces/:workspace_id/secrets", SecretLive.Index, :index
      live "/workspaces/:workspace_id/secrets/new", SecretLive.Form, :new
      live "/workspaces/:workspace_id/secrets/:id/edit", SecretLive.Form, :edit
      live "/workspaces/:workspace_id/artifacts", ArtifactLive.Index, :index
      live "/workspaces/:workspace_id/artifacts/:id", ArtifactLive.Show, :show
      live "/workspaces/:workspace_id/approval-rules", ApprovalLive.Index, :index
      live "/workspaces/:workspace_id/approval-rules/new", ApprovalLive.Form, :new
      live "/workspaces/:workspace_id/approval-rules/:id/edit", ApprovalLive.Form, :edit
      live "/workspaces/:workspace_id/event-rules", EventRuleLive.Index, :index
      live "/workspaces/:workspace_id/event-rules/new", EventRuleLive.Form, :new
      live "/workspaces/:workspace_id/event-rules/:id", EventRuleLive.Show, :show
      live "/workspaces/:workspace_id/event-rules/:id/edit", EventRuleLive.Form, :edit
      live "/workspaces/:workspace_id/pending-approvals", ApprovalLive.Pending, :index
      live "/workspaces/:workspace_id/pending-approvals/:id", ApprovalLive.Show, :show
      live "/workspaces/:workspace_id/skills", SkillLive.Index, :index
      live "/workspaces/:workspace_id/skills/new", SkillLive.Form, :new
      live "/workspaces/:workspace_id/skills/:id/edit", SkillLive.Form, :edit
      live "/workspaces/:workspace_id/gallery", GalleryLive.Index, :index
      live "/workspaces/:workspace_id/files", FileBrowserLive.Index, :index
      live "/workspaces/:workspace_id/files/*path", FileBrowserLive.Index, :show
      live "/workspaces/:workspace_id/remote-agents", A2AClientLive.Index, :index
      live "/workspaces/:workspace_id/remote-agents/new", A2AClientLive.Form, :new
      live "/workspaces/:workspace_id/remote-agents/:id", A2AClientLive.Show, :show
      live "/workspaces/:workspace_id/remote-agents/:id/edit", A2AClientLive.Form, :edit
      live "/workspaces/:workspace_id/access-tokens", AccessTokenLive.Index, :index
      live "/workspaces/:workspace_id/access-tokens/new", AccessTokenLive.Form, :new
      live "/workspaces/:workspace_id/access-tokens/:id", AccessTokenLive.Show, :show
      live "/workspaces/:workspace_id/access-tokens/:id/edit", AccessTokenLive.Form, :edit
      live "/workspaces/:workspace_id/plugins", PluginLive.Index, :index
      live "/workspaces/:workspace_id/plugins/install", PluginLive.Install, :install
      live "/workspaces/:workspace_id/plugins/:ref", PluginLive.Show, :show
      live "/workspaces/:workspace_id/knowledge-bases", KnowledgeBaseLive.Index, :index
      live "/workspaces/:workspace_id/knowledge-bases/new", KnowledgeBaseLive.Form, :new
      live "/workspaces/:workspace_id/knowledge-bases/:id", KnowledgeBaseLive.Show, :show
      live "/workspaces/:workspace_id/knowledge-bases/:id/edit", KnowledgeBaseLive.Form, :edit
    end
  end

  # OpenAPI spec endpoint (no scope prefix)
  scope "/api/v1" do
    pipe_through [:api]
    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end

  # Webhook trigger — public, explicitly scoped by URL
  scope "/api/v1/tenants/:tenant_id/workspaces/:workspace_id", SummonerWeb.API.V1 do
    pipe_through [:scoped_api]

    post "/webhooks/:id/trigger", WebhookTriggerController, :trigger
    post "/plugins/:plugin_ref/webhooks/:route", PluginWebhookController, :trigger
  end

  # REST API — token-authenticated, explicitly scoped by URL
  scope "/api/v1/tenants/:tenant_id/workspaces/:workspace_id", SummonerWeb.API.V1 do
    pipe_through [:scoped_api]

    resources "/agents", AgentController, except: [:new, :edit] do
      post "/invoke", InvocationController, :invoke
      post "/stream", StreamController, :stream
    end

    resources "/conversations", ConversationController, only: [:index, :show, :create, :delete] do
      get "/messages", ConversationController, :messages
      get "/export", ConversationController, :export
    end

    resources "/pipelines", PipelineController, except: [:new, :edit] do
      get "/runs", PipelineController, :runs
    end

    resources "/swarms", SwarmController, except: [:new, :edit]
    resources "/providers", ProviderController, except: [:new, :edit]
    resources "/secrets", SecretController, except: [:new, :edit]
    resources "/mcp-servers", McpServerController, except: [:new, :edit]
    resources "/skills", SkillController, except: [:new, :edit]
    resources "/media-providers", MediaProviderController, except: [:new, :edit]

    resources "/webhooks", WebhookController, except: [:new, :edit]

    resources "/event-rules", EventRuleController, except: [:new, :edit] do
      get "/executions", EventRuleController, :executions
    end

    post "/event-rules/test", EventRuleController, :test

    resources "/invocations", InvocationController, only: [:show] do
      get "/steps", InvocationController, :steps
      get "/events", InvocationController, :events
      post "/cancel", InvocationController, :cancel
    end

    # Usage analytics
    get "/usages", UsageController, :index
    get "/usages/breakdowns", UsageController, :breakdowns
  end

  # Admin API — token-authenticated, global (no workspace scope)
  scope "/api/v1/admin", SummonerWeb.API.V1 do
    pipe_through [:api]

    get "/tenants", AdminController, :list_tenants
    get "/users", AdminController, :list_users
    patch "/users/:id", AdminController, :update_user
    get "/invitations", AdminController, :list_invitations
    get "/stats", AdminController, :stats
  end

  # OpenAI-compatible API — token-authenticated
  scope "/v1", SummonerWeb.OpenAI do
    pipe_through [:api]

    post "/chat/completions", ChatCompletionsController, :create
    get "/models", ModelsController, :index
  end

  scope "/agents" do
    pipe_through :api

    forward "/", SummonerWeb.A2AEndpoint
  end

  # MCP Server endpoint — Streamable HTTP transport
  # Auth is handled by MCPAuth plug (Bearer token → workspace)
  pipeline :mcp do
    plug :accepts, ["json"]
    plug SummonerWeb.Plugs.MCPAuth
  end

  scope "/mcp" do
    pipe_through :mcp

    forward "/", Anubis.Server.Transport.StreamableHTTP.Plug, server: Summoner.Adapters.MCP.Server
  end

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

      get "/swaggerui", OpenApiSpex.Plug.SwaggerUI, path: "/api/v1/openapi"
    end
  end

  ## Authentication routes

  scope "/", SummonerWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/tenants/:tenant_id/register", UserRegistrationController, :new
    post "/tenants/:tenant_id/register", UserRegistrationController, :create
  end

  scope "/", SummonerWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email

    get "/tenants/:tenant_id/workspaces/:workspace_id/files/download/*path",
        FileDownloadController,
        :download

    get "/tenants/:tenant_id/workspaces/:workspace_id/files/archive",
        FileDownloadController,
        :archive

    get "/tenants/:tenant_id/workspaces/:workspace_id/artifacts/:id/download",
        ArtifactController,
        :download
  end

  scope "/", SummonerWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
