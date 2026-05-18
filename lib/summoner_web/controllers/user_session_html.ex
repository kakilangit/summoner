defmodule SummonerWeb.UserSessionHTML do
  use SummonerWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:summoner, Summoner.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
