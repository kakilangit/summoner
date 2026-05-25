defmodule Summoner.Domain.Schemas.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Summoner.Domain.Schemas.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use as authorization, or to
  ensure specific code paths can only be access for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Summoner.Domain.Policies.SystemPolicy
  alias Summoner.Domain.Schemas.User

  defstruct user: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc """
  Returns true if the scope's user is the root admin (email matches ROOT_ADMIN_EMAIL env var).
  """
  def root_admin?(%__MODULE__{user: %User{email: email}}) do
    SystemPolicy.root_admin?(%{email: email})
  end

  def root_admin?(_), do: false

  @doc """
  Returns true if the scope's user has any system-level permissions.
  """
  def system_admin?(%__MODULE__{user: %User{} = user}) do
    SystemPolicy.system_admin?(user)
  end

  def system_admin?(_), do: false

  @doc """
  Returns true if the scope's user has the admin role.

  **DEPRECATED**: Use `system_admin?/1` or specific permission checks via `SystemPolicy.can?/2`.
  This method checks the legacy `user.role == "admin"` field and will be removed in v0.3.0.
  """
  def admin?(%__MODULE__{user: %User{role: "admin"}}), do: true
  def admin?(_), do: false
end
