# Admin Authentication Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace shared password admin login with per-user accounts (bcrypt), role-based permissions, scene scoping, and a Manage Admins UI.

**Architecture:** New `admin_users` table in DuckDB with bcrypt password hashes. Login via username/password form in the existing lock icon modal. Bootstrap flow creates first super admin when table is empty. Scene admins are locked to their assigned scene. Super admin gets a "Manage Admins" tab to CRUD admin accounts.

**Tech Stack:** R Shiny, DuckDB, bcrypt (R package), bslib, reactable

**Design Doc:** `docs/plans/2026-02-22-admin-auth-design.md`

---

## Pre-Implementation: Database Sync

Before any code changes, sync fresh data from MotherDuck:

```bash
python scripts/sync_from_motherduck.py --yes
```

This ensures your local DuckDB has the latest production data before adding the new table.

---

### Task 1: Add `admin_users` Table to Schema

**Files:**
- Modify: `db/schema.sql` (append new table after `limitless_sync_state`, before views section ~line 366)

**Step 1: Add the table definition to schema.sql**

Add after the `limitless_sync_state` table and before the `-- VIEWS FOR COMMON QUERIES` section:

```sql
-- =============================================================================
-- ADMIN USERS TABLE
-- Per-user admin accounts with bcrypt password hashes and role-based access
-- Replaces shared ADMIN_PASSWORD/SUPERADMIN_PASSWORD env vars
-- =============================================================================
CREATE TABLE IF NOT EXISTS admin_users (
    user_id INTEGER PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    display_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'scene_admin',
    scene_id INTEGER,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_admin_users_username ON admin_users(username);
```

**Step 2: Create the table in local database**

Run from R console:

```r
source("R/db_connection.R")
con <- connect_db()
DBI::dbExecute(con, "CREATE TABLE IF NOT EXISTS admin_users (
    user_id INTEGER PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    display_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'scene_admin',
    scene_id INTEGER,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)")
DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_admin_users_username ON admin_users(username)")
DBI::dbListTables(con)  # Verify admin_users appears
DBI::dbDisconnect(con, shutdown = TRUE)
```

Expected: Table created, shows in table list.

**Step 3: Commit**

```bash
git add db/schema.sql
git commit -m "schema: add admin_users table for per-user admin accounts"
```

---

### Task 2: Install bcrypt and Add to Dependencies

**Files:**
- Modify: `app.R` (add `library(bcrypt)` near top where other packages are loaded, ~line 1-30)

**Step 1: Install bcrypt**

```r
install.packages("bcrypt")
```

**Step 2: Add bcrypt to app.R imports**

Find the section in `app.R` where packages are loaded (near the top). Add:

```r
library(bcrypt)
```

Place it near the other library calls. If `app.R` uses `library()` calls at the top, add it there. If it uses a different pattern (like loading via `_brand.yml` or `bslib`), follow the existing pattern.

Note: `app.R` currently loads packages implicitly via `bslib`, `shiny`, etc. Check the actual top of the file. The `bcrypt` library needs to be available in the server scope.

**Step 3: Verify bcrypt works**

```r
library(bcrypt)
hash <- hashpw("testpassword")
checkpw("testpassword", hash)  # Should return TRUE
checkpw("wrongpassword", hash) # Should return FALSE
```

**Step 4: Commit**

```bash
git add app.R
git commit -m "deps: add bcrypt package for admin password hashing"
```

---

### Task 3: Add `rv$admin_user` Reactive and Bootstrap Flag

**Files:**
- Modify: `app.R` — reactive values section (~lines 912-968)

**Step 1: Add new reactive values**

In the `rv <- reactiveValues(...)` block in `app.R` (around line 913), add to the `# === CORE ===` section:

```r
    # === CORE ===
    db_con = NULL,
    is_admin = FALSE,
    is_superadmin = FALSE,
    admin_user = NULL,          # List: user_id, username, display_name, role, scene_id
    needs_bootstrap = FALSE,    # TRUE when admin_users table is empty
```

**Step 2: Remove old password env vars**

In `app.R` (~lines 330-341), remove the `ADMIN_PASSWORD` and `SUPERADMIN_PASSWORD` blocks entirely:

```r
# DELETE these lines (330-341):
# Admin password - MUST be set via environment variable
ADMIN_PASSWORD <- Sys.getenv("ADMIN_PASSWORD")
if (ADMIN_PASSWORD == "") {
  warning("ADMIN_PASSWORD environment variable not set - admin login disabled")
  ADMIN_PASSWORD <- NULL
}

# Super admin password - optional, grants access to Edit Stores and Edit Formats
SUPERADMIN_PASSWORD <- Sys.getenv("SUPERADMIN_PASSWORD")
if (SUPERADMIN_PASSWORD == "") {
  SUPERADMIN_PASSWORD <- NULL
}
```

**Step 3: Commit**

```bash
git add app.R
git commit -m "refactor: add admin_user reactive, remove shared password env vars"
```

---

### Task 4: Implement Bootstrap Check on App Startup

**Files:**
- Modify: `server/shared-server.R` — add bootstrap check after DB connection is established

**Step 1: Find where DB connection is set**

Look in `shared-server.R` for where `rv$db_con` is first assigned (the database connection initialization). Add a bootstrap check right after:

```r
# Check if admin_users table needs bootstrap (first-ever setup)
admin_count <- safe_query(rv$db_con,
  "SELECT COUNT(*) as n FROM admin_users",
  default = data.frame(n = 0))
if (nrow(admin_count) > 0 && admin_count$n[1] == 0) {
  rv$needs_bootstrap <- TRUE
}
```

This sets the flag that the login modal will check.

**Step 2: Commit**

```bash
git add server/shared-server.R
git commit -m "feat: add bootstrap check for empty admin_users table on startup"
```

---

### Task 5: Rewrite Login Modal (Bootstrap + Normal Login)

**Files:**
- Modify: `server/shared-server.R` — replace the login modal handler (~lines 334-400) and login handler (~lines 403-424)

**Step 1: Replace the login modal observer**

Replace the `observeEvent(input$admin_login_link, { ... })` block (~lines 334-400) with:

```r
observeEvent(input$admin_login_link, {
  if (rv$is_admin) {
    # Already logged in - show admin nav + logout
    role_label <- if (rv$is_superadmin) "super admin" else "scene admin"
    admin_name <- rv$admin_user$display_name

    # Build admin nav links
    admin_links <- tagList(
      actionLink("modal_admin_results",
                 tagList(bsicons::bs_icon("pencil-square"), " Enter Results"),
                 class = "admin-modal-link"),
      actionLink("modal_admin_tournaments",
                 tagList(bsicons::bs_icon("trophy"), " Edit Tournaments"),
                 class = "admin-modal-link"),
      actionLink("modal_admin_players",
                 tagList(bsicons::bs_icon("people"), " Edit Players"),
                 class = "admin-modal-link"),
      actionLink("modal_admin_decks",
                 tagList(bsicons::bs_icon("collection"), " Edit Decks"),
                 class = "admin-modal-link")
    )

    # Add super admin links if applicable
    superadmin_links <- NULL
    if (rv$is_superadmin) {
      superadmin_links <- tagList(
        tags$hr(class = "my-2"),
        tags$div(class = "admin-modal-section", "Super Admin"),
        actionLink("modal_admin_stores",
                   tagList(bsicons::bs_icon("shop"), " Edit Stores"),
                   class = "admin-modal-link"),
        actionLink("modal_admin_formats",
                   tagList(bsicons::bs_icon("calendar3"), " Edit Formats"),
                   class = "admin-modal-link"),
        actionLink("modal_admin_users",
                   tagList(bsicons::bs_icon("person-gear"), " Manage Admins"),
                   class = "admin-modal-link")
      )
    }

    showModal(modalDialog(
      title = paste0(admin_name, " (", role_label, ")"),
      div(
        class = "admin-modal-nav",
        admin_links,
        superadmin_links
      ),
      footer = tagList(
        actionButton("logout_btn", "Logout", class = "btn-warning"),
        modalButton("Close")
      )
    ))
  } else if (rv$needs_bootstrap) {
    # First-time setup - create super admin
    showModal(modalDialog(
      title = "Create Super Admin",
      tags$p(class = "text-muted", "No admin accounts exist yet. Create the first super admin account."),
      textInput("bootstrap_username", "Username", placeholder = "e.g., michael"),
      textInput("bootstrap_display_name", "Display Name", placeholder = "e.g., Michael"),
      tags$div(
        passwordInput("bootstrap_password", "Password"),
        style = "margin-bottom: 0.5rem;"
      ),
      passwordInput("bootstrap_confirm", "Confirm Password"),
      footer = tagList(
        actionButton("bootstrap_btn", "Create Account", class = "btn-primary"),
        modalButton("Cancel")
      )
    ))
  } else {
    # Normal login form
    showModal(modalDialog(
      title = "Admin Login",
      textInput("login_username", "Username"),
      passwordInput("login_password", "Password"),
      footer = tagList(
        actionButton("login_btn", "Login", class = "btn-primary"),
        modalButton("Cancel")
      )
    ))
  }
})
```

**Step 2: Replace the login handler**

Replace the `observeEvent(input$login_btn, { ... })` block (~lines 403-424) with:

```r
# Handle login
observeEvent(input$login_btn, {
  username <- trimws(input$login_username)
  password <- input$login_password

  if (nchar(username) == 0 || nchar(password) == 0) {
    notify("Please enter username and password", type = "warning")
    return()
  }

  # Look up user
  user <- safe_query(rv$db_con,
    "SELECT user_id, username, password_hash, display_name, role, scene_id
     FROM admin_users WHERE username = ? AND is_active = TRUE",
    params = list(username),
    default = data.frame())

  if (nrow(user) == 0) {
    notify("Invalid username or password", type = "error")
    return()
  }

  # Verify password
  if (!bcrypt::checkpw(password, user$password_hash[1])) {
    notify("Invalid username or password", type = "error")
    return()
  }

  # Success - set reactive state
  rv$is_admin <- TRUE
  rv$is_superadmin <- (user$role[1] == "super_admin")
  rv$admin_user <- list(
    user_id = user$user_id[1],
    username = user$username[1],
    display_name = user$display_name[1],
    role = user$role[1],
    scene_id = if (is.na(user$scene_id[1])) NULL else user$scene_id[1]
  )

  removeModal()
  notify(paste0("Welcome, ", user$display_name[1], "!"), type = "message")

  # Force scene for scene admins
  if (rv$admin_user$role == "scene_admin" && !is.null(rv$admin_user$scene_id)) {
    scene_slug <- safe_query(rv$db_con,
      "SELECT slug FROM scenes WHERE scene_id = ?",
      params = list(rv$admin_user$scene_id),
      default = data.frame())
    if (nrow(scene_slug) > 0) {
      updateSelectInput(session, "scene_selector", selected = scene_slug$slug[1])
    }
  }

  # Update dropdowns with data
  updateSelectInput(session, "tournament_store",
                    choices = get_store_choices(rv$db_con, include_none = TRUE))
})
```

**Step 3: Add bootstrap handler**

Add a new observer right after the login handler:

```r
# Handle bootstrap (first super admin creation)
observeEvent(input$bootstrap_btn, {
  username <- trimws(input$bootstrap_username)
  display_name <- trimws(input$bootstrap_display_name)
  password <- input$bootstrap_password
  confirm <- input$bootstrap_confirm

  # Validation
  if (nchar(username) < 3) {
    notify("Username must be at least 3 characters", type = "warning")
    return()
  }
  if (nchar(display_name) == 0) {
    notify("Display name is required", type = "warning")
    return()
  }
  if (nchar(password) < 8) {
    notify("Password must be at least 8 characters", type = "warning")
    return()
  }
  if (password != confirm) {
    notify("Passwords do not match", type = "error")
    return()
  }

  # Double-check table is still empty (prevent race condition)
  admin_count <- safe_query(rv$db_con,
    "SELECT COUNT(*) as n FROM admin_users",
    default = data.frame(n = 0))
  if (admin_count$n[1] > 0) {
    rv$needs_bootstrap <- FALSE
    notify("Admin accounts already exist. Please log in.", type = "warning")
    removeModal()
    return()
  }

  # Create super admin
  hash <- bcrypt::hashpw(password)
  # Get next user_id
  max_id <- safe_query(rv$db_con,
    "SELECT COALESCE(MAX(user_id), 0) as max_id FROM admin_users",
    default = data.frame(max_id = 0))
  new_id <- max_id$max_id[1] + 1

  result <- safe_execute(rv$db_con,
    "INSERT INTO admin_users (user_id, username, password_hash, display_name, role, scene_id)
     VALUES (?, ?, ?, ?, 'super_admin', NULL)",
    params = list(new_id, username, hash, display_name))

  if (result > 0) {
    rv$needs_bootstrap <- FALSE
    rv$is_admin <- TRUE
    rv$is_superadmin <- TRUE
    rv$admin_user <- list(
      user_id = new_id,
      username = username,
      display_name = display_name,
      role = "super_admin",
      scene_id = NULL
    )
    removeModal()
    notify(paste0("Super admin account created. Welcome, ", display_name, "!"), type = "message")

    # Update dropdowns with data
    updateSelectInput(session, "tournament_store",
                      choices = get_store_choices(rv$db_con, include_none = TRUE))
  } else {
    notify("Failed to create account. Please try again.", type = "error")
  }
})
```

**Step 4: Update logout handler**

Replace the `observeEvent(input$logout_btn, { ... })` block (~lines 427-436) with:

```r
# Handle logout
observeEvent(input$logout_btn, {
  rv$is_admin <- FALSE
  rv$is_superadmin <- FALSE
  rv$admin_user <- NULL
  rv$active_tournament_id <- NULL
  removeModal()
  notify("Logged out", type = "message")
  # Navigate back to dashboard
  nav_select("main_content", "dashboard")
  rv$current_nav <- "dashboard"
})
```

**Step 5: Commit**

```bash
git add server/shared-server.R
git commit -m "feat: rewrite login modal with username/password auth and bootstrap flow"
```

---

### Task 6: Add Manage Admins UI

**Files:**
- Create: `views/admin-users-ui.R`

**Step 1: Create the UI file**

Create `views/admin-users-ui.R`:

```r
# =============================================================================
# Admin Users UI - Manage admin accounts (super admin only)
# =============================================================================

admin_users_ui <- nav_panel_hidden(
  value = "admin_users",

  div(
    class = "page-header",
    h2("Manage Admins"),
    tags$p(class = "text-muted", "Add, edit, and deactivate admin accounts.")
  ),

  layout_columns(
    col_widths = c(8, 4),
    fill = FALSE,

    # Admin list
    card(
      card_header("Admin Accounts"),
      card_body(
        reactableOutput("admin_users_table")
      )
    ),

    # Add/Edit form
    card(
      card_header(
        textOutput("admin_form_title")
      ),
      card_body(
        textInput("admin_username", "Username", placeholder = "e.g., sarah"),
        textInput("admin_display_name", "Display Name", placeholder = "e.g., Sarah"),
        passwordInput("admin_password", "Password"),
        tags$p(class = "form-text text-muted", id = "password_hint",
               "Leave blank when editing to keep existing password."),
        selectInput("admin_role", "Role",
                    choices = c("Scene Admin" = "scene_admin",
                                "Super Admin" = "super_admin"),
                    selected = "scene_admin",
                    selectize = FALSE),
        conditionalPanel(
          condition = "input.admin_role == 'scene_admin'",
          selectInput("admin_scene", "Assigned Scene",
                      choices = list("Select scene..." = ""),
                      selectize = FALSE)
        ),
        div(
          class = "d-flex gap-2 mt-3",
          actionButton("save_admin_btn", "Save", class = "btn-primary"),
          actionButton("clear_admin_form_btn", "Clear", class = "btn-outline-secondary")
        )
      )
    )
  ),

  # Deactivate/Reactivate section (shown when editing)
  conditionalPanel(
    condition = "output.editing_admin",
    card(
      class = "mt-3",
      card_body(
        div(
          class = "d-flex justify-content-between align-items-center",
          tags$p(class = "mb-0", "Toggle this admin account's active status."),
          actionButton("toggle_admin_active_btn", "Deactivate", class = "btn-outline-danger btn-sm")
        )
      )
    )
  )
)
```

**Step 2: Commit**

```bash
git add views/admin-users-ui.R
git commit -m "feat: add Manage Admins UI page"
```

---

### Task 7: Add Manage Admins Server Logic

**Files:**
- Create: `server/admin-users-server.R`

**Step 1: Create the server file**

Create `server/admin-users-server.R`:

```r
# =============================================================================
# Admin Users Server - Manage admin accounts (super admin only)
# =============================================================================

# Editing state
editing_admin_id <- reactiveVal(NULL)

# Output for conditional panels
output$editing_admin <- reactive({ !is.null(editing_admin_id()) })
outputOptions(output, "editing_admin", suspendWhenHidden = FALSE)

# Form title
output$admin_form_title <- renderText({
  if (!is.null(editing_admin_id())) "Edit Admin" else "Add Admin"
})

# --- Load scene choices for dropdown ---
observe({
  req(rv$db_con, rv$is_superadmin)
  scenes <- safe_query(rv$db_con,
    "SELECT scene_id, display_name FROM scenes WHERE slug != 'all' AND is_active = TRUE ORDER BY display_name",
    default = data.frame())
  if (nrow(scenes) > 0) {
    choices <- setNames(as.character(scenes$scene_id), scenes$display_name)
    updateSelectInput(session, "admin_scene",
                      choices = c("Select scene..." = "", choices))
  }
})

# --- Admin Users Table ---
admin_users_data <- reactive({
  rv$data_refresh  # Trigger refresh
  req(rv$db_con, rv$is_superadmin)
  safe_query(rv$db_con,
    "SELECT u.user_id, u.username, u.display_name, u.role,
            u.is_active, u.created_at, s.display_name as scene_name
     FROM admin_users u
     LEFT JOIN scenes s ON u.scene_id = s.scene_id
     ORDER BY u.role DESC, u.display_name",
    default = data.frame())
})

output$admin_users_table <- renderReactable({
  df <- admin_users_data()
  req(nrow(df) > 0)

  reactable(
    df,
    columns = list(
      user_id = colDef(show = FALSE),
      username = colDef(name = "Username", minWidth = 100),
      display_name = colDef(name = "Name", minWidth = 100),
      role = colDef(name = "Role", minWidth = 100, cell = function(value) {
        if (value == "super_admin") "Super Admin" else "Scene Admin"
      }),
      scene_name = colDef(name = "Scene", minWidth = 100, cell = function(value) {
        if (is.na(value) || is.null(value)) "All (Super)" else value
      }),
      is_active = colDef(name = "Active", maxWidth = 80, cell = function(value) {
        if (value) "\u2705" else "\u274c"
      }),
      created_at = colDef(name = "Created", minWidth = 100, cell = function(value) {
        format(as.Date(value), "%b %d, %Y")
      })
    ),
    selection = "single",
    onClick = "select",
    highlight = TRUE,
    compact = TRUE,
    theme = reactableTheme(
      rowSelectedStyle = list(backgroundColor = "rgba(0, 123, 255, 0.1)")
    )
  )
})

# --- Row Selection: Populate edit form ---
observeEvent(getReactableState("admin_users_table", "selected"), {
  selected <- getReactableState("admin_users_table", "selected")
  if (is.null(selected) || length(selected) == 0) {
    editing_admin_id(NULL)
    return()
  }

  df <- admin_users_data()
  row <- df[selected, ]

  editing_admin_id(row$user_id)
  updateTextInput(session, "admin_username", value = row$username)
  updateTextInput(session, "admin_display_name", value = row$display_name)
  updateTextInput(session, "admin_password", value = "")  # Never show existing password
  updateSelectInput(session, "admin_role", selected = row$role)

  # Set scene dropdown (need scene_id, not name)
  admin_row <- safe_query(rv$db_con,
    "SELECT scene_id FROM admin_users WHERE user_id = ?",
    params = list(row$user_id),
    default = data.frame())
  if (nrow(admin_row) > 0 && !is.na(admin_row$scene_id[1])) {
    updateSelectInput(session, "admin_scene", selected = as.character(admin_row$scene_id[1]))
  } else {
    updateSelectInput(session, "admin_scene", selected = "")
  }

  # Update toggle button label
  btn_label <- if (row$is_active) "Deactivate" else "Reactivate"
  btn_class <- if (row$is_active) "btn-outline-danger btn-sm" else "btn-outline-success btn-sm"
  updateActionButton(session, "toggle_admin_active_btn", label = btn_label)
})

# --- Clear Form ---
observeEvent(input$clear_admin_form_btn, {
  editing_admin_id(NULL)
  updateTextInput(session, "admin_username", value = "")
  updateTextInput(session, "admin_display_name", value = "")
  updateTextInput(session, "admin_password", value = "")
  updateSelectInput(session, "admin_role", selected = "scene_admin")
  updateSelectInput(session, "admin_scene", selected = "")
  updateReactable("admin_users_table", selected = NA)
})

# --- Save Admin (Create or Update) ---
observeEvent(input$save_admin_btn, {
  req(rv$is_superadmin)

  username <- trimws(input$admin_username)
  display_name <- trimws(input$admin_display_name)
  password <- input$admin_password
  role <- input$admin_role
  scene_id <- if (role == "scene_admin" && nchar(input$admin_scene) > 0) {
    as.integer(input$admin_scene)
  } else {
    NA_integer_
  }

  # Validation
  if (nchar(username) < 3) {
    notify("Username must be at least 3 characters", type = "warning")
    return()
  }
  if (nchar(display_name) == 0) {
    notify("Display name is required", type = "warning")
    return()
  }
  if (role == "scene_admin" && is.na(scene_id)) {
    notify("Scene admins must have an assigned scene", type = "warning")
    return()
  }

  if (is.null(editing_admin_id())) {
    # --- CREATE new admin ---
    if (nchar(password) < 8) {
      notify("Password must be at least 8 characters", type = "warning")
      return()
    }

    # Check username uniqueness
    existing <- safe_query(rv$db_con,
      "SELECT COUNT(*) as n FROM admin_users WHERE username = ?",
      params = list(username),
      default = data.frame(n = 0))
    if (existing$n[1] > 0) {
      notify("Username already exists", type = "error")
      return()
    }

    hash <- bcrypt::hashpw(password)
    max_id <- safe_query(rv$db_con,
      "SELECT COALESCE(MAX(user_id), 0) as max_id FROM admin_users",
      default = data.frame(max_id = 0))
    new_id <- max_id$max_id[1] + 1

    result <- safe_execute(rv$db_con,
      "INSERT INTO admin_users (user_id, username, password_hash, display_name, role, scene_id)
       VALUES (?, ?, ?, ?, ?, ?)",
      params = list(new_id, username, hash, display_name, role,
                    if (is.na(scene_id)) NA_integer_ else scene_id))

    if (result > 0) {
      notify(paste0("Admin '", username, "' created"), type = "message")
      rv$data_refresh <- rv$data_refresh + 1
      # Clear form
      editing_admin_id(NULL)
      updateTextInput(session, "admin_username", value = "")
      updateTextInput(session, "admin_display_name", value = "")
      updateTextInput(session, "admin_password", value = "")
      updateSelectInput(session, "admin_role", selected = "scene_admin")
      updateSelectInput(session, "admin_scene", selected = "")
      updateReactable("admin_users_table", selected = NA)
    } else {
      notify("Failed to create admin", type = "error")
    }

  } else {
    # --- UPDATE existing admin ---
    uid <- editing_admin_id()

    # Prevent super admin from changing their own role
    if (uid == rv$admin_user$user_id && role != "super_admin") {
      notify("You cannot change your own role", type = "error")
      return()
    }

    # Check username uniqueness (excluding self)
    existing <- safe_query(rv$db_con,
      "SELECT COUNT(*) as n FROM admin_users WHERE username = ? AND user_id != ?",
      params = list(username, uid),
      default = data.frame(n = 0))
    if (existing$n[1] > 0) {
      notify("Username already exists", type = "error")
      return()
    }

    if (nchar(password) > 0) {
      # Update with new password
      if (nchar(password) < 8) {
        notify("Password must be at least 8 characters", type = "warning")
        return()
      }
      hash <- bcrypt::hashpw(password)
      safe_execute(rv$db_con,
        "DELETE FROM admin_users WHERE user_id = ?",
        params = list(uid))
      safe_execute(rv$db_con,
        "INSERT INTO admin_users (user_id, username, password_hash, display_name, role, scene_id, is_active)
         VALUES (?, ?, ?, ?, ?, ?, TRUE)",
        params = list(uid, username, hash, display_name, role,
                      if (is.na(scene_id)) NA_integer_ else scene_id))
    } else {
      # Update without changing password (DuckDB: DELETE + INSERT to preserve hash)
      old <- safe_query(rv$db_con,
        "SELECT password_hash, is_active FROM admin_users WHERE user_id = ?",
        params = list(uid),
        default = data.frame())
      if (nrow(old) == 0) {
        notify("Admin not found", type = "error")
        return()
      }
      safe_execute(rv$db_con,
        "DELETE FROM admin_users WHERE user_id = ?",
        params = list(uid))
      safe_execute(rv$db_con,
        "INSERT INTO admin_users (user_id, username, password_hash, display_name, role, scene_id, is_active)
         VALUES (?, ?, ?, ?, ?, ?, ?)",
        params = list(uid, username, old$password_hash[1], display_name, role,
                      if (is.na(scene_id)) NA_integer_ else scene_id,
                      old$is_active[1]))
    }

    notify(paste0("Admin '", username, "' updated"), type = "message")
    rv$data_refresh <- rv$data_refresh + 1

    # If editing self, update reactive state
    if (uid == rv$admin_user$user_id) {
      rv$admin_user$display_name <- display_name
      rv$admin_user$username <- username
    }
  }
})

# --- Toggle Active Status ---
observeEvent(input$toggle_admin_active_btn, {
  req(rv$is_superadmin, !is.null(editing_admin_id()))
  uid <- editing_admin_id()

  # Prevent self-deactivation
  if (uid == rv$admin_user$user_id) {
    notify("You cannot deactivate your own account", type = "error")
    return()
  }

  # Get current status
  current <- safe_query(rv$db_con,
    "SELECT is_active, username, password_hash, display_name, role, scene_id, created_at
     FROM admin_users WHERE user_id = ?",
    params = list(uid),
    default = data.frame())
  if (nrow(current) == 0) return()

  new_status <- !current$is_active[1]

  # DuckDB: DELETE + INSERT for update
  safe_execute(rv$db_con,
    "DELETE FROM admin_users WHERE user_id = ?",
    params = list(uid))
  safe_execute(rv$db_con,
    "INSERT INTO admin_users (user_id, username, password_hash, display_name, role, scene_id, is_active, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(uid, current$username[1], current$password_hash[1],
                  current$display_name[1], current$role[1],
                  if (is.na(current$scene_id[1])) NA_integer_ else current$scene_id[1],
                  new_status, current$created_at[1]))

  action <- if (new_status) "reactivated" else "deactivated"
  notify(paste0("Admin '", current$username[1], "' ", action), type = "message")
  rv$data_refresh <- rv$data_refresh + 1

  # Clear selection
  editing_admin_id(NULL)
  updateReactable("admin_users_table", selected = NA)
})
```

**Step 2: Commit**

```bash
git add server/admin-users-server.R
git commit -m "feat: add Manage Admins server logic (CRUD, toggle active)"
```

---

### Task 8: Wire Up Manage Admins in app.R

**Files:**
- Modify: `app.R` — add UI source, nav panel, sidebar link, lazy-load, and navigation handler

**Step 1: Source the UI file**

Find where other admin UI files are sourced (near the top of `app.R`, look for `source("views/admin-`)). Add:

```r
source("views/admin-users-ui.R")
```

**Step 2: Add nav panel**

In the `navset_hidden` section (~line 804-818), add after `admin_players`:

```r
        nav_panel_hidden(value = "admin_users", admin_users_ui),
```

Wait — the UI is already wrapped as a `nav_panel_hidden` in the file. So instead, just add the value reference. Actually, looking at the pattern: the other admin UIs define their content directly (not wrapped in `nav_panel_hidden`). Let me check.

The existing pattern in `app.R` lines 813-818 is:
```r
nav_panel_hidden(value = "admin_results", admin_results_ui),
```

Where `admin_results_ui` is defined in `views/admin-results-ui.R`. The UI file should export a tagList or div, NOT a `nav_panel_hidden`. So update `views/admin-users-ui.R` to remove the `nav_panel_hidden` wrapper — just export the inner content. Then add to `app.R`:

```r
nav_panel_hidden(value = "admin_users", admin_users_ui),
```

Place it after the `admin_players` line in the `navset_hidden` block.

**Step 3: Add sidebar link**

In the Super Admin `conditionalPanel` section (~lines 783-792), add before the closing paren:

```r
        actionLink("nav_admin_users",
                   tagList(bsicons::bs_icon("person-gear"), " Manage Admins"),
                   class = "nav-link-sidebar")
```

**Step 4: Add lazy-load**

In the admin modules lazy-load block (~lines 1003-1013), add:

```r
      source("server/admin-users-server.R", local = TRUE)
```

**Step 5: Add navigation handler**

Find where other admin nav handlers are defined (look for `observeEvent(input$nav_admin_stores` in shared-server.R or app.R). Add a matching handler:

```r
# Navigate to Manage Admins
observeEvent(input$nav_admin_users, {
  nav_select("main_content", "admin_users")
  rv$current_nav <- "admin_users"
})

# Also handle modal link
observeEvent(input$modal_admin_users, {
  removeModal()
  nav_select("main_content", "admin_users")
  rv$current_nav <- "admin_users"
})
```

**Step 6: Add sidebar sync for admin_users**

Find the sidebar sync handlers (the block that updates `.active` class on sidebar links). Add `admin_users` to the handler. Look for the pattern where `rv$current_nav` changes trigger sidebar CSS updates.

**Step 7: Commit**

```bash
git add app.R views/admin-users-ui.R
git commit -m "feat: wire Manage Admins tab into sidebar, navset, and lazy-load"
```

---

### Task 9: Update .env.example

**Files:**
- Modify: `.env.example` — remove old password vars, add note about bootstrap

**Step 1: Update .env.example**

Replace the admin password section (~lines 12-18) with:

```
# Admin Authentication
# No env vars needed — first admin account is created via in-app bootstrap.
# On first launch, click the lock icon to create the super admin account.
# Additional admins are managed via the "Manage Admins" tab.
```

**Step 2: Commit**

```bash
git add .env.example
git commit -m "docs: update .env.example to reflect per-user admin auth"
```

---

### Task 10: Fix admin-users-ui.R Export Pattern

**Files:**
- Modify: `views/admin-users-ui.R` — make sure it matches the pattern used by other admin UIs

**Step 1: Check existing admin UI pattern**

Read `views/admin-results-ui.R` (first 10 lines) to see how admin UIs export their content. The exported variable should be a tagList or div, NOT wrapped in `nav_panel_hidden`. Fix `admin-users-ui.R` to match.

For example, if `admin_results_ui` is defined as:
```r
admin_results_ui <- div(
  class = "page-content",
  ...
)
```

Then `admin_users_ui` should follow the same pattern.

**Step 2: Commit if changes needed**

```bash
git add views/admin-users-ui.R
git commit -m "fix: match admin-users-ui.R export pattern to other admin UIs"
```

---

### Task 11: Scene Scoping for Scene Admins

**Files:**
- Modify: `server/shared-server.R` — force scene filter for scene admins on login

**Step 1: Verify scene enforcement**

After login (Task 5 already forces the scene selector), also ensure that scene admins cannot switch scenes. Find the scene selector observer and add a guard:

```r
# In the scene selector observer (wherever input$scene_selector is handled):
# Add this check at the top:
if (rv$is_admin && !rv$is_superadmin && !is.null(rv$admin_user$scene_id)) {
  # Scene admin - force back to their assigned scene
  scene_slug <- safe_query(rv$db_con,
    "SELECT slug FROM scenes WHERE scene_id = ?",
    params = list(rv$admin_user$scene_id),
    default = data.frame())
  if (nrow(scene_slug) > 0 && input$scene_selector != scene_slug$slug[1]) {
    updateSelectInput(session, "scene_selector", selected = scene_slug$slug[1])
    notify("Scene admins can only manage their assigned scene", type = "warning")
    return()
  }
}
```

**Step 2: Commit**

```bash
git add server/shared-server.R
git commit -m "feat: enforce scene scoping for scene admin role"
```

---

### Task 12: Verification and Manual Testing

**Step 1: Syntax check**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "tryCatch(source('app.R'), error = function(e) cat('ERROR:', e$message, '\n'))"
```

**Step 2: Manual test plan**

Run `shiny::runApp()` and verify:

1. **Bootstrap flow:**
   - First launch → click lock icon → "Create Super Admin" form appears
   - Create account (username: michael, display: Michael, password: 8+ chars)
   - Verify: logged in as super admin, admin tabs visible

2. **Login/Logout:**
   - Logout → click lock icon → username/password form
   - Login with created credentials → verify welcome message
   - Login with wrong password → verify error message

3. **Manage Admins (super admin):**
   - Navigate to Manage Admins tab
   - Create a scene admin (pick a scene from dropdown)
   - Verify admin appears in table
   - Click row → form populates with edit data
   - Edit display name → save → verify update
   - Deactivate → verify status changes in table
   - Try deactivating yourself → verify error

4. **Scene scoping:**
   - Login as scene admin
   - Verify scene selector is forced to assigned scene
   - Verify Manage Admins tab is NOT visible
   - Verify Edit Stores and Edit Formats are NOT visible

5. **Edge cases:**
   - Try creating admin with duplicate username → error
   - Try creating with password < 8 chars → error
   - Scene admin with no scene selected → error

**Step 3: Final commit**

If any fixes were needed during testing, commit them:

```bash
git add -A
git commit -m "fix: address issues found during admin auth testing"
```

---

### Post-Implementation: Database Sync

After verifying locally with the super admin account created:

```bash
python scripts/sync_to_motherduck.py
```

This pushes the new `admin_users` table (with your super admin account) to MotherDuck for production.
