defmodule Summoner.Workers.CopilotPoller do
  @moduledoc """
  Oban worker that polls GitHub for a Copilot OAuth token after
  the user initiates a device code flow.

  On success, creates (or updates) a Seal with the OAuth token and
  links it to the provider via `api_key_secret_id`. Broadcasts the
  result to the provider topic so the LiveView can react.

  ## Args

      %{
        "provider_id"   => binary,
        "workspace_id"  => binary,
        "device_code"   => binary,
        "interval"      => integer,
        "attempt"       => integer  # 1-based, injected on re-enqueue
      }

  Max 60 attempts (matching Arcanum's polling limit). Each attempt
  is a single Oban job — no `Process.sleep` blocking.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1

  alias Arcanum.Auth.Copilot, as: CopilotAuth
  alias Summoner.Broadcasts
  alias Summoner.Providers
  alias Summoner.Providers.Provider
  alias Summoner.Repo
  alias Summoner.Secrets

  require Logger

  @max_attempts 60
  @seal_name_prefix "COPILOT_TOKEN"

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "provider_id" => provider_id,
            "workspace_id" => workspace_id,
            "device_code" => device_code,
            "interval" => interval,
            "attempt" => attempt
          } = args
      }) do
    if attempt > @max_attempts do
      broadcast_result(workspace_id, provider_id, {:error, :polling_timeout})
      {:cancel, "Exceeded max polling attempts"}
    else
      poll_once(args, workspace_id, provider_id, device_code, interval, attempt)
    end
  end

  # -------------------------------------------------------------------
  # Polling
  # -------------------------------------------------------------------

  defp poll_once(args, workspace_id, provider_id, device_code, interval, attempt) do
    Logger.info("Copilot poll attempt #{attempt} for provider #{provider_id}")

    case CopilotAuth.poll_once(device_code) do
      {:ok, token} ->
        handle_token(workspace_id, provider_id, token)

      {:pending, :slow_down} ->
        # RFC 8628: add 5 seconds on slow_down
        schedule_next(args, interval + 5, attempt)

      {:pending, :authorization_pending} ->
        schedule_next(args, interval, attempt)

      {:error, :device_code_expired} ->
        broadcast_result(workspace_id, provider_id, {:error, :expired})
        {:cancel, "Device code expired"}

      {:error, :access_denied} ->
        broadcast_result(workspace_id, provider_id, {:error, :denied})
        {:cancel, "User denied access"}

      {:error, reason} ->
        Logger.warning("Copilot poll attempt #{attempt} failed: #{inspect(reason)}")
        schedule_next(args, interval, attempt)
    end
  end

  defp schedule_next(args, interval, attempt) do
    delay = interval + 3
    Logger.info("Copilot scheduling next poll (attempt #{attempt + 1}) in #{delay}s")

    args
    |> Map.put("attempt", attempt + 1)
    |> __MODULE__.new(schedule_in: delay)
    |> Oban.insert()

    :ok
  end

  # -------------------------------------------------------------------
  # Token persistence
  # -------------------------------------------------------------------

  defp handle_token(workspace_id, provider_id, token) do
    Repo.transaction(fn ->
      seal_name = seal_name(provider_id)

      secret =
        case upsert_seal(workspace_id, seal_name, token) do
          {:ok, secret} -> secret
          {:error, reason} -> Repo.rollback(reason)
        end

      case link_seal_to_provider(provider_id, secret.id) do
        {:ok, _provider} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, :ok} ->
        broadcast_result(workspace_id, provider_id, :ok)
        :ok

      {:error, reason} ->
        Logger.error("Failed to persist Copilot token: #{inspect(reason)}")
        broadcast_result(workspace_id, provider_id, {:error, :persistence_failed})
        {:error, reason}
    end
  end

  defp upsert_seal(workspace_id, name, value) do
    import Ecto.Query, warn: false

    case Repo.get_by(Summoner.Secrets.Secret,
           workspace_id: workspace_id,
           name: name
         ) do
      nil ->
        Secrets.create_secret(%{user: nil}, %{
          workspace_id: workspace_id,
          name: name,
          encrypted_value: value,
          description: "Auto-created by Copilot device code flow"
        })

      existing ->
        Secrets.update_secret(%{user: nil}, existing, %{encrypted_value: value})
    end
  end

  defp link_seal_to_provider(provider_id, secret_id) do
    provider = Repo.get!(Provider, provider_id) |> Repo.preload(:api_key_secret)
    Providers.update_provider(%{user: nil}, provider, %{api_key_secret_id: secret_id})
  end

  defp seal_name(provider_id) do
    # Take last 8 chars of NULID for uniqueness
    suffix = provider_id |> String.slice(-8, 8) |> String.upcase()
    "#{@seal_name_prefix}_#{suffix}"
  end

  # -------------------------------------------------------------------
  # PubSub
  # -------------------------------------------------------------------

  defp broadcast_result(workspace_id, provider_id, result) do
    Broadcasts.broadcast(
      Broadcasts.provider_topic(workspace_id, provider_id),
      {:copilot_connect, result}
    )
  end
end
