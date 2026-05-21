defmodule SummonerWeb.API.V1.WebhookJSON do
  @moduledoc "JSON rendering for webhooks."

  import SummonerWeb.API.PaginationJSON

  def index(%{page: page}) do
    %{items: Enum.map(page.entries, &webhook_data/1), meta: page_meta(page)}
  end

  def show(%{webhook: webhook}) do
    webhook_data(webhook)
  end

  defp webhook_data(w) do
    %{
      id: w.id,
      name: w.name,
      description: w.description,
      target_type: w.target_type,
      target_id: w.target_id,
      auth_mode: w.auth_mode,
      hmac_secret_id: w.hmac_secret_id,
      transform: w.transform,
      response_mode: w.response_mode,
      rate_limit_rpm: w.rate_limit_rpm,
      timeout_s: w.timeout_s,
      enabled: w.enabled,
      last_triggered_at: w.last_triggered_at,
      trigger_count: w.trigger_count,
      workspace_id: w.workspace_id,
      inserted_at: w.inserted_at,
      updated_at: w.updated_at
    }
  end
end
