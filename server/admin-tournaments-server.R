# =============================================================================
# Admin: Edit Tournaments Server Logic
# =============================================================================

# Edit grid state
rv$edit_grid_data <- NULL
rv$edit_record_format <- "points"
rv$edit_player_matches <- list()
rv$edit_deleted_result_ids <- c()
rv$edit_grid_tournament_id <- NULL

# Update edit form dropdowns when data changes
observe({
  req(rv$db_con)
  rv$format_refresh

  # Update store dropdown for edit form
  updateSelectInput(session, "edit_tournament_store",
                    choices = get_store_choices(rv$db_con, include_none = TRUE))

  # Update format dropdown for edit form
  format_choices <- get_format_choices(rv$db_con)
  updateSelectInput(session, "edit_tournament_format", choices = format_choices)
})

# Auto-select tournament when navigated from duplicate modal
observe({
  req(rv$navigate_to_tournament_id)

  # Trigger the same logic as clicking a row
  tournament_id <- rv$navigate_to_tournament_id
  rv$navigate_to_tournament_id <- NULL  # Clear to prevent re-triggering

  # Get tournament details
  tournament <- dbGetQuery(rv$db_con, "
    SELECT t.*, s.name as store_name
    FROM tournaments t
    LEFT JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = ?
  ", params = list(tournament_id))

  if (nrow(tournament) == 0) return()

  # Fill form (same as click handler)
  updateTextInput(session, "editing_tournament_id", value = as.character(tournament$tournament_id))
  updateSelectInput(session, "edit_tournament_store", selected = tournament$store_id)
  updateDateInput(session, "edit_tournament_date", value = tournament$event_date)
  updateSelectInput(session, "edit_tournament_type", selected = tournament$event_type)
  updateSelectInput(session, "edit_tournament_format", selected = tournament$format)
  updateNumericInput(session, "edit_tournament_players", value = tournament$player_count)
  updateNumericInput(session, "edit_tournament_rounds", value = tournament$rounds)

  # Show buttons
  shinyjs::show("update_tournament")
  shinyjs::show("delete_tournament")
  shinyjs::show("view_results_btn_container")

  notify(sprintf("Editing: %s - %s", tournament$store_name, tournament$event_date),
                   type = "message", duration = 3)
})

# Debounce admin search input (300ms)
admin_tournament_search_debounced <- reactive(input$admin_tournament_search) |> debounce(300)

# Tournament list table
output$admin_tournament_list <- renderReactable({
  req(rv$db_con)

  # Trigger refresh
  input$update_tournament
  input$confirm_delete_tournament
  input$admin_tournaments_show_all_scenes

  # Search filter
  search <- admin_tournament_search_debounced() %||% ""
  scene <- rv$current_scene
  show_all <- isTRUE(input$admin_tournaments_show_all_scenes) && isTRUE(rv$is_superadmin)

  # Build scene filter
  scene_filter <- ""
  if (!show_all && !is.null(scene) && scene != "" && scene != "all") {
    if (scene == "online") {
      scene_filter <- "AND s.is_online = TRUE"
    } else {
      scene_filter <- sprintf("AND s.scene_id = (SELECT scene_id FROM scenes WHERE slug = '%s')", scene)
    }
  }

  # Build query
  query <- sprintf("
    SELECT t.tournament_id,
           s.name as store_name,
           t.event_date,
           t.event_type,
           t.format,
           t.player_count,
           t.rounds,
           COUNT(r.result_id) as results_entered
    FROM tournaments t
    LEFT JOIN stores s ON t.store_id = s.store_id
    LEFT JOIN results r ON t.tournament_id = r.tournament_id
    WHERE 1=1 %s
  ", scene_filter)

  if (nchar(search) > 0) {
    query <- paste0(query, " AND LOWER(s.name) LIKE LOWER('%", search, "%')")
  }

  query <- paste0(query, " GROUP BY t.tournament_id, s.name, t.event_date, t.event_type, t.format, t.player_count, t.rounds
                          ORDER BY t.event_date DESC")

  data <- dbGetQuery(rv$db_con, query)

  if (nrow(data) == 0) {
    return(reactable(data.frame(Message = "No tournaments found")))
  }

  # Format event type
  format_event_type <- function(type) {
    type_labels <- c(
      "locals" = "Locals",
      "online" = "Online",
      "evo_cup" = "Evo Cup",
      "store_championship" = "Store Champ",
      "regionals" = "Regionals",
      "regulation_battle" = "Reg Battle",
      "release_event" = "Release",
      "other" = "Other"
    )
    type_labels[type] %||% type
  }

  # Prepare display data
  display_data <- data.frame(
    ID = data$tournament_id,
    Store = data$store_name,
    Date = as.character(data$event_date),
    Type = sapply(data$event_type, format_event_type),
    Format = data$format,
    Players = data$player_count,
    Rounds = data$rounds,
    Results = data$results_entered,
    stringsAsFactors = FALSE
  )

  # Store tournament_id in a way we can retrieve on click
  reactable(
    display_data,
    selection = "single",
    onClick = JS("function(rowInfo, column) {
      if (rowInfo) {
        Shiny.setInputValue('admin_tournament_list_clicked', {
          tournament_id: rowInfo.row.ID,
          nonce: Math.random()
        }, {priority: 'event'});
      }
    }"),
    highlight = TRUE,
    compact = TRUE,
    pagination = TRUE,
    defaultPageSize = 32,
    columns = list(
      ID = colDef(show = FALSE),
      Store = colDef(minWidth = 150),
      Date = colDef(width = 100),
      Type = colDef(width = 90),
      Format = colDef(width = 70),
      Players = colDef(width = 70, align = "center"),
      Rounds = colDef(width = 65, align = "center"),
      Results = colDef(width = 70, align = "center")
    )
  )
})

# Click row to edit
observeEvent(input$admin_tournament_list_clicked, {
  req(rv$db_con)
  tournament_id <- input$admin_tournament_list_clicked$tournament_id

  if (is.null(tournament_id)) return()

  # Get tournament details
  tournament <- dbGetQuery(rv$db_con, "
    SELECT t.*, s.name as store_name
    FROM tournaments t
    LEFT JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = ?
  ", params = list(tournament_id))

  if (nrow(tournament) == 0) return()

  # Fill form
  updateTextInput(session, "editing_tournament_id", value = as.character(tournament$tournament_id))
  updateSelectInput(session, "edit_tournament_store", selected = tournament$store_id)
  updateDateInput(session, "edit_tournament_date", value = tournament$event_date)
  updateSelectInput(session, "edit_tournament_type", selected = tournament$event_type)
  updateSelectInput(session, "edit_tournament_format", selected = tournament$format)
  updateNumericInput(session, "edit_tournament_players", value = tournament$player_count)
  updateNumericInput(session, "edit_tournament_rounds", value = tournament$rounds)

  # Show buttons
  shinyjs::show("update_tournament")
  shinyjs::show("delete_tournament")

  notify(sprintf("Editing: %s - %s", tournament$store_name, tournament$event_date),
                   type = "message", duration = 2)
})

# Tournament stats info
output$tournament_stats_info <- renderUI({
  req(rv$db_con, input$editing_tournament_id)

  tid <- as.integer(input$editing_tournament_id)

  # Get results count
  results_count <- dbGetQuery(rv$db_con, "
    SELECT COUNT(*) as cnt FROM results WHERE tournament_id = ?
  ", params = list(tid))$cnt

  # Get winner info
  winner <- dbGetQuery(rv$db_con, "
    SELECT p.display_name, da.archetype_name
    FROM results r
    JOIN players p ON r.player_id = p.player_id
    LEFT JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
    WHERE r.tournament_id = ? AND r.placement = 1
  ", params = list(tid))

  tagList(
    div(
      class = "d-flex gap-4 text-muted small",
      div(bsicons::bs_icon("people-fill"), sprintf(" %d results entered", results_count)),
      if (nrow(winner) > 0) {
        div(bsicons::bs_icon("trophy-fill"),
            sprintf(" Winner: %s (%s)", winner$display_name, winner$archetype_name %||% "Unknown deck"))
      }
    )
  )
})

# Update tournament
observeEvent(input$update_tournament, {
  req(rv$is_admin, rv$db_con, input$editing_tournament_id)

  clear_all_field_errors(session)

  tournament_id <- as.integer(input$editing_tournament_id)
  store_id <- input$edit_tournament_store
  event_date <- input$edit_tournament_date
  event_type <- input$edit_tournament_type
  format <- input$edit_tournament_format
  player_count <- input$edit_tournament_players
  rounds <- input$edit_tournament_rounds

  # Validation
  if (is.null(store_id) || store_id == "") {
    show_field_error(session, "edit_tournament_store")
    notify("Please select a store", type = "error")
    return()
  }

  if (is.null(event_type) || event_type == "") {
    show_field_error(session, "edit_tournament_type")
    notify("Please select an event type", type = "error")
    return()
  }

  tryCatch({
    dbExecute(rv$db_con, "
      UPDATE tournaments
      SET store_id = $1, event_date = $2, event_type = $3, format = $4,
          player_count = $5, rounds = $6, updated_at = CURRENT_TIMESTAMP
      WHERE tournament_id = $7
    ", params = list(as.integer(store_id), event_date, event_type, format,
                     player_count, rounds, tournament_id))

    notify("Tournament updated", type = "message")

    # Reset form
    reset_tournament_form()

    # Trigger table refresh (admin + public tables)
    rv$tournament_refresh <- (rv$tournament_refresh %||% 0) + 1
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# Cancel edit tournament
observeEvent(input$cancel_edit_tournament, {
  reset_tournament_form()
})

# Helper function to reset form
reset_tournament_form <- function() {
  updateTextInput(session, "editing_tournament_id", value = "")
  updateSelectInput(session, "edit_tournament_store", selected = "")
  updateDateInput(session, "edit_tournament_date", value = Sys.Date())
  updateSelectInput(session, "edit_tournament_type", selected = "")
  updateNumericInput(session, "edit_tournament_players", value = 8)
  updateNumericInput(session, "edit_tournament_rounds", value = 3)

  shinyjs::hide("update_tournament")
  shinyjs::hide("delete_tournament")
  shinyjs::hide("view_results_btn_container")
}

# Delete button click - show modal
observeEvent(input$delete_tournament, {
  req(rv$is_admin, input$editing_tournament_id)

  tournament_id <- as.integer(input$editing_tournament_id)

  # Get tournament info and results count
  tournament <- dbGetQuery(rv$db_con, "
    SELECT t.*, s.name as store_name,
           (SELECT COUNT(*) FROM results WHERE tournament_id = t.tournament_id) as results_count
    FROM tournaments t
    LEFT JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = ?
  ", params = list(tournament_id))

  showModal(modalDialog(
    title = "Confirm Delete",
    div(
      p(sprintf("Are you sure you want to delete this tournament?")),
      p(tags$strong(sprintf("%s - %s", tournament$store_name, tournament$event_date))),
      if (tournament$results_count > 0) {
        p(class = "text-danger",
          bsicons::bs_icon("exclamation-triangle-fill"),
          sprintf(" This will also delete %d result(s)!", tournament$results_count))
      },
      p(class = "text-muted small", "This action cannot be undone.")
    ),
    footer = tagList(
      actionButton("confirm_delete_tournament", "Delete", class = "btn-danger"),
      modalButton("Cancel")
    ),
    easyClose = TRUE
  ))
})

# Confirm delete tournament
observeEvent(input$confirm_delete_tournament, {
  req(rv$is_admin, rv$db_con, input$editing_tournament_id)

  tournament_id <- as.integer(input$editing_tournament_id)

  tryCatch({
    # Delete results first (cascade)
    dbExecute(rv$db_con, "DELETE FROM results WHERE tournament_id = ?",
              params = list(tournament_id))

    # Delete tournament
    dbExecute(rv$db_con, "DELETE FROM tournaments WHERE tournament_id = ?",
              params = list(tournament_id))

    notify("Tournament and results deleted", type = "message")

    # Hide modal and reset form
    removeModal()
    reset_tournament_form()

    # Trigger table refresh (admin + public tables)
    rv$tournament_refresh <- (rv$tournament_refresh %||% 0) + 1
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# =============================================================================
# Results Modal Handlers
# =============================================================================

# Helper: show the results editor modal (can be called multiple times)
show_results_editor <- function() {
  showModal(modalDialog(
    # Tournament summary
    uiOutput("results_modal_summary"),

    hr(),

    # Add result button
    div(
      class = "mb-3",
      actionButton("modal_add_result", "+ Add Result",
                   class = "btn-outline-primary btn-sm",
                   icon = icon("plus"))
    ),

    # Results table
    reactableOutput("modal_results_table"),

    # Add result form (hidden initially)
    shinyjs::hidden(
      div(
        id = "modal_add_result_form",
        class = "card mt-3 p-3 bg-light",
        h6("Add New Result"),
        div(
          class = "row g-2",
          div(class = "col-md-6",
              selectizeInput("modal_new_player", "Player",
                             choices = NULL,
                             options = list(create = FALSE, placeholder = "Select player..."))),
          div(class = "col-md-6",
              selectizeInput("modal_new_deck", "Deck",
                             choices = NULL,
                             options = list(create = FALSE, placeholder = "Select deck...")))
        ),
        div(
          class = "row g-2 mt-2",
          div(class = "col-md-3",
              numericInput("modal_new_placement", "Place", value = 1, min = 1)),
          div(class = "col-md-3",
              numericInput("modal_new_wins", "Wins", value = 0, min = 0)),
          div(class = "col-md-3",
              numericInput("modal_new_losses", "Losses", value = 0, min = 0)),
          div(class = "col-md-3",
              numericInput("modal_new_ties", "Ties", value = 0, min = 0))
        ),
        div(
          class = "row g-2 mt-2",
          div(class = "col-12",
              textInput("modal_new_decklist", "Decklist URL (optional)", placeholder = "https://..."))
        ),
        div(
          class = "d-flex gap-2 mt-3",
          actionButton("modal_save_new_result", "Save", class = "btn-success btn-sm"),
          actionButton("modal_cancel_new_result", "Cancel", class = "btn-outline-secondary btn-sm")
        )
      )
    ),

    title = tagList(bsicons::bs_icon("list-check"), " Tournament Results"),
    footer = modalButton("Done"),
    size = "l",
    easyClose = TRUE
  ))
}

# Helper: show the edit result modal
show_edit_result_modal <- function() {
  showModal(modalDialog(
    # Hidden field for result ID
    textInput("modal_editing_result_id", NULL, value = ""),
    tags$script("document.getElementById('modal_editing_result_id').parentElement.style.display = 'none';"),

    selectizeInput("modal_edit_player", "Player",
                   choices = NULL,
                   options = list(create = FALSE, placeholder = "Select player...")),
    selectizeInput("modal_edit_deck", "Deck",
                   choices = NULL,
                   options = list(create = FALSE, placeholder = "Select deck...")),
    div(
      class = "modal-numeric-inputs",
      layout_columns(
        col_widths = c(3, 3, 3, 3),
        numericInput("modal_edit_placement", "Place", value = 1, min = 1),
        numericInput("modal_edit_wins", "Wins", value = 0, min = 0),
        numericInput("modal_edit_losses", "Losses", value = 0, min = 0),
        numericInput("modal_edit_ties", "Ties", value = 0, min = 0)
      )
    ),
    div(
      class = "mt-2",
      textInput("modal_edit_decklist", "Decklist URL (optional)")
    ),

    title = tagList(bsicons::bs_icon("pencil-square"), " Edit Result"),
    footer = tagList(
      actionButton("modal_delete_result", "Delete", class = "btn-danger"),
      div(
        class = "d-inline",
        actionButton("modal_cancel_edit_result", "Cancel", class = "btn-secondary"),
        actionButton("modal_save_edit_result", "Save Changes", class = "btn-success ms-2")
      )
    ),
    easyClose = FALSE
  ))
}

# Helper: show delete result confirmation modal
show_delete_result_confirm <- function() {
  showModal(modalDialog(
    p("Are you sure you want to delete this result?"),
    p(class = "text-muted small", "This action cannot be undone."),

    title = "Delete Result?",
    footer = tagList(
      actionButton("modal_cancel_delete_result", "Cancel", class = "btn-secondary"),
      actionButton("modal_confirm_delete_result", "Delete", class = "btn-danger")
    ),
    size = "s",
    easyClose = FALSE
  ))
}

# Show View/Edit Results button when tournament is selected
observeEvent(input$admin_tournament_list_clicked, {
  # Button is shown in the existing click handler, add this line there
  shinyjs::show("view_results_btn_container")
}, priority = -1)  # Run after main handler

# Hide button when form is cancelled/reset
observeEvent(input$cancel_edit_tournament, {
  shinyjs::hide("view_results_btn_container")
}, priority = -1)

# Open edit results grid
observeEvent(input$view_edit_results, {
  req(rv$db_con, input$editing_tournament_id)

  tournament_id <- as.integer(input$editing_tournament_id)
  rv$edit_grid_tournament_id <- tournament_id

  # Load existing results into grid
  grid <- load_grid_from_results(tournament_id, rv$db_con)

  # Infer record format: if any row has ties > 0 or wins don't cleanly convert to points, use WLT
  has_ties <- any(grid$ties > 0)
  has_irregular <- any((grid$wins * 3L + grid$ties) != grid$points & nchar(trimws(grid$player_name)) > 0)
  rv$edit_record_format <- if (has_ties || has_irregular) "wlt" else "points"

  # Add blank rows to allow adding more results (pad to at least current count + 4)
  current_count <- nrow(grid)
  pad_count <- max(current_count + 4, 8)
  if (current_count < pad_count) {
    extra <- init_grid_data(pad_count - current_count)
    extra$placement <- seq(current_count + 1, pad_count)
    grid <- rbind(grid, extra)
  }

  rv$edit_grid_data <- grid
  rv$edit_deleted_result_ids <- c()

  # Build player matches from loaded data
  rv$edit_player_matches <- list()
  for (i in seq_len(current_count)) {
    if (nchar(trimws(grid$player_name[i])) > 0) {
      rv$edit_player_matches[[as.character(i)]] <- list(
        status = "matched",
        player_id = grid$matched_player_id[i],
        member_number = grid$matched_member_number[i]
      )
    }
  }

  shinyjs::show("edit_results_grid_section")
})

# Edit grid rendering
output$edit_grid_table <- renderUI({
  req(rv$edit_grid_data)

  grid <- rv$edit_grid_data
  record_format <- rv$edit_record_format %||% "points"

  # Check if release event
  is_release <- FALSE
  if (!is.null(rv$edit_grid_tournament_id) && !is.null(rv$db_con) && dbIsValid(rv$db_con)) {
    t_info <- dbGetQuery(rv$db_con, "SELECT event_type FROM tournaments WHERE tournament_id = ?",
                         params = list(rv$edit_grid_tournament_id))
    if (nrow(t_info) > 0) is_release <- t_info$event_type[1] == "release_event"
  }

  deck_choices <- build_deck_choices(rv$db_con)

  render_grid_ui(grid, record_format, is_release, deck_choices, rv$edit_player_matches, "edit_")
})

# Edit grid summary bar
output$edit_grid_summary_bar <- renderUI({
  req(rv$db_con, rv$edit_grid_tournament_id)

  tournament <- dbGetQuery(rv$db_con, "
    SELECT t.*, s.name as store_name
    FROM tournaments t
    LEFT JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = ?
  ", params = list(rv$edit_grid_tournament_id))

  if (nrow(tournament) == 0) return(NULL)

  div(
    class = "tournament-summary-bar mb-3",
    div(class = "summary-detail", bsicons::bs_icon("shop"), tournament$store_name),
    div(class = "summary-detail", bsicons::bs_icon("calendar"), as.character(tournament$event_date)),
    div(class = "summary-detail", bsicons::bs_icon("tag"), tournament$format),
    div(class = "summary-detail", bsicons::bs_icon("people"), paste(tournament$player_count, "players"))
  )
})

# Edit grid format badge
output$edit_record_format_badge <- renderUI({
  format <- rv$edit_record_format %||% "points"
  label <- if (format == "points") "Points mode" else "W-L-T mode"
  span(class = "badge bg-info", label)
})

# Edit grid filled count
output$edit_filled_count <- renderUI({
  req(rv$edit_grid_data)
  grid <- rv$edit_grid_data
  filled <- sum(nchar(trimws(grid$player_name)) > 0)
  total <- nrow(grid)
  span(class = "text-muted small", sprintf("Filled: %d/%d", filled, total))
})

# Cancel edit grid
observeEvent(input$edit_grid_cancel, {
  shinyjs::hide("edit_results_grid_section")
  rv$edit_grid_data <- NULL
  rv$edit_player_matches <- list()
  rv$edit_deleted_result_ids <- c()
  rv$edit_grid_tournament_id <- NULL
})

# =============================================================================
# Edit Grid: Interactivity (delete, player matching, paste, deck requests)
# =============================================================================

# Delete row handler
observeEvent(input$edit_delete_row, {
  req(rv$edit_grid_data)
  row_idx <- as.integer(input$edit_delete_row)
  if (is.null(row_idx) || row_idx < 1 || row_idx > nrow(rv$edit_grid_data)) return()

  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_")
  grid <- rv$edit_grid_data

  # Track deleted result_ids for DB deletion on save
  deleted_result_id <- grid$result_id[row_idx]
  if (!is.na(deleted_result_id)) {
    rv$edit_deleted_result_ids <- c(rv$edit_deleted_result_ids, deleted_result_id)
  }

  # Remove the row
  grid <- grid[-row_idx, ]

  # Append blank row
  blank_row <- data.frame(
    placement = nrow(grid) + 1,
    player_name = "", points = 0L, wins = 0L, losses = 0L, ties = 0L,
    deck_id = NA_integer_, match_status = "", matched_player_id = NA_integer_,
    matched_member_number = NA_character_, result_id = NA_integer_,
    stringsAsFactors = FALSE
  )
  grid <- rbind(grid, blank_row)
  grid$placement <- seq_len(nrow(grid))

  # Shift match indices
  new_matches <- list()
  for (j in seq_len(nrow(grid))) {
    old_idx <- if (j < row_idx) j else j + 1
    if (!is.null(rv$edit_player_matches[[as.character(old_idx)]])) {
      new_matches[[as.character(j)]] <- rv$edit_player_matches[[as.character(old_idx)]]
    }
  }
  rv$edit_player_matches <- new_matches
  rv$edit_grid_data <- grid
  notify(paste0("Row removed. Players renumbered 1-", nrow(grid), "."), type = "message", duration = 3)
})

# Attach blur handlers for edit grid
observe({
  req(rv$edit_grid_data)
  shinyjs::runjs("
    $(document).off('blur.editGrid').on('blur.editGrid', 'input[id^=\"edit_player_\"]', function() {
      var id = $(this).attr('id');
      var rowNum = parseInt(id.replace('edit_player_', ''));
      if (!isNaN(rowNum)) {
        Shiny.setInputValue('edit_player_blur', {row: rowNum, name: $(this).val(), ts: Date.now()}, {priority: 'event'});
      }
    });
  ")
})

observeEvent(input$edit_player_blur, {
  req(rv$db_con, rv$edit_grid_data)

  info <- input$edit_player_blur
  row_num <- info$row
  name <- trimws(info$name)

  if (is.null(row_num) || is.na(row_num)) return()
  if (row_num < 1 || row_num > nrow(rv$edit_grid_data)) return()

  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_")

  if (nchar(name) == 0) {
    rv$edit_player_matches[[as.character(row_num)]] <- NULL
    rv$edit_grid_data$match_status[row_num] <- ""
    rv$edit_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$edit_grid_data$matched_member_number[row_num] <- NA_character_
    return()
  }

  match_info <- match_player(name, rv$db_con)
  rv$edit_player_matches[[as.character(row_num)]] <- match_info
  rv$edit_grid_data$match_status[row_num] <- match_info$status
  if (match_info$status == "matched") {
    rv$edit_grid_data$matched_player_id[row_num] <- match_info$player_id
    rv$edit_grid_data$matched_member_number[row_num] <- match_info$member_number
  } else {
    rv$edit_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$edit_grid_data$matched_member_number[row_num] <- NA_character_
  }
})

# Paste from spreadsheet modal
observeEvent(input$edit_paste_btn, {
  showModal(modalDialog(
    title = tagList(bsicons::bs_icon("clipboard"), " Paste from Spreadsheet"),
    tagList(
      p(class = "text-muted", "Paste data with one player per line. Columns separated by tabs (from a spreadsheet) or 2+ spaces."),
      p(class = "text-muted small mb-2", "Supported formats:"),
      tags$div(
        class = "bg-body-secondary rounded p-2 mb-3",
        style = "font-family: monospace; font-size: 0.8rem; white-space: pre-line;",
        tags$div(class = "fw-bold mb-1", "Names only:"),
        tags$div(class = "text-muted mb-2", "PlayerOne\nPlayerTwo"),
        tags$div(class = "fw-bold mb-1", "Names + Points:"),
        tags$div(class = "text-muted mb-2", "PlayerOne\t9\nPlayerTwo\t7"),
        tags$div(class = "fw-bold mb-1", "Names + W/L/T:"),
        tags$div(class = "text-muted", "PlayerOne\t3\t0\t0\nPlayerTwo\t2\t1\t1")
      ),
      tags$textarea(id = "edit_paste_data", class = "form-control", rows = "10",
                    placeholder = "Paste data here...")
    ),
    footer = tagList(
      actionButton("edit_paste_apply", "Fill Grid", class = "btn-primary", icon = icon("table")),
      modalButton("Cancel")
    ),
    size = "l",
    easyClose = TRUE
  ))
})

observeEvent(input$edit_paste_apply, {
  req(rv$edit_grid_data)

  paste_text <- input$edit_paste_data
  if (is.null(paste_text) || nchar(trimws(paste_text)) == 0) {
    notify("No data to paste", type = "warning")
    return()
  }

  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_")
  grid <- rv$edit_grid_data

  all_decks <- dbGetQuery(rv$db_con, "
    SELECT archetype_id, archetype_name FROM deck_archetypes WHERE is_active = TRUE
  ")

  parsed <- parse_paste_data(paste_text, all_decks)

  if (length(parsed) == 0) {
    notify("No valid lines found", type = "warning")
    return()
  }

  fill_count <- 0L
  for (idx in seq_along(parsed)) {
    if (idx > nrow(grid)) break
    p <- parsed[[idx]]
    grid$player_name[idx] <- p$name
    grid$points[idx] <- p$points
    grid$wins[idx] <- p$wins
    grid$losses[idx] <- p$losses
    grid$ties[idx] <- p$ties
    if (!is.na(p$deck_id)) grid$deck_id[idx] <- p$deck_id
    fill_count <- fill_count + 1L
  }

  removeModal()
  notify(sprintf("Filled %d rows from pasted data", fill_count), type = "message")

  for (idx in seq_len(fill_count)) {
    match_info <- match_player(grid$player_name[idx], rv$db_con)
    if (!is.null(match_info)) {
      rv$edit_player_matches[[as.character(idx)]] <- match_info
      grid$match_status[idx] <- match_info$status
      if (match_info$status == "matched") {
        grid$matched_player_id[idx] <- match_info$player_id
        grid$matched_member_number[idx] <- match_info$member_number
      }
    }
  }
  rv$edit_grid_data <- grid
})

# Deck request watcher for edit grid
observe({
  req(rv$edit_grid_data)
  grid <- rv$edit_grid_data

  lapply(seq_len(nrow(grid)), function(i) {
    observeEvent(input[[paste0("edit_deck_", i)]], {
      if (!is.null(input[[paste0("edit_deck_", i)]]) &&
          input[[paste0("edit_deck_", i)]] == "__REQUEST_NEW__") {
        rv$admin_deck_request_row <- i
        showModal(modalDialog(
          title = tagList(bsicons::bs_icon("collection-fill"), " Request New Deck"),
          textInput("editgrid_deck_request_name", "Deck Name", placeholder = "e.g., Blue Flare"),
          layout_columns(
            col_widths = c(6, 6),
            selectInput("editgrid_deck_request_color", "Primary Color",
                        choices = c("Red", "Blue", "Yellow", "Green", "Purple", "Black", "White")),
            selectInput("editgrid_deck_request_color2", "Secondary Color (optional)",
                        choices = c("None" = "", "Red", "Blue", "Yellow", "Green", "Purple", "Black", "White"))
          ),
          textInput("editgrid_deck_request_card_id", "Card ID (optional)",
                    placeholder = "e.g., BT1-001"),
          footer = tagList(
            modalButton("Cancel"),
            actionButton("edit_deck_request_submit", "Submit Request", class = "btn-primary")
          )
        ))
      }
    }, ignoreInit = TRUE)
  })
})

observeEvent(input$edit_deck_request_submit, {
  req(rv$db_con)

  deck_name <- trimws(input$editgrid_deck_request_name)
  if (nchar(deck_name) == 0) {
    notify("Please enter a deck name", type = "error")
    return()
  }

  primary_color <- input$editgrid_deck_request_color
  secondary_color <- if (!is.null(input$editgrid_deck_request_color2) && input$editgrid_deck_request_color2 != "") {
    input$editgrid_deck_request_color2
  } else NA_character_

  card_id <- if (!is.null(input$editgrid_deck_request_card_id) && trimws(input$editgrid_deck_request_card_id) != "") {
    trimws(input$editgrid_deck_request_card_id)
  } else NA_character_

  existing <- dbGetQuery(rv$db_con, "
    SELECT request_id FROM deck_requests
    WHERE LOWER(deck_name) = LOWER(?) AND status = 'pending'
  ", params = list(deck_name))

  if (nrow(existing) > 0) {
    notify(sprintf("A pending request for '%s' already exists", deck_name), type = "warning")
  } else {
    max_id <- dbGetQuery(rv$db_con, "SELECT COALESCE(MAX(request_id), 0) as max_id FROM deck_requests")$max_id
    new_id <- max_id + 1

    dbExecute(rv$db_con, "
      INSERT INTO deck_requests (request_id, deck_name, primary_color, secondary_color, display_card_id, status)
      VALUES (?, ?, ?, ?, ?, 'pending')
    ", params = list(new_id, deck_name, primary_color, secondary_color, card_id))

    notify(sprintf("Deck request submitted: %s", deck_name), type = "message")
  }

  removeModal()

  # Force grid re-render
  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_")
  rv$edit_grid_data <- rv$edit_grid_data
})

# Results modal summary
output$results_modal_summary <- renderUI({
  req(rv$db_con, rv$modal_tournament_id)

  tournament <- dbGetQuery(rv$db_con, "
    SELECT t.*, s.name as store_name
    FROM tournaments t
    LEFT JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = ?
  ", params = list(rv$modal_tournament_id))

  if (nrow(tournament) == 0) return(NULL)

  div(
    class = "d-flex flex-wrap gap-3 align-items-center text-muted",
    span(tags$strong(tournament$store_name)),
    span(bsicons::bs_icon("calendar"), " ", as.character(tournament$event_date)),
    span(bsicons::bs_icon("tag"), " ", tournament$format),
    span(bsicons::bs_icon("people"), " ", tournament$player_count, " players")
  )
})

# Results table in modal
output$modal_results_table <- renderReactable({
  req(rv$db_con, rv$modal_tournament_id)

  # Trigger refresh
  rv$modal_results_refresh

  results <- dbGetQuery(rv$db_con, "
    SELECT r.result_id, r.placement, p.display_name as player,
           da.archetype_name as deck, da.primary_color,
           r.wins, r.losses, r.ties, r.decklist_url
    FROM results r
    JOIN players p ON r.player_id = p.player_id
    LEFT JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
    WHERE r.tournament_id = ?
    ORDER BY r.placement
  ", params = list(rv$modal_tournament_id))

  if (nrow(results) == 0) {
    return(reactable(data.frame(Message = "No results entered yet")))
  }

  # Format record
  results$Record <- paste0(results$wins, "-", results$losses, "-", results$ties)

  display_data <- data.frame(
    result_id = results$result_id,
    Place = results$placement,
    Player = results$player,
    Deck = results$deck,
    Record = results$Record,
    stringsAsFactors = FALSE
  )

  reactable(
    display_data,
    selection = "single",
    onClick = JS("function(rowInfo, column) {
      if (rowInfo) {
        Shiny.setInputValue('modal_result_clicked', {
          result_id: rowInfo.row.result_id,
          nonce: Math.random()
        }, {priority: 'event'});
      }
    }"),
    highlight = TRUE,
    compact = TRUE,
    pagination = FALSE,
    columns = list(
      result_id = colDef(show = FALSE),
      Place = colDef(name = "#", width = 50, align = "center"),
      Player = colDef(minWidth = 120),
      Deck = colDef(minWidth = 120),
      Record = colDef(width = 80, align = "center")
    )
  )
})

# =============================================================================
# Edit/Delete Result Handlers
# =============================================================================

# Click result row to edit
observeEvent(input$modal_result_clicked, {
  req(rv$db_con, rv$modal_tournament_id)

  result_id <- input$modal_result_clicked$result_id

  result <- dbGetQuery(rv$db_con, "
    SELECT r.*
    FROM results r
    WHERE r.result_id = ? AND r.tournament_id = ?
  ", params = list(result_id, rv$modal_tournament_id))

  if (nrow(result) == 0) {
    notify("Result not found", type = "error")
    return()
  }

  # Handle various empty/null representations from DuckDB
  decklist_val <- result$decklist_url
  decklist_display <- if (is.null(decklist_val) ||
                          length(decklist_val) == 0 ||
                          is.na(decklist_val) ||
                          decklist_val == "" ||
                          decklist_val == "NA") "" else decklist_val

  # Show edit modal (replaces results editor; will re-show after save/cancel)
  show_edit_result_modal()

  # Populate form after modal renders
  updateTextInput(session, "modal_editing_result_id", value = as.character(result_id))
  updateSelectizeInput(session, "modal_edit_player",
                       choices = get_player_choices(rv$db_con),
                       selected = result$player_id)
  updateSelectizeInput(session, "modal_edit_deck",
                       choices = get_archetype_choices(rv$db_con),
                       selected = result$archetype_id)
  updateNumericInput(session, "modal_edit_placement", value = result$placement)
  updateNumericInput(session, "modal_edit_wins", value = result$wins)
  updateNumericInput(session, "modal_edit_losses", value = result$losses)
  updateNumericInput(session, "modal_edit_ties", value = result$ties)
  updateTextInput(session, "modal_edit_decklist", value = decklist_display)
})

# Save edited result
observeEvent(input$modal_save_edit_result, {
  req(rv$db_con, rv$modal_tournament_id, input$modal_editing_result_id)

  clear_all_field_errors(session)

  result_id <- as.integer(input$modal_editing_result_id)
  player_id <- as.integer(input$modal_edit_player)
  archetype_id <- as.integer(input$modal_edit_deck)
  placement <- input$modal_edit_placement
  wins <- input$modal_edit_wins %||% 0
  losses <- input$modal_edit_losses %||% 0
  ties <- input$modal_edit_ties %||% 0
  decklist_url <- if (!is.null(input$modal_edit_decklist) && nchar(input$modal_edit_decklist) > 0)
    input$modal_edit_decklist else NA_character_

  # Validation
  if (is.na(player_id)) {
    show_field_error(session, "modal_edit_player")
    notify("Please select a player", type = "error")
    return()
  }
  if (is.na(archetype_id)) {
    show_field_error(session, "modal_edit_deck")
    notify("Please select a deck", type = "error")
    return()
  }

  tryCatch({
    dbExecute(rv$db_con, "
      UPDATE results
      SET player_id = ?, archetype_id = ?, placement = ?,
          wins = ?, losses = ?, ties = ?, decklist_url = ?,
          updated_at = CURRENT_TIMESTAMP
      WHERE result_id = ? AND tournament_id = ?
    ", params = list(player_id, archetype_id, placement,
                     wins, losses, ties, decklist_url,
                     result_id, rv$modal_tournament_id))

    notify("Result updated!", type = "message")

    rv$modal_results_refresh <- (rv$modal_results_refresh %||% 0) + 1
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

    # Re-show results editor (replaces edit modal)
    show_results_editor()
    updateSelectizeInput(session, "modal_new_player",
                         choices = get_player_choices(rv$db_con))
    updateSelectizeInput(session, "modal_new_deck",
                         choices = get_archetype_choices(rv$db_con))

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# Cancel edit result — return to results editor
observeEvent(input$modal_cancel_edit_result, {
  show_results_editor()
  updateSelectizeInput(session, "modal_new_player",
                       choices = get_player_choices(rv$db_con))
  updateSelectizeInput(session, "modal_new_deck",
                       choices = get_archetype_choices(rv$db_con))
})

# Delete result button (shows confirmation, replaces edit modal)
observeEvent(input$modal_delete_result, {
  req(input$modal_editing_result_id)
  show_delete_result_confirm()
})

# Cancel delete result — return to results editor
observeEvent(input$modal_cancel_delete_result, {
  show_results_editor()
  updateSelectizeInput(session, "modal_new_player",
                       choices = get_player_choices(rv$db_con))
  updateSelectizeInput(session, "modal_new_deck",
                       choices = get_archetype_choices(rv$db_con))
})

# Confirm delete result
observeEvent(input$modal_confirm_delete_result, {
  req(rv$db_con, rv$modal_tournament_id, input$modal_editing_result_id)

  result_id <- as.integer(input$modal_editing_result_id)

  tryCatch({
    dbExecute(rv$db_con, "DELETE FROM results WHERE result_id = ? AND tournament_id = ?",
              params = list(result_id, rv$modal_tournament_id))

    notify("Result deleted", type = "message")

    rv$modal_results_refresh <- (rv$modal_results_refresh %||% 0) + 1
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

    # Re-show results editor (replaces delete confirmation modal)
    show_results_editor()
    updateSelectizeInput(session, "modal_new_player",
                         choices = get_player_choices(rv$db_con))
    updateSelectizeInput(session, "modal_new_deck",
                         choices = get_archetype_choices(rv$db_con))

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# =============================================================================
# Add New Result Handlers
# =============================================================================

# Show add result form
observeEvent(input$modal_add_result, {
  # Reset form
  updateSelectizeInput(session, "modal_new_player", selected = "")
  updateSelectizeInput(session, "modal_new_deck", selected = "")
  updateNumericInput(session, "modal_new_placement", value = 1)
  updateNumericInput(session, "modal_new_wins", value = 0)
  updateNumericInput(session, "modal_new_losses", value = 0)
  updateNumericInput(session, "modal_new_ties", value = 0)
  updateTextInput(session, "modal_new_decklist", value = "")

  shinyjs::show("modal_add_result_form")
})

# Cancel add result
observeEvent(input$modal_cancel_new_result, {
  shinyjs::hide("modal_add_result_form")
})

# Save new result
observeEvent(input$modal_save_new_result, {
  req(rv$db_con, rv$modal_tournament_id)

  clear_all_field_errors(session)

  player_id <- as.integer(input$modal_new_player)
  archetype_id <- as.integer(input$modal_new_deck)
  placement <- input$modal_new_placement
  wins <- input$modal_new_wins %||% 0
  losses <- input$modal_new_losses %||% 0
  ties <- input$modal_new_ties %||% 0
  decklist_url <- if (!is.null(input$modal_new_decklist) && nchar(input$modal_new_decklist) > 0)
    input$modal_new_decklist else NA_character_

  # Validation
  if (is.na(player_id)) {
    show_field_error(session, "modal_new_player")
    notify("Please select a player", type = "error")
    return()
  }
  if (is.na(archetype_id)) {
    show_field_error(session, "modal_new_deck")
    notify("Please select a deck", type = "error")
    return()
  }

  tryCatch({
    dbExecute(rv$db_con, "
      INSERT INTO results (tournament_id, player_id, archetype_id, placement,
                           wins, losses, ties, decklist_url)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(rv$modal_tournament_id, player_id, archetype_id, placement,
                     wins, losses, ties, decklist_url))

    notify("Result added!", type = "message")

    shinyjs::hide("modal_add_result_form")
    rv$modal_results_refresh <- (rv$modal_results_refresh %||% 0) + 1
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# Scene indicator for admin tournaments page
output$admin_tournaments_scene_indicator <- renderUI({
  scene <- rv$current_scene
  show_all <- isTRUE(input$admin_tournaments_show_all_scenes) && isTRUE(rv$is_superadmin)

  if (show_all || is.null(scene) || scene == "" || scene == "all") {
    return(NULL)
  }

  div(
    class = "badge bg-info mb-2",
    paste("Filtered to:", toupper(scene))
  )
})
