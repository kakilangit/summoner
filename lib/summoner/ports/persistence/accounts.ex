defmodule Summoner.Ports.Persistence.Accounts do
  @moduledoc "Port for accounts persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :accounts],
             Summoner.Adapters.Persistence.Accounts
           )

  # Database getters
  defdelegate get_user_by_email(email), to: @adapter
  defdelegate get_user_by_email_and_password(email, password), to: @adapter
  defdelegate get_user!(id), to: @adapter

  # Registration
  defdelegate register_user(attrs), to: @adapter

  # Settings
  defdelegate sudo_mode?(user), to: @adapter
  defdelegate sudo_mode?(user, minutes), to: @adapter
  defdelegate change_user_email(user), to: @adapter
  defdelegate change_user_email(user, attrs), to: @adapter
  defdelegate change_user_email(user, attrs, opts), to: @adapter
  defdelegate update_user_email(user, token), to: @adapter
  defdelegate change_user_password(user), to: @adapter
  defdelegate change_user_password(user, attrs), to: @adapter
  defdelegate change_user_password(user, attrs, opts), to: @adapter
  defdelegate update_user_password(user, attrs), to: @adapter

  # Session
  defdelegate generate_user_session_token(user), to: @adapter
  defdelegate get_user_by_session_token(token), to: @adapter
  defdelegate get_user_by_magic_link_token(token), to: @adapter
  defdelegate login_user_by_magic_link(token), to: @adapter

  # Email delivery
  defdelegate deliver_user_update_email_instructions(user, current_email, update_email_url_fun),
    to: @adapter

  defdelegate deliver_login_instructions(user, magic_link_url_fun), to: @adapter

  # Session cleanup
  defdelegate delete_user_session_token(token), to: @adapter

  # Registration helpers
  defdelegate set_user_password(user, password), to: @adapter
  defdelegate confirm_user(user), to: @adapter

  # Theme
  defdelegate update_user_theme(user, theme_name), to: @adapter
end
