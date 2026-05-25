defmodule Summoner.Repo.Migrations.AddSystemPermissionsAndOwnerRoles do
  use Ecto.Migration
  @disable_ddl_transaction true

  def up do
    # Create system_permissions table
    create table(:system_permissions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :permission, :text, null: false

      timestamps()
    end

    create unique_index(:system_permissions, [:user_id, :permission])
    create index(:system_permissions, [:user_id])

    # Add check constraint for permission values
    execute("""
    ALTER TABLE system_permissions
    ADD CONSTRAINT system_permissions_permission_check
    CHECK (permission IN ('manage_users', 'manage_tenants', 'manage_system_settings', 'view_system_stats'))
    """)

    # Update tenant_memberships role enum
    execute("ALTER TABLE tenant_memberships ALTER COLUMN role DROP DEFAULT")

    execute(
      "ALTER TABLE tenant_memberships DROP CONSTRAINT IF EXISTS tenant_memberships_role_check"
    )

    execute("""
    ALTER TABLE tenant_memberships
    ADD CONSTRAINT tenant_memberships_role_check
    CHECK (role IN ('owner', 'admin', 'member'))
    """)

    execute("ALTER TABLE tenant_memberships ALTER COLUMN role SET DEFAULT 'member'")

    # Update workspace_memberships role enum
    execute("ALTER TABLE workspace_memberships ALTER COLUMN role DROP DEFAULT")

    execute(
      "ALTER TABLE workspace_memberships DROP CONSTRAINT IF EXISTS workspace_memberships_role_check"
    )

    execute("""
    ALTER TABLE workspace_memberships
    ADD CONSTRAINT workspace_memberships_role_check
    CHECK (role IN ('owner', 'admin', 'member', 'viewer'))
    """)

    execute("ALTER TABLE workspace_memberships ALTER COLUMN role SET DEFAULT 'member'")

    # Promote first tenant member to owner for each tenant
    execute("""
    UPDATE tenant_memberships
    SET role = 'owner'
    WHERE id IN (
      SELECT DISTINCT ON (tenant_id) id
      FROM tenant_memberships
      ORDER BY tenant_id, inserted_at ASC
    )
    """)

    # Promote first workspace member to owner for each workspace
    execute("""
    UPDATE workspace_memberships
    SET role = 'owner'
    WHERE id IN (
      SELECT DISTINCT ON (workspace_id) id
      FROM workspace_memberships
      ORDER BY workspace_id, inserted_at ASC
    )
    """)
  end

  def down do
    drop table(:system_permissions)

    # Revert tenant_memberships role enum
    execute("ALTER TABLE tenant_memberships ALTER COLUMN role DROP DEFAULT")

    execute(
      "ALTER TABLE tenant_memberships DROP CONSTRAINT IF EXISTS tenant_memberships_role_check"
    )

    execute("""
    ALTER TABLE tenant_memberships
    ADD CONSTRAINT tenant_memberships_role_check
    CHECK (role IN ('admin', 'member'))
    """)

    execute("ALTER TABLE tenant_memberships ALTER COLUMN role SET DEFAULT 'member'")

    # Revert workspace_memberships role enum
    execute("ALTER TABLE workspace_memberships ALTER COLUMN role DROP DEFAULT")

    execute(
      "ALTER TABLE workspace_memberships DROP CONSTRAINT IF EXISTS workspace_memberships_role_check"
    )

    execute("""
    ALTER TABLE workspace_memberships
    ADD CONSTRAINT workspace_memberships_role_check
    CHECK (role IN ('admin', 'member', 'viewer'))
    """)

    execute("ALTER TABLE workspace_memberships ALTER COLUMN role SET DEFAULT 'member'")
  end
end
