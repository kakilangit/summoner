# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Seed built-in themes
Summoner.Adapters.Persistence.Themes.seed_builtins()
IO.puts("[Summoner] Built-in themes seeded.")

# Seed the admin user from ADMIN_EMAIL and ADMIN_PASSWORD env vars.
# Both are required for first boot. Skips silently if admin already exists.

if System.get_env("ADMIN_EMAIL") && System.get_env("ADMIN_PASSWORD") do
  alias Summoner.Adapters.Persistence.Accounts
  alias Summoner.Domain.Schemas.User
  alias Summoner.Repo

  email = System.get_env("ADMIN_EMAIL")
  password = System.get_env("ADMIN_PASSWORD")

  case Accounts.get_user_by_email(email) do
    %User{} = _existing ->
      IO.puts("[Summoner] Admin user already exists: #{email}")

    nil ->
      {:ok, user} = Accounts.register_user(%{email: email})

      user
      |> User.password_changeset(%{password: password})
      |> Repo.update!()

      Repo.get!(User, user.id)
      |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(), role: "admin")
      |> Repo.update!()

      IO.puts("[Summoner] Admin user created: #{email}")
  end
else
  IO.puts("[Summoner] ADMIN_EMAIL/ADMIN_PASSWORD not set, skipping admin seed.")
end
