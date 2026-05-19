defmodule SummonerWeb.UserRegistrationController do
  use SummonerWeb, :controller

  alias Summoner.Adapters.Persistence.Accounts
  alias Summoner.Adapters.Persistence.Admin
  alias Summoner.Adapters.Persistence.Invitations
  alias Summoner.Adapters.Persistence.Tenants
  alias Summoner.Domain.Schemas.Invitation
  alias Summoner.Domain.Schemas.User

  def new(conn, params) do
    with {:ok, tenant} <- fetch_tenant(params),
         {:ok, mode} <- check_registration_mode(tenant) do
      changeset = Accounts.change_user_email(%User{})
      code = params["code"] || ""

      render(conn, :new,
        changeset: changeset,
        mode: mode,
        code: code,
        tenant: tenant
      )
    else
      {:error, :not_found} ->
        conn |> put_flash(:error, "Realm not found.") |> redirect(to: ~p"/users/log-in")

      {:error, :disabled} ->
        conn
        |> put_flash(:error, "Registration is currently disabled for this realm.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def create(conn, %{"user" => user_params} = params) do
    with {:ok, tenant} <- fetch_tenant(params),
         {:ok, mode} <- check_registration_mode(tenant) do
      case mode do
        :invitation -> create_with_invitation(conn, user_params, tenant)
        :open -> create_open(conn, user_params, tenant)
      end
    else
      {:error, :not_found} ->
        conn |> put_flash(:error, "Realm not found.") |> redirect(to: ~p"/users/log-in")

      {:error, :disabled} ->
        conn
        |> put_flash(:error, "Registration is currently disabled for this realm.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  defp fetch_tenant(%{"tenant_id" => id}) do
    case Tenants.get_tenant!(id) do
      tenant -> {:ok, tenant}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp check_registration_mode(tenant) do
    case tenant.settings.registration_mode do
      :disabled -> {:error, :disabled}
      mode -> {:ok, mode}
    end
  end

  defp create_open(conn, user_params, tenant) do
    if Admin.smtp_configured?() do
      register_with_email(conn, user_params, tenant)
    else
      register_with_password(conn, user_params, tenant)
    end
  end

  defp create_with_invitation(conn, user_params, tenant) do
    code = user_params["invitation_code"] || ""

    case Invitations.get_invitation_by_code(code) do
      nil ->
        render_invitation_error(conn, user_params, tenant, "Invalid invitation code.")

      invitation ->
        if Invitation.available?(invitation) and invitation.tenant_id == tenant.id do
          do_create_with_invitation(conn, user_params, tenant, invitation)
        else
          render_invitation_error(
            conn,
            user_params,
            tenant,
            "This invitation has expired, already been used, or is not valid for this realm."
          )
        end
    end
  end

  defp do_create_with_invitation(conn, user_params, tenant, invitation) do
    if Admin.smtp_configured?() do
      register_invited_with_email(conn, user_params, tenant, invitation)
    else
      register_invited_with_password(conn, user_params, tenant, invitation)
    end
  end

  defp register_with_email(conn, user_params, tenant) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        Tenants.add_member(tenant.id, user.id, :member)

        {:ok, _} =
          Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))

        conn
        |> put_flash(
          :info,
          "An email was sent to #{user.email}, please access it to confirm your account."
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset, mode: :open, code: "", tenant: tenant)
    end
  end

  defp register_with_password(conn, user_params, tenant) do
    password = user_params["password"] || ""

    case Accounts.register_user(user_params) do
      {:ok, user} ->
        Tenants.add_member(tenant.id, user.id, :member)
        confirm_and_set_password(conn, user, password)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset, mode: :open, code: "", tenant: tenant)
    end
  end

  defp register_invited_with_email(conn, user_params, tenant, invitation) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        Invitations.use_invitation(invitation.code, user)
        Tenants.add_member(tenant.id, user.id, :member)

        {:ok, _} =
          Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))

        conn
        |> put_flash(
          :info,
          "An email was sent to #{user.email}, please access it to confirm your account."
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new,
          changeset: changeset,
          mode: :invitation,
          code: user_params["invitation_code"] || "",
          tenant: tenant
        )
    end
  end

  defp register_invited_with_password(conn, user_params, tenant, invitation) do
    password = user_params["password"] || ""

    case Accounts.register_user(user_params) do
      {:ok, user} ->
        Invitations.use_invitation(invitation.code, user)
        Tenants.add_member(tenant.id, user.id, :member)
        confirm_and_set_password(conn, user, password)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new,
          changeset: changeset,
          mode: :invitation,
          code: user_params["invitation_code"] || "",
          tenant: tenant
        )
    end
  end

  defp confirm_and_set_password(conn, user, password) do
    with {:ok, user} <- set_password(user, password),
         {:ok, _user} <- confirm_user(user) do
      conn
      |> put_flash(:info, "Account created successfully. You can now log in.")
      |> redirect(to: ~p"/users/log-in")
    else
      {:error, _} ->
        conn
        |> put_flash(:error, "Account created but there was an error setting your password.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  defp set_password(user, password) do
    user
    |> User.password_changeset(%{password: password})
    |> Summoner.Repo.update()
  end

  defp confirm_user(user) do
    user
    |> User.confirm_changeset()
    |> Summoner.Repo.update()
  end

  defp render_invitation_error(conn, user_params, tenant, message) do
    changeset =
      %User{}
      |> Accounts.change_user_email(%{email: user_params["email"]})

    conn
    |> put_flash(:error, message)
    |> render(:new,
      changeset: changeset,
      mode: :invitation,
      code: user_params["invitation_code"] || "",
      tenant: tenant
    )
  end
end
