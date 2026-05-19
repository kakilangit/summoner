defmodule Summoner.Domain.Types.Features do
  @moduledoc """
  Feature flags for the application.

  Provides a clean interface to check runtime feature toggles
  without leaking Application.get_env calls across the codebase.
  """

  @doc """
  Returns `true` when the application runs in local mode (desktop/dev).

  In local mode, features like "Open in file manager" are available.
  Controlled by the `LOCAL_MODE` environment variable.
  """
  @spec local_mode?() :: boolean()
  def local_mode?, do: Application.get_env(:summoner, :local_mode, false)
end
