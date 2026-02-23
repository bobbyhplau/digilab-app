# Admin Authentication Design

**Goal:** Replace shared password admin login with per-user accounts, role-based permissions, and scene scoping.

**Scope:** Simple password-based auth for ~5 admin users. No OAuth, no cookies, no session persistence. Full Discord OAuth upgrade deferred to post-v1.0.

---

## Database

New `admin_users` table:

```sql
CREATE TABLE admin_users (
  user_id INTEGER PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  display_name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'scene_admin',  -- 'scene_admin' or 'super_admin'
  scene_id INTEGER,  -- NULL for super_admin, required for scene_admin
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

- Passwords hashed with `bcrypt` via the R `bcrypt` package
- `is_active` flag allows disabling admins without deletion
- `scene_id` enforces scene-level access for scene admins

---

## Authentication Flow

### Login

1. User clicks lock icon in header → login modal shows username + password fields
2. App queries `admin_users` by username where `is_active = TRUE`
3. Verifies password with `bcrypt::checkpw()`
4. On success: sets `rv$is_admin = TRUE`, `rv$is_superadmin` (based on role), and `rv$admin_user` (reactive list with user_id, username, display_name, role, scene_id)
5. On failure: shows "Invalid username or password" notification
6. Admin state lives in Shiny reactive values — lost on page refresh

### Bootstrap (First Launch)

1. On app start, if `admin_users` table is empty, set `rv$needs_bootstrap = TRUE`
2. Lock icon click shows "Create Super Admin" form: username, display name, password, confirm password
3. First account is always `super_admin` role with `scene_id = NULL`
4. After creation, normal login flow takes over

### Logout

Clears `rv$is_admin`, `rv$is_superadmin`, `rv$admin_user`. Returns to dashboard tab.

### Scene Scoping

- Scene admins: `rv$admin_user$scene_id` forces admin queries to their assigned scene. Scene selector hidden in admin context.
- Super admins: can switch scenes freely (current behavior preserved).

---

## Admin Management UI

**"Manage Admins" tab** — visible only to super admin in the admin sidebar.

### Components

- **Admin list table** (reactable): username, display name, role, assigned scene, active status
- **Add Admin form**: username, display name, password, role dropdown (scene_admin / super_admin), scene dropdown (visible only when role = scene_admin)
- **Edit/deactivate**: click row to edit display name, role, scene, or toggle active. Super admin cannot deactivate themselves.
- **No password reset**: if an admin forgets their password, super admin deactivates the old account and creates a new one.

---

## Migration

### Removed

- `ADMIN_PASSWORD` and `SUPERADMIN_PASSWORD` env vars — no longer read
- Single password input modal in `shared-server.R`
- References in `.env.example`

### Unchanged

- Lock icon in header (same `actionLink`, different modal content)
- `rv$is_admin` and `rv$is_superadmin` reactive flags (same names, set from DB user)
- Lazy-loaded admin modules in `app.R`
- `conditionalPanel` sidebar visibility logic
- Scene filtering in admin queries

### New

- `admin_users` table in `db/schema.sql`
- `bcrypt` package dependency
- `rv$admin_user` reactive value
- Bootstrap flow on first launch
- Manage Admins tab: `views/admin-users-ui.R` + `server/admin-users-server.R`

### Sync Workflow

1. Pull fresh DB: `python scripts/sync_from_motherduck.py --yes`
2. Run schema migration (add `admin_users` table)
3. Run app locally, create super admin via bootstrap form
4. Push back: `python scripts/sync_to_motherduck.py`

---

## Password Manager Compatibility

Login form inputs should include `autocomplete="username"` and `autocomplete="current-password"` attributes. Shiny's `textInput`/`passwordInput` may need custom HTML tags to include these. Since the app runs in an iframe on `digilab.cards`, credentials will be scoped to the Posit Connect origin — not ideal but functional. Users save credentials once manually if auto-detection doesn't trigger.

---

## Future Upgrade Path (Post-v1.0)

This design is a stepping stone. The full user accounts system (UA1-UA12) will:
- Replace password auth with Discord OAuth
- Add cookie-based session persistence
- Add admin invite links
- Add audit log table
- Add rate limiting

The `admin_users` table will be migrated to the full `users` table with Discord fields added. The role/scene_id columns carry over directly.
