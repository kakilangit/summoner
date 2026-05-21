defmodule SummonerWeb.OpenAI.ModelsController do
  @moduledoc """
  OpenAI-compatible `GET /v1/models` endpoint.

  Lists available agents and raw provider models in OpenAI model object format.
  """

  use SummonerWeb, :controller

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"

  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Providers

  @doc """
  GET /v1/models

  Returns all agents as `summoner:<callname>` and all provider models
  as `summoner:raw:<provider>/<model>` in OpenAI model list format.
  """
  def index(conn, _params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id

    agent_models = list_agent_models(scope, workspace_id)
    raw_models = list_raw_models(scope, workspace_id, tenant_id)

    json(conn, %{
      "object" => "list",
      "data" => agent_models ++ raw_models
    })
  end

  defp list_agent_models(scope, workspace_id) do
    scope
    |> Agents.list_agents(workspace_id)
    |> Enum.map(fn agent ->
      %{
        "id" => "summoner:#{agent.callname}",
        "object" => "model",
        "created" => to_unix(agent.inserted_at),
        "owned_by" => "summoner"
      }
    end)
  end

  defp list_raw_models(scope, workspace_id, tenant_id) do
    scope
    |> Providers.list_providers(workspace_id, tenant_id)
    |> Enum.flat_map(fn provider ->
      provider_name = String.downcase(provider.name)
      models = provider.cached_models || []

      Enum.map(models, fn model_name ->
        %{
          "id" => "summoner:raw:#{provider_name}/#{model_name}",
          "object" => "model",
          "created" => to_unix(provider.inserted_at),
          "owned_by" => provider_name
        }
      end)
    end)
  end

  defp to_unix(%DateTime{} = dt), do: DateTime.to_unix(dt)

  defp to_unix(%NaiveDateTime{} = ndt),
    do: ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

  defp to_unix(_), do: 0
end
