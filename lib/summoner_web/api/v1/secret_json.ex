defmodule SummonerWeb.API.V1.SecretJSON do
  @moduledoc "JSON rendering for secrets. Values are never exposed."

  def index(%{secrets: secrets}) do
    %{data: Enum.map(secrets, &secret_data/1)}
  end

  def show(%{secret: secret}) do
    %{data: secret_data(secret)}
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
