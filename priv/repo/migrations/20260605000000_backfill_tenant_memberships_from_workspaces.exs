defmodule Summoner.Repo.Migrations.BackfillTenantMembershipsFromWorkspaces do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO tenant_memberships (id, user_id, tenant_id, role, inserted_at, updated_at)
    SELECT gen_random_uuid(), wm.user_id, w.tenant_id, 'member', now(), now()
    FROM workspace_memberships wm
    JOIN workspaces w ON w.id = wm.workspace_id
    WHERE NOT EXISTS (
      SELECT 1 FROM tenant_memberships tm
      WHERE tm.user_id = wm.user_id AND tm.tenant_id = w.tenant_id
    )
    GROUP BY wm.user_id, w.tenant_id
    """)
  end

  def down do
    # No rollback — we can't distinguish auto-created from manually created memberships
    :ok
  end
end
