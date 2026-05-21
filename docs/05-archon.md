# Archon (Admin Panel)

The **Archon** is the system administration panel, accessible only to users with the `admin` role. The root admin is determined by the `ADMIN_EMAIL` environment variable and is protected from demotion or disabling.

## Dashboard

The Archon dashboard (`/admin`) displays system-wide statistics:

- Total users
- Total guilds (tenants)
- Total realms (workspaces)
- Total summons (agents)
- Total invocations

## User Management

**Path:** `/admin/users`

| Action | Description |
|--------|-------------|
| List users | Paginated list of all users with email, role, and status |
| View user | User detail: email, role, creation date, confirmation status, workspace memberships |
| Change role | Set user role to `user` or `admin` |
| Disable user | Soft-disable (sets `disabled_at`), prevents login |
| Enable user | Re-enable a disabled user |
| Reset password | Generate a random 16-character password |
| Create user | Admin-created users bypass email confirmation |

The root admin (matching `ADMIN_EMAIL`) cannot be demoted or disabled.

**Password requirements:** 12-72 characters.

## Realm Management

**Path:** `/admin/workspaces`

| Action | Description |
|--------|-------------|
| List realms | All workspaces across all guilds with member counts |
| Delete realm | Permanently delete a workspace and all its data |

## Invitation Management

**Path:** `/admin/invites`

View all invitation codes across all guilds with their status (`available`, `used`, `expired`), creation date, and usage information.

## Quota Management

**Path:** `/admin/quotas`

Manage per-user, per-guild invitation quotas. Guild admins have unlimited invitation quota by default. Regular members are subject to configured limits (0-10,000 invitations).

## Invitations

Invitations are guild-scoped. Each invitation code:

- Is a 16-byte random URL-safe base64 string
- Expires after 30 days
- Can be used once to register a new user into the guild
- Is created by guild admins or members with available quota

**Registration flow:**

1. Guild admin creates an invitation code
2. Admin shares the code with the new user
3. New user navigates to `/tenants/:tenant_id/register`
4. User enters the invitation code, email, and password
5. User is registered and added to the guild as a member
