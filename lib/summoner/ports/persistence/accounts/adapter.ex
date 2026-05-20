defmodule Summoner.Ports.Persistence.Accounts.Adapter do
  @moduledoc "Behaviour for accounts persistence operations."

  # Database getters
  @callback get_user_by_email(String.t()) :: struct() | nil
  @callback get_user_by_email_and_password(String.t(), String.t()) :: struct() | nil
  @callback get_user!(String.t()) :: struct()

  # Registration
  @callback register_user(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}

  # Settings
  @callback sudo_mode?(struct()) :: boolean()
  @callback sudo_mode?(struct(), integer()) :: boolean()
  @callback change_user_email(struct()) :: Ecto.Changeset.t()
  @callback change_user_email(struct(), map()) :: Ecto.Changeset.t()
  @callback change_user_email(struct(), map(), keyword()) :: Ecto.Changeset.t()
  @callback update_user_email(struct(), String.t()) ::
              {:ok, struct()} | {:error, term()}
  @callback change_user_password(struct()) :: Ecto.Changeset.t()
  @callback change_user_password(struct(), map()) :: Ecto.Changeset.t()
  @callback change_user_password(struct(), map(), keyword()) :: Ecto.Changeset.t()
  @callback update_user_password(struct(), map()) ::
              {:ok, {struct(), [struct()]}} | {:error, Ecto.Changeset.t()}

  # Session
  @callback generate_user_session_token(struct()) :: binary()
  @callback get_user_by_session_token(binary()) :: {struct(), DateTime.t()} | nil
  @callback get_user_by_magic_link_token(String.t()) :: struct() | nil
  @callback login_user_by_magic_link(String.t()) ::
              {:ok, {struct(), [struct()]}} | {:error, term()}

  # Email delivery
  @callback deliver_user_update_email_instructions(struct(), String.t(), function()) ::
              {:ok, term()}
  @callback deliver_login_instructions(struct(), function()) :: {:ok, term()}

  # Session cleanup
  @callback delete_user_session_token(binary()) :: :ok

  # Registration helpers
  @callback set_user_password(struct(), String.t()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback confirm_user(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}

  # Theme
  @callback update_user_theme(struct(), String.t()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
end
