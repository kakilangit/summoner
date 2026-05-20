defmodule Summoner.Release do
  @moduledoc """
  Release tasks for Summoner.

  Used during deployment to run migrations and seed the admin user.

  ## Usage

      bin/summoner eval "Summoner.Release.migrate()"
      bin/summoner eval "Summoner.Release.seed_admin()"
  """

  @app :summoner

  @doc """
  Runs all pending Ecto migrations.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Creates the initial admin user from ADMIN_EMAIL and ADMIN_PASSWORD env vars.

  - Both env vars are required. Exits with error if missing.
  - If the admin user already exists, does nothing.
  - The admin user is created with role "admin" and confirmed immediately.
  """
  def seed_admin do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          do_seed_admin()
        end)
    end
  end

  defp do_seed_admin do
    alias Summoner.Adapters.Persistence.Accounts
    alias Summoner.Domain.Schemas.User
    alias Summoner.Repo

    email = fetch_env!("ADMIN_EMAIL")
    password = fetch_env!("ADMIN_PASSWORD")

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
  end

  defp fetch_env!(var) do
    case System.get_env(var) do
      nil ->
        IO.puts(
          :stderr,
          "[Summoner] ERROR: #{var} environment variable is required but not set."
        )

        System.halt(1)

      "" ->
        IO.puts(:stderr, "[Summoner] ERROR: #{var} environment variable is set but empty.")
        System.halt(1)

      value ->
        value
    end
  end

  defp load_app do
    Application.load(@app)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end
end
