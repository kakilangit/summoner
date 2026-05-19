defmodule Summoner.Repo.Migrations.SplitAgentsSchema do
  @moduledoc """
  Nuclear migration: split the monolithic `agents` table into three tables.

  - `agents` — thin universal identity (name, callname, type, role)
  - `local_agents` — inference/ReAct config (provider, model, timeouts, etc.)
  - `remote_agents` — A2A client config (URL, card, auth, status)

  All orchestration FKs (`swarm_members.agent_id`, `pipeline_stages.agent_id`, etc.)
  remain unchanged — they still reference `agents.id`.
  """

  use Ecto.Migration

  def change do
    # 1. Create agent_type enum
    execute(
      "CREATE TYPE agent_type AS ENUM ('local', 'remote')",
      "DROP TYPE IF EXISTS agent_type"
    )

    # 2. Add type and deleted_at to agents
    alter table(:agents) do
      add :type, :agent_type, default: "local", null: false
      add :deleted_at, :utc_datetime_usec
    end

    # 3. Create local_agents detail table
    create table(:local_agents, primary_key: false) do
      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :model, :string, null: false
      add :system_prompt, :text
      add :personality, :text
      add :max_steps, :integer, null: false, default: 10
      add :max_concurrent_invocations, :integer, null: false, default: 1
      add :max_delegation_concurrency, :integer, null: false, default: 3
      add :max_tokens_per_invocation, :integer, null: false, default: 50_000
      add :context_length, :integer
      add :step_timeout_s, :integer, null: false, default: 60
      add :total_timeout_s, :integer, null: false, default: 300
      add :stream_tokens_to_observability, :boolean, null: false, default: false
      add :budget_usd, :decimal, precision: 10, scale: 2

      add :provider_id, references(:providers, type: :binary_id, on_delete: :restrict),
        null: false

      add :media_provider_id,
          references(:media_providers, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:local_agents, [:provider_id])

    # 4. Create remote_agents detail table
    create table(:remote_agents, primary_key: false) do
      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :agent_card_url, :string, null: false
      add :cached_agent_card, :map
      add :auth_mode, :string, null: false, default: "none"
      add :card_refreshed_at, :utc_datetime_usec
      add :status, :string, null: false, default: "unknown"
      add :timeout_s, :integer, null: false, default: 300

      add :api_key_secret_id, references(:secrets, type: :binary_id, on_delete: :nilify_all)
    end

    # 5. Backfill: copy existing agent data into local_agents
    execute(
      """
      INSERT INTO local_agents (
        agent_id, model, system_prompt, personality,
        max_steps, max_concurrent_invocations, max_delegation_concurrency,
        max_tokens_per_invocation, context_length, step_timeout_s, total_timeout_s,
        stream_tokens_to_observability, budget_usd, provider_id, media_provider_id
      )
      SELECT
        id, model, system_prompt, personality,
        max_steps, max_concurrent_invocations, max_delegation_concurrency,
        max_tokens_per_invocation, context_length, step_timeout_s, total_timeout_s,
        stream_tokens_to_observability, budget_usd, provider_id, media_provider_id
      FROM agents
      """,
      """
      INSERT INTO agents (
        id, workspace_id, name, callname, role,
        model, system_prompt, personality,
        max_steps, max_concurrent_invocations, max_delegation_concurrency,
        max_tokens_per_invocation, context_length, step_timeout_s, total_timeout_s,
        stream_tokens_to_observability, budget_usd, provider_id, media_provider_id,
        inserted_at, updated_at
      )
      SELECT
        la.agent_id, a.workspace_id, a.name, a.callname, a.role,
        la.model, la.system_prompt, la.personality,
        la.max_steps, la.max_concurrent_invocations, la.max_delegation_concurrency,
        la.max_tokens_per_invocation, la.context_length, la.step_timeout_s, la.total_timeout_s,
        la.stream_tokens_to_observability, la.budget_usd, la.provider_id, la.media_provider_id,
        a.inserted_at, a.updated_at
      FROM local_agents la
      JOIN agents a ON a.id = la.agent_id
      """
    )

    # 6. Drop moved columns from agents
    alter table(:agents) do
      remove :model, :string
      remove :system_prompt, :text
      remove :personality, :text
      remove :max_steps, :integer
      remove :max_concurrent_invocations, :integer
      remove :max_delegation_concurrency, :integer
      remove :max_tokens_per_invocation, :integer
      remove :context_length, :integer
      remove :step_timeout_s, :integer
      remove :total_timeout_s, :integer
      remove :stream_tokens_to_observability, :boolean
      remove :budget_usd, :decimal
      remove :provider_id, references(:providers, type: :binary_id)
      remove :media_provider_id, references(:media_providers, type: :binary_id)
    end

    # 7. Replace callname unique index with partial (exclude soft-deleted)
    drop_if_exists unique_index(:agents, [:workspace_id, :callname])
    drop_if_exists index(:agents, [:provider_id])

    create unique_index(:agents, [:workspace_id, :callname],
             where: "deleted_at IS NULL",
             name: :agents_workspace_id_callname_active_index
           )
  end
end
