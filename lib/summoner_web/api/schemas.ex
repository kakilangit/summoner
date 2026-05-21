defmodule SummonerWeb.API.Schemas do
  @moduledoc "OpenAPI schema definitions for the Summoner REST API."

  alias OpenApiSpex.Schema

  # ── Pagination ──────────────────────────────────────────────────────

  defmodule PaginationMeta do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PaginationMeta",
      type: :object,
      properties: %{
        page: %Schema{type: :integer, example: 1},
        per_page: %Schema{type: :integer, example: 20},
        total_entries: %Schema{type: :integer, example: 42},
        total_pages: %Schema{type: :integer, example: 3}
      },
      required: [:page, :per_page, :total_entries, :total_pages]
    })
  end

  # ── Agent ───────────────────────────────────────────────────────────

  defmodule LocalAgent do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "LocalAgent",
      type: :object,
      properties: %{
        model: %Schema{type: :string},
        system_prompt: %Schema{type: :string, nullable: true},
        personality: %Schema{type: :string, nullable: true},
        max_steps: %Schema{type: :integer, default: 10},
        max_concurrent_invocations: %Schema{type: :integer, default: 1},
        max_delegation_concurrency: %Schema{type: :integer, default: 3},
        max_tokens_per_invocation: %Schema{type: :integer, default: 50_000},
        context_length: %Schema{type: :integer, nullable: true},
        step_timeout_s: %Schema{type: :integer, default: 60},
        total_timeout_s: %Schema{type: :integer, default: 300},
        stream_tokens_to_observability: %Schema{type: :boolean, default: false},
        budget_usd: %Schema{type: :number, format: :float, nullable: true},
        max_tool_concurrency: %Schema{type: :integer, nullable: true},
        provider_id: %Schema{type: :string, format: :binary_id},
        media_provider_id: %Schema{type: :string, format: :binary_id, nullable: true}
      },
      required: [:model, :provider_id]
    })
  end

  defmodule RemoteAgent do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RemoteAgent",
      type: :object,
      properties: %{
        agent_card_url: %Schema{type: :string, format: :uri},
        auth_mode: %Schema{
          type: :string,
          enum: ["bearer_token", "api_key", "oauth2", "none"],
          default: "none"
        },
        status: %Schema{type: :string, enum: ["online", "offline", "unknown"], default: "unknown"},
        timeout_s: %Schema{type: :integer, default: 300},
        card_refreshed_at: %Schema{type: :string, format: :"date-time", nullable: true},
        api_key_secret_id: %Schema{type: :string, format: :binary_id, nullable: true}
      },
      required: [:agent_card_url]
    })
  end

  defmodule Agent do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Agent",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        name: %Schema{type: :string},
        callname: %Schema{type: :string, nullable: true},
        type: %Schema{type: :string, enum: ["local", "remote"]},
        role: %Schema{type: :string, enum: ["autonomous", "worker"]},
        workspace_id: %Schema{type: :string, format: :binary_id},
        local_agent: LocalAgent,
        remote_agent: RemoteAgent,
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :type, :role, :workspace_id]
    })
  end

  defmodule AgentListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AgentListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: Agent},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  defmodule AgentParams do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AgentParams",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        callname: %Schema{type: :string},
        type: %Schema{type: :string, enum: ["local", "remote"], default: "local"},
        role: %Schema{type: :string, enum: ["autonomous", "worker"]},
        local_agent: %Schema{
          type: :object,
          properties: %{
            model: %Schema{type: :string},
            system_prompt: %Schema{type: :string},
            personality: %Schema{type: :string},
            max_steps: %Schema{type: :integer},
            provider_id: %Schema{type: :string, format: :binary_id}
          }
        },
        remote_agent: %Schema{
          type: :object,
          properties: %{
            agent_card_url: %Schema{type: :string, format: :uri},
            auth_mode: %Schema{
              type: :string,
              enum: ["bearer_token", "api_key", "oauth2", "none"]
            },
            timeout_s: %Schema{type: :integer},
            api_key_secret_id: %Schema{type: :string, format: :binary_id}
          }
        }
      },
      required: [:name, :role]
    })
  end

  # ── Conversation ────────────────────────────────────────────────────

  defmodule Conversation do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Conversation",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        title: %Schema{type: :string, nullable: true},
        kind: %Schema{type: :string, enum: ["chat", "swarm", "pipeline", "a2a"]},
        provider_name: %Schema{type: :string, nullable: true},
        model_name: %Schema{type: :string, nullable: true},
        workspace_id: %Schema{type: :string, format: :binary_id},
        primary_agent_id: %Schema{type: :string, format: :binary_id},
        user_id: %Schema{type: :string, format: :binary_id, nullable: true},
        swarm_id: %Schema{type: :string, format: :binary_id, nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :workspace_id, :primary_agent_id]
    })
  end

  defmodule ConversationListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ConversationListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: Conversation},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  defmodule ConversationParams do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ConversationParams",
      type: :object,
      properties: %{
        title: %Schema{type: :string},
        primary_agent_id: %Schema{type: :string, format: :binary_id}
      },
      required: [:primary_agent_id]
    })
  end

  # ── Message ─────────────────────────────────────────────────────────

  defmodule Message do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Message",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        role: %Schema{type: :string, enum: ["user", "assistant", "system", "tool"]},
        visibility: %Schema{type: :string, enum: ["public", "internal"]},
        kind: %Schema{
          type: :string,
          enum: ["chat", "summary", "generate_image", "generate_video"]
        },
        content: %Schema{type: :array, items: %Schema{type: :object, additionalProperties: true}},
        tool_call_id: %Schema{type: :string, nullable: true},
        tool_calls: %Schema{
          type: :array,
          items: %Schema{type: :object, additionalProperties: true},
          nullable: true
        },
        token_count: %Schema{type: :integer, nullable: true},
        thinking: %Schema{type: :string, nullable: true},
        provider_name: %Schema{type: :string, nullable: true},
        model_name: %Schema{type: :string, nullable: true},
        agent_id: %Schema{type: :string, format: :binary_id, nullable: true},
        conversation_id: %Schema{type: :string, format: :binary_id},
        invocation_id: %Schema{type: :string, format: :binary_id, nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :role, :conversation_id]
    })
  end

  defmodule MessageListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "MessageListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: Message},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  # ── Invocation ──────────────────────────────────────────────────────

  defmodule InvokeParams do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "InvokeParams",
      type: :object,
      properties: %{
        message: %Schema{type: :string, description: "The user message to send"},
        conversation_id: %Schema{
          type: :string,
          format: :binary_id,
          description: "Reuse existing conversation",
          nullable: true
        }
      },
      required: [:message]
    })
  end

  defmodule InvokeResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "InvokeResponse",
      type: :object,
      properties: %{
        invocation_id: %Schema{type: :string, format: :binary_id},
        status: %Schema{
          type: :string,
          enum: ~w(queued running completed failed handed_off awaiting_user cancelled)
        },
        end_reason: %Schema{
          type: :string,
          enum:
            ~w(completed failed cancelled stale handed_off token_limit_reached step_limit_reached total_timeout worker_unavailable escalation_unresolved empty_response doom_loop context_overflow),
          nullable: true
        },
        output: %Schema{type: :object, additionalProperties: true, nullable: true},
        agent_id: %Schema{type: :string, format: :binary_id},
        conversation_id: %Schema{type: :string, format: :binary_id},
        started_at: %Schema{type: :string, format: :"date-time"},
        completed_at: %Schema{type: :string, format: :"date-time", nullable: true},
        provider_name: %Schema{type: :string, nullable: true},
        model_name: %Schema{type: :string, nullable: true},
        messages: %Schema{type: :array, items: Message}
      }
    })
  end

  defmodule Invocation do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Invocation",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        status: %Schema{
          type: :string,
          enum: ~w(queued running completed failed handed_off awaiting_user cancelled)
        },
        end_reason: %Schema{
          type: :string,
          enum:
            ~w(completed failed cancelled stale handed_off token_limit_reached step_limit_reached total_timeout worker_unavailable escalation_unresolved empty_response doom_loop context_overflow),
          nullable: true
        },
        input: %Schema{type: :object, additionalProperties: true, nullable: true},
        output: %Schema{type: :object, additionalProperties: true, nullable: true},
        depth: %Schema{type: :integer},
        agent_id: %Schema{type: :string, format: :binary_id},
        conversation_id: %Schema{type: :string, format: :binary_id},
        workspace_id: %Schema{type: :string, format: :binary_id},
        parent_invocation_id: %Schema{type: :string, format: :binary_id, nullable: true},
        started_at: %Schema{type: :string, format: :"date-time"},
        completed_at: %Schema{type: :string, format: :"date-time", nullable: true},
        provider_name: %Schema{type: :string, nullable: true},
        model_name: %Schema{type: :string, nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :status, :agent_id, :conversation_id, :workspace_id]
    })
  end

  # ── Step ────────────────────────────────────────────────────────────

  defmodule Step do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Step",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        step_number: %Schema{type: :integer},
        reasoning: %Schema{type: :string, nullable: true},
        tool_name: %Schema{type: :string, nullable: true},
        tool_input: %Schema{type: :object, additionalProperties: true, nullable: true},
        tool_output: %Schema{type: :object, additionalProperties: true, nullable: true},
        status: %Schema{type: :string, enum: ["ok", "error"]},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :step_number, :status]
    })
  end

  defmodule StepListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "StepListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: Step},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  # ── Event ───────────────────────────────────────────────────────────

  defmodule Event do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Event",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        event_type: %Schema{
          type: :string,
          enum:
            ~w(planning_started subtask_created subtask_claimed subtask_completed tool_started tool_finished tool_failed handoff_started handoff_completed pipeline_stage_started pipeline_stage_completed awaiting_user token_limit_reached completed failed reaper)
        },
        visibility: %Schema{type: :string, enum: ["public", "internal"]},
        summary: %Schema{type: :string, nullable: true},
        payload: %Schema{type: :object, additionalProperties: true, nullable: true},
        agent_id: %Schema{type: :string, format: :binary_id, nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :event_type, :visibility]
    })
  end

  defmodule EventListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "EventListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: Event},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  # ── Provider ────────────────────────────────────────────────────────

  defmodule Provider do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Provider",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        name: %Schema{type: :string},
        kind: %Schema{type: :string},
        api_format: %Schema{type: :string, enum: ["openai", "anthropic", "custom"]},
        type: %Schema{type: :string, enum: ["local", "cloud"]},
        base_url: %Schema{type: :string, format: :uri},
        status: %Schema{type: :string, enum: ["online", "offline", "unknown"]},
        cached_models: %Schema{type: :array, items: %Schema{type: :string}},
        workspace_id: %Schema{type: :string, format: :binary_id},
        tenant_id: %Schema{type: :string, format: :binary_id},
        api_key_secret_id: %Schema{type: :string, format: :binary_id, nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :kind, :api_format, :type, :base_url]
    })
  end

  defmodule ProviderListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ProviderListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: Provider},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  defmodule ProviderParams do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ProviderParams",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        kind: %Schema{type: :string},
        api_format: %Schema{type: :string, enum: ["openai", "anthropic", "custom"]},
        type: %Schema{type: :string, enum: ["local", "cloud"]},
        base_url: %Schema{type: :string, format: :uri},
        api_key_secret_id: %Schema{type: :string, format: :binary_id}
      },
      required: [:name, :kind, :api_format, :type, :base_url]
    })
  end

  # ── Secret ──────────────────────────────────────────────────────────

  defmodule Secret do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Secret",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        name: %Schema{type: :string, pattern: "^[A-Z][A-Z0-9_]*$"},
        description: %Schema{type: :string, nullable: true},
        workspace_id: %Schema{type: :string, format: :binary_id},
        tenant_id: %Schema{type: :string, format: :binary_id},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name]
    })
  end

  defmodule SecretListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SecretListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: Secret},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  defmodule SecretParams do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SecretParams",
      type: :object,
      properties: %{
        name: %Schema{type: :string, pattern: "^[A-Z][A-Z0-9_]*$"},
        description: %Schema{type: :string},
        encrypted_value: %Schema{
          type: :string,
          description: "Plaintext value (encrypted at rest)"
        }
      },
      required: [:name, :encrypted_value]
    })
  end

  # ── Skill ───────────────────────────────────────────────────────────

  defmodule Skill do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Skill",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        name: %Schema{type: :string},
        content: %Schema{type: :string},
        workspace_id: %Schema{type: :string, format: :binary_id},
        tenant_id: %Schema{type: :string, format: :binary_id},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :content]
    })
  end

  defmodule SkillListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SkillListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: Skill},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  defmodule SkillParams do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SkillParams",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        content: %Schema{type: :string}
      },
      required: [:name, :content]
    })
  end

  # ── McpServer ───────────────────────────────────────────────────────

  defmodule McpServer do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "McpServer",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        name: %Schema{type: :string},
        transport: %Schema{type: :string, enum: ["stdio", "http"]},
        command_or_url: %Schema{type: :string},
        config: %Schema{type: :object, additionalProperties: true},
        workspace_id: %Schema{type: :string, format: :binary_id},
        tenant_id: %Schema{type: :string, format: :binary_id},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :transport, :command_or_url]
    })
  end

  defmodule McpServerListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "McpServerListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: McpServer},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  defmodule McpServerParams do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "McpServerParams",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        transport: %Schema{type: :string, enum: ["stdio", "http"]},
        command_or_url: %Schema{type: :string},
        config: %Schema{type: :object, additionalProperties: true}
      },
      required: [:name, :transport, :command_or_url]
    })
  end

  # ── MediaProvider ───────────────────────────────────────────────────

  defmodule MediaProvider do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "MediaProvider",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        name: %Schema{type: :string},
        default_image_model: %Schema{type: :string, nullable: true},
        default_video_model: %Schema{type: :string, nullable: true},
        max_concurrent_jobs: %Schema{type: :integer, default: 3},
        config: %Schema{type: :object, additionalProperties: true},
        workspace_id: %Schema{type: :string, format: :binary_id},
        tenant_id: %Schema{type: :string, format: :binary_id},
        provider_id: %Schema{type: :string, format: :binary_id},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :provider_id]
    })
  end

  defmodule MediaProviderListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "MediaProviderListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: MediaProvider},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  defmodule MediaProviderParams do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "MediaProviderParams",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        default_image_model: %Schema{type: :string},
        default_video_model: %Schema{type: :string},
        max_concurrent_jobs: %Schema{type: :integer},
        config: %Schema{type: :object, additionalProperties: true},
        provider_id: %Schema{type: :string, format: :binary_id}
      },
      required: [:name, :provider_id]
    })
  end

  # ── Pipeline ────────────────────────────────────────────────────────

  defmodule PipelineStage do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PipelineStage",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        position: %Schema{type: :integer},
        instruction: %Schema{type: :string, nullable: true},
        depends_on_positions: %Schema{type: :array, items: %Schema{type: :integer}},
        skill: %Schema{type: :string, nullable: true},
        agent_id: %Schema{type: :string, format: :binary_id},
        pipeline_id: %Schema{type: :string, format: :binary_id},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :position, :agent_id]
    })
  end

  defmodule Pipeline do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Pipeline",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        name: %Schema{type: :string},
        mode: %Schema{type: :string, enum: ["simple", "orchestrated"]},
        trigger_type: %Schema{type: :string, enum: ["manual", "scheduled"]},
        cron_expression: %Schema{type: :string, nullable: true},
        workspace_id: %Schema{type: :string, format: :binary_id},
        orchestrator_agent_id: %Schema{type: :string, format: :binary_id, nullable: true},
        conversation_id: %Schema{type: :string, format: :binary_id, nullable: true},
        stages: %Schema{type: :array, items: PipelineStage},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :mode, :trigger_type]
    })
  end

  defmodule PipelineListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PipelineListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: Pipeline},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  defmodule PipelineRun do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PipelineRun",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        status: %Schema{type: :string, enum: ["running", "completed", "failed", "cancelled"]},
        input: %Schema{type: :string, nullable: true},
        output: %Schema{type: :string, nullable: true},
        error: %Schema{type: :string, nullable: true},
        started_at: %Schema{type: :string, format: :"date-time"},
        completed_at: %Schema{type: :string, format: :"date-time", nullable: true},
        pipeline_id: %Schema{type: :string, format: :binary_id},
        workspace_id: %Schema{type: :string, format: :binary_id},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :status, :pipeline_id]
    })
  end

  defmodule PipelineRunListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PipelineRunListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: PipelineRun},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  defmodule PipelineParams do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PipelineParams",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        mode: %Schema{type: :string, enum: ["simple", "orchestrated"]},
        trigger_type: %Schema{type: :string, enum: ["manual", "scheduled"]},
        cron_expression: %Schema{type: :string},
        orchestrator_agent_id: %Schema{type: :string, format: :binary_id},
        stages: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              position: %Schema{type: :integer},
              instruction: %Schema{type: :string},
              depends_on_positions: %Schema{type: :array, items: %Schema{type: :integer}},
              skill: %Schema{type: :string},
              agent_id: %Schema{type: :string, format: :binary_id}
            },
            required: [:position, :agent_id]
          }
        }
      },
      required: [:name]
    })
  end

  # ── Swarm ───────────────────────────────────────────────────────────

  defmodule SwarmMember do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SwarmMember",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        position: %Schema{type: :integer},
        agent_id: %Schema{type: :string, format: :binary_id},
        swarm_id: %Schema{type: :string, format: :binary_id},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :agent_id, :swarm_id]
    })
  end

  defmodule Swarm do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Swarm",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        name: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        mode: %Schema{type: :string, enum: ["round_robin", "relay", "directed"]},
        max_turns: %Schema{type: :integer, default: 20},
        workspace_id: %Schema{type: :string, format: :binary_id},
        coordinator_agent_id: %Schema{type: :string, format: :binary_id, nullable: true},
        members: %Schema{type: :array, items: SwarmMember},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :mode]
    })
  end

  defmodule SwarmListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SwarmListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: Swarm},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  defmodule SwarmParams do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SwarmParams",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        description: %Schema{type: :string},
        mode: %Schema{type: :string, enum: ["round_robin", "relay", "directed"]},
        max_turns: %Schema{type: :integer},
        coordinator_agent_id: %Schema{type: :string, format: :binary_id},
        members: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              position: %Schema{type: :integer},
              agent_id: %Schema{type: :string, format: :binary_id}
            },
            required: [:agent_id]
          }
        }
      },
      required: [:name]
    })
  end

  # ── Admin ───────────────────────────────────────────────────────────

  defmodule Tenant do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Tenant",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        name: %Schema{type: :string},
        disabled_at: %Schema{type: :string, format: :"date-time", nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name]
    })
  end

  defmodule TenantListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "TenantListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: Tenant},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  defmodule User do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "User",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        email: %Schema{type: :string, format: :email},
        role: %Schema{type: :string},
        confirmed_at: %Schema{type: :string, format: :"date-time", nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :email]
    })
  end

  defmodule UserListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "UserListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: User},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  defmodule UserUpdateParams do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "UserUpdateParams",
      type: :object,
      properties: %{
        action: %Schema{
          type: :string,
          enum: ["disable", "enable"],
          description: "Enable or disable the user"
        },
        role: %Schema{type: :string, description: "Change user role"}
      }
    })
  end

  defmodule Invitation do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Invitation",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        code: %Schema{type: :string},
        tenant_id: %Schema{type: :string, format: :binary_id},
        status: %Schema{type: :string, enum: ["used", "expired", "available"]},
        expires_at: %Schema{type: :string, format: :"date-time"},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :code, :tenant_id, :status]
    })
  end

  defmodule InvitationListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "InvitationListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: Invitation},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  # ── Usage ───────────────────────────────────────────────────────────

  defmodule UsageResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "UsageResponse",
      type: :object,
      properties: %{
        rolling_30_day_tokens: %Schema{type: :integer},
        rolling_30_day_cost: %Schema{type: :number, format: :float}
      }
    })
  end

  defmodule UsageBreakdownEntry do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "UsageBreakdownEntry",
      type: :object,
      properties: %{
        agent_id: %Schema{type: :string, format: :binary_id, nullable: true},
        model: %Schema{type: :string, nullable: true},
        provider_id: %Schema{type: :string, format: :binary_id, nullable: true},
        total_tokens: %Schema{type: :integer},
        prompt_tokens: %Schema{type: :integer},
        completion_tokens: %Schema{type: :integer},
        invocation_count: %Schema{type: :integer}
      }
    })
  end

  defmodule UsageBreakdownResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "UsageBreakdownResponse",
      type: :object,
      properties: %{
        by_agent: %Schema{type: :array, items: UsageBreakdownEntry},
        by_model: %Schema{type: :array, items: UsageBreakdownEntry},
        by_provider: %Schema{type: :array, items: UsageBreakdownEntry}
      }
    })
  end

  # ── Error ───────────────────────────────────────────────────────────

  defmodule ErrorResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ErrorResponse",
      type: :object,
      properties: %{
        error: %Schema{
          type: :object,
          properties: %{
            code: %Schema{type: :string},
            message: %Schema{type: :string}
          },
          required: [:code, :message]
        }
      },
      required: [:error]
    })
  end

  # ── Webhook ──────────────────────────────────────────────────────────

  defmodule Webhook do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Webhook",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :binary_id},
        name: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        target_type: %Schema{type: :string, enum: ["agent", "pipeline", "swarm"]},
        target_id: %Schema{type: :string, format: :binary_id},
        auth_mode: %Schema{type: :string, enum: ["public", "token", "hmac"]},
        hmac_secret_id: %Schema{type: :string, format: :binary_id, nullable: true},
        transform: %Schema{type: :string, nullable: true},
        response_mode: %Schema{type: :string, enum: ["sync", "async", "stream"]},
        rate_limit_rpm: %Schema{type: :integer},
        timeout_s: %Schema{type: :integer},
        enabled: %Schema{type: :boolean},
        last_triggered_at: %Schema{type: :string, format: :"date-time", nullable: true},
        trigger_count: %Schema{type: :integer},
        workspace_id: %Schema{type: :string, format: :binary_id},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :target_type, :target_id, :auth_mode, :response_mode]
    })
  end

  defmodule WebhookListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "WebhookListResponse",
      type: :object,
      properties: %{
        items: %Schema{type: :array, items: Webhook},
        meta: PaginationMeta
      },
      required: [:items, :meta]
    })
  end

  defmodule WebhookParams do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "WebhookParams",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        description: %Schema{type: :string},
        target_type: %Schema{type: :string, enum: ["agent", "pipeline", "swarm"]},
        target_id: %Schema{type: :string, format: :binary_id},
        auth_mode: %Schema{type: :string, enum: ["public", "token", "hmac"]},
        hmac_secret_id: %Schema{type: :string, format: :binary_id},
        transform: %Schema{type: :string},
        response_mode: %Schema{type: :string, enum: ["sync", "async", "stream"]},
        rate_limit_rpm: %Schema{type: :integer},
        timeout_s: %Schema{type: :integer},
        enabled: %Schema{type: :boolean}
      },
      required: [:name, :target_type, :target_id]
    })
  end

  defmodule WebhookTriggerParams do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "WebhookTriggerParams",
      type: :object,
      properties: %{
        message: %Schema{type: :string, description: "Message to send to the target agent"}
      },
      additionalProperties: true
    })
  end

  defmodule WebhookTriggerResult do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "WebhookTriggerResult",
      type: :object,
      properties: %{
        conversation_id: %Schema{type: :string, format: :binary_id},
        invocation_id: %Schema{type: :string, format: :binary_id},
        status: %Schema{type: :string}
      }
    })
  end
end
