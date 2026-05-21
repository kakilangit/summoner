defmodule SummonerWeb.API.V1.SecretJSON do
  @moduledoc "JSON rendering for secrets. Values are never exposed."

  import SummonerWeb.API.PaginationJSON

  def index(%{page: page}) do
    %{items: Enum.map(page.entries, &secret_data/1), meta: page_meta(page)}
  end

  def show(%{secret: secret}) do
    secret_data(secret)
  end

  defp secret_data(s) do
    %{
      id: s.id,
      name: s.name,
      description: s.description,
      workspace_id: s.workspace_id,
      tenant_id: s.tenant_id,
      inserted_at: s.inserted_at,
      updated_at: s.updated_at
    }
  end
end
