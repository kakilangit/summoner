defmodule Summoner.Domain.Policies.UnauthorizedError do
  @moduledoc """
  Raised when a user attempts an action they don't have permission for.
  """

  defexception [:action, :role, :message]

  @impl true
  def exception(opts) do
    action = Keyword.get(opts, :action)
    role = Keyword.get(opts, :role)
    msg = "Unauthorized: role #{inspect(role)} cannot perform #{inspect(action)}"
    %__MODULE__{action: action, role: role, message: msg}
  end
end
