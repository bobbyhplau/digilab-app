# =============================================================================
# Admin Scenes Server - Manage scenes (super admin only)
# =============================================================================

# Editing state
editing_scene_id <- reactiveVal(NULL)

# Output for conditional panels
output$editing_scene <- reactive({ !is.null(editing_scene_id()) })
outputOptions(output, "editing_scene", suspendWhenHidden = FALSE)

# --- Scenes Table ---
scenes_data <- reactive({
  rv$data_refresh  # Trigger refresh
  req(rv$db_con, rv$is_superadmin)
  safe_query(rv$db_con,
    "SELECT s.scene_id, s.display_name, s.slug, s.scene_type, s.latitude, s.longitude,
            s.is_active, COUNT(st.store_id) as store_count
     FROM scenes s
     LEFT JOIN stores st ON s.scene_id = st.scene_id AND st.is_active = TRUE
     GROUP BY s.scene_id, s.display_name, s.slug, s.scene_type, s.latitude, s.longitude, s.is_active
     ORDER BY s.scene_type, s.display_name",
    default = data.frame())
})

output$admin_scenes_table <- renderReactable({
  df <- scenes_data()
  req(nrow(df) > 0)

  reactable(
    df,
    columns = list(
      scene_id = colDef(show = FALSE),
      display_name = colDef(name = "Name", minWidth = 120),
      slug = colDef(name = "Slug", minWidth = 80),
      scene_type = colDef(name = "Type", maxWidth = 80, cell = function(value) {
        if (value == "metro") "Metro" else if (value == "online") "Online" else value
      }),
      latitude = colDef(show = FALSE),
      longitude = colDef(show = FALSE),
      is_active = colDef(name = "Active", maxWidth = 70, cell = function(value) {
        if (value) "\u2705" else "\u274c"
      }),
      store_count = colDef(name = "Stores", maxWidth = 70)
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
observeEvent(getReactableState("admin_scenes_table", "selected"), {
  selected <- getReactableState("admin_scenes_table", "selected")
  if (is.null(selected) || length(selected) == 0) {
    editing_scene_id(NULL)
    return()
  }

  df <- scenes_data()
  row <- df[selected, ]

  editing_scene_id(row$scene_id)
  updateTextInput(session, "scene_display_name", value = row$display_name)
  updateTextInput(session, "scene_slug", value = row$slug)
  updateSelectInput(session, "scene_type", selected = row$scene_type)

  # Build location hint from existing coordinates
  if (!is.na(row$latitude) && !is.na(row$longitude)) {
    updateTextInput(session, "scene_location",
                    value = paste0(row$display_name, " (has coordinates)"))
  } else {
    updateTextInput(session, "scene_location", value = "")
  }

  updateCheckboxInput(session, "scene_is_active", value = row$is_active)

  shinyjs::html("scene_form_title", "Edit Scene")
})

# --- Clear Form ---
observeEvent(input$clear_scene_form_btn, {
  editing_scene_id(NULL)
  updateTextInput(session, "scene_display_name", value = "")
  updateTextInput(session, "scene_slug", value = "")
  updateSelectInput(session, "scene_type", selected = "metro")
  updateTextInput(session, "scene_location", value = "")
  updateCheckboxInput(session, "scene_is_active", value = TRUE)
  updateReactable("admin_scenes_table", selected = NA)
  shinyjs::html("scene_form_title", "Add Scene")
})

# --- Show stores in selected scene ---
output$scene_stores_list <- renderUI({
  sid <- editing_scene_id()
  if (is.null(sid)) {
    return(tags$p(class = "text-muted small", "Select a scene to view its stores."))
  }

  stores <- safe_query(rv$db_con,
    "SELECT name, city, is_online, is_active FROM stores
     WHERE scene_id = ? ORDER BY name",
    params = list(sid),
    default = data.frame())

  if (nrow(stores) == 0) {
    return(tags$p(class = "text-muted small", "No stores assigned to this scene."))
  }

  store_items <- lapply(seq_len(nrow(stores)), function(i) {
    s <- stores[i, ]
    status <- if (s$is_active) "" else " (inactive)"
    location <- if (s$is_online) "Online" else s$city
    tags$div(
      class = "d-flex justify-content-between align-items-center py-1",
      tags$span(paste0(s$name, status)),
      tags$span(class = "text-muted small", location)
    )
  })

  tagList(
    tags$div(class = "small text-muted mb-1",
             paste0(nrow(stores), " store", if (nrow(stores) != 1) "s")),
    do.call(tagList, store_items)
  )
})

# --- Save Scene (Create or Update) ---
observeEvent(input$save_scene_btn, {
  req(rv$is_superadmin)

  display_name <- trimws(input$scene_display_name)
  slug <- trimws(tolower(input$scene_slug))
  scene_type <- input$scene_type
  is_active <- input$scene_is_active

  # Validation
  if (nchar(display_name) == 0) {
    notify("Display name is required", type = "warning")
    return()
  }
  if (nchar(slug) == 0) {
    notify("URL slug is required", type = "warning")
    return()
  }
  if (!grepl("^[a-z0-9-]+$", slug)) {
    notify("Slug must be lowercase letters, numbers, and hyphens only", type = "warning")
    return()
  }

  # Geocode for metro scenes
  lat <- NA_real_
  lng <- NA_real_
  if (scene_type == "metro") {
    location <- trimws(input$scene_location)

    # If editing and location field wasn't changed (still shows hint), keep existing coords
    if (!is.null(editing_scene_id())) {
      old_scene <- safe_query(rv$db_con,
        "SELECT latitude, longitude FROM scenes WHERE scene_id = ?",
        params = list(editing_scene_id()),
        default = data.frame())
      if (nrow(old_scene) > 0 && grepl("has coordinates", location, fixed = TRUE)) {
        lat <- old_scene$latitude[1]
        lng <- old_scene$longitude[1]
      }
    }

    # Geocode if we don't already have coordinates
    if (is.na(lat) || is.na(lng)) {
      if (nchar(location) == 0) {
        notify("Location is required for metro scenes (e.g., 'Houston, TX')", type = "warning")
        return()
      }
      notify("Geocoding location...", type = "message", duration = 2)
      geo_result <- geocode_with_mapbox(location)
      lat <- geo_result$lat
      lng <- geo_result$lng

      if (is.na(lat) || is.na(lng)) {
        notify("Could not geocode location. Try a more specific location (e.g., 'Houston, Texas, USA').",
               type = "warning", duration = 5)
        return()
      }
    }
  }

  if (is.null(editing_scene_id())) {
    # --- CREATE new scene ---
    # Check slug uniqueness
    existing <- safe_query(rv$db_con,
      "SELECT COUNT(*) as n FROM scenes WHERE slug = ?",
      params = list(slug),
      default = data.frame(n = 0))
    if (existing$n[1] > 0) {
      notify("A scene with that slug already exists", type = "error")
      return()
    }

    max_id <- safe_query(rv$db_con,
      "SELECT COALESCE(MAX(scene_id), 0) as max_id FROM scenes",
      default = data.frame(max_id = 0))
    new_id <- max_id$max_id[1] + 1

    result <- safe_execute(rv$db_con,
      "INSERT INTO scenes (scene_id, name, slug, display_name, scene_type, latitude, longitude, is_active)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      params = list(new_id, display_name, slug, display_name, scene_type,
                    if (is.na(lat)) NA_real_ else lat,
                    if (is.na(lng)) NA_real_ else lng,
                    is_active))

    if (result > 0) {
      notify(paste0("Scene '", display_name, "' created"), type = "message")
      rv$data_refresh <- rv$data_refresh + 1

      # Clear form
      editing_scene_id(NULL)
      updateTextInput(session, "scene_display_name", value = "")
      updateTextInput(session, "scene_slug", value = "")
      updateSelectInput(session, "scene_type", selected = "metro")
      updateTextInput(session, "scene_location", value = "")
      updateCheckboxInput(session, "scene_is_active", value = TRUE)
      updateReactable("admin_scenes_table", selected = NA)
    } else {
      notify("Failed to create scene", type = "error")
    }

  } else {
    # --- UPDATE existing scene ---
    sid <- editing_scene_id()

    # Check slug uniqueness (excluding self)
    existing <- safe_query(rv$db_con,
      "SELECT COUNT(*) as n FROM scenes WHERE slug = ? AND scene_id != ?",
      params = list(slug, sid),
      default = data.frame(n = 0))
    if (existing$n[1] > 0) {
      notify("A scene with that slug already exists", type = "error")
      return()
    }

    safe_execute(rv$db_con,
      "UPDATE scenes SET name = ?, slug = ?, display_name = ?, scene_type = ?,
       latitude = ?, longitude = ?, is_active = ?
       WHERE scene_id = ?",
      params = list(display_name, slug, display_name, scene_type,
                    if (is.na(lat)) NA_real_ else lat,
                    if (is.na(lng)) NA_real_ else lng,
                    is_active, sid))

    notify(paste0("Scene '", display_name, "' updated"), type = "message")
    rv$data_refresh <- rv$data_refresh + 1
  }
})

# --- Delete Scene ---
observeEvent(input$delete_scene_btn, {
  req(rv$is_superadmin, !is.null(editing_scene_id()))
  sid <- editing_scene_id()

  # Check for associated stores
  store_count <- safe_query(rv$db_con,
    "SELECT COUNT(*) as n FROM stores WHERE scene_id = ?",
    params = list(sid),
    default = data.frame(n = 0))

  if (store_count$n[1] > 0) {
    notify(paste0("Cannot delete: ", store_count$n[1], " store(s) are assigned to this scene. Reassign them first."),
           type = "error", duration = 5)
    return()
  }

  # Check for admin users assigned to this scene
  admin_count <- safe_query(rv$db_con,
    "SELECT COUNT(*) as n FROM admin_users WHERE scene_id = ?",
    params = list(sid),
    default = data.frame(n = 0))

  if (admin_count$n[1] > 0) {
    notify(paste0("Cannot delete: ", admin_count$n[1], " admin(s) are assigned to this scene. Reassign them first."),
           type = "error", duration = 5)
    return()
  }

  safe_execute(rv$db_con,
    "DELETE FROM scenes WHERE scene_id = ?",
    params = list(sid))

  scene_name <- input$scene_display_name
  notify(paste0("Scene '", scene_name, "' deleted"), type = "message")
  rv$data_refresh <- rv$data_refresh + 1

  # Clear form
  editing_scene_id(NULL)
  updateTextInput(session, "scene_display_name", value = "")
  updateTextInput(session, "scene_slug", value = "")
  updateSelectInput(session, "scene_type", selected = "metro")
  updateTextInput(session, "scene_location", value = "")
  updateCheckboxInput(session, "scene_is_active", value = TRUE)
  updateReactable("admin_scenes_table", selected = NA)
  shinyjs::html("scene_form_title", "Add Scene")
})
