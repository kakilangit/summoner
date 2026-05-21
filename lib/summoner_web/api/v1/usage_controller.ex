defmodule SummonerWeb.API.V1.UsageController do
  @moduledoc "REST API controller for usage analytics."

  use SummonerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Summoner.Ports.Persistence.Ledger
  alias SummonerWeb.API.Schemas

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  tags ["usage"]

  operation :index,
    summary: "Get usage summary",
    description: "Rolling 30-day token usage and cost.",
    responses: [ok: {"Usage", "application/json", Schemas.UsageResponse}]

  operation :breakdowns,
    summary: "Get usage breakdowns",
    description: "Usage broken down by agent, model, and provider.",
    responses: [ok: {"Breakdowns", "application/json", Schemas.UsageBreakdownResponse}]

  def index(conn, _params) do
    workspace_id = conn.assigns.current_workspace_id

    usage = %{
      rolling_30_day_tokens: Ledger.rolling_30_day_usage(workspace_id),
      rolling_30_day_cost: Ledger.rolling_30_day_cost(workspace_id)
    }

    render(conn, :index, usage: usage)
  end

  def breakdowns(conn, _params) do
    workspace_id = conn.assigns.current_workspace_id

    breakdowns = %{
      by_agent: Ledger.usage_by_agent(workspace_id),
      by_model: Ledger.usage_by_model(workspace_id),
      by_provider: Ledger.usage_by_provider(workspace_id)
    }

    render(conn, :breakdowns, breakdowns: breakdowns)
  end
end
