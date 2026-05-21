defmodule SummonerWeb.API.ApiSpec do
  @moduledoc "OpenAPI 3.1 specification for the Summoner REST API."

  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server}
  alias SummonerWeb.{Endpoint, Router}

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [Server.from_endpoint(Endpoint)],
      info: %Info{
        title: "Summoner API",
        version: to_string(Application.spec(:summoner, :vsn)),
        description: "REST API for the Summoner multi-agent AI platform."
      },
      paths: Paths.from_router(Router),
      components: %Components{
        securitySchemes: %{
          "bearer" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "Ward token (shk_...)",
            description: "Ward (access token) with appropriate scopes."
          }
        }
      },
      security: [%{"bearer" => []}]
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
