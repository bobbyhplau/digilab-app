# Edit Tournaments Grid Entry — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the modal-based results editor in Edit Tournaments with a shared grid component that has full feature parity with Enter Results (grid entry, paste from spreadsheet, player matching, deck requests).

**Architecture:** Extract grid rendering, input sync, and paste parsing from `admin-results-server.R` into a shared `R/admin_grid.R` module. Both Enter Results and Edit Tournaments call these shared functions with a prefix parameter (`admin_` vs `edit_`) to avoid input ID collisions. Edit Tournaments adds a `result_id` column to track existing rows for update/insert/delete diffing on save.

**Tech Stack:** R Shiny, bslib layout_columns, shinyjs, DuckDB

---

### Task 1: Create `R/admin_grid.R` with Shared Helper Functions

**Files:**
- Create: `R/admin_grid.R`

**Step 1: Create the shared module file with extracted functions**

The file contains 5 functions extracted from `server/admin-results-server.R`. The key change is adding a `prefix` parameter to all functions so input IDs don't collide between Enter Results (`admin_`) and Edit Tournaments (`edit_`).

```r
# R/admin_grid.R
# Shared grid functions for Enter Results and Edit Tournaments

# Ordinal helper (1st, 2nd, 3rd, etc.)
grid_ordinal <- function(n) {
  suffix <- c("th", "st", "nd", "rd", rep("th", 6))
  if (n %% 100 >= 11 && n %% 100 <= 13) {
    return(paste0(n, "th"))
  }
  return(paste0(n, suffix[(n %% 10) + 1]))
}

# Initialize blank grid data frame
init_grid_data <- function(player_count) {
  data.frame(
    placement = seq_len(player_count),
    player_name = rep("", player_count),
    points = rep(0L, player_count),
    wins = rep(0L, player_count),
    losses = rep(0L, player_count),
    ties = rep(0L, player_count),
    deck_id = rep(NA_integer_, player_count),
    match_status = rep("", player_count),
    matched_player_id = rep(NA_integer_, player_count),
    matched_member_number = rep(NA_character_, player_count),
    result_id = rep(NA_integer_, player_count),
    stringsAsFactors = FALSE
  )
}

# Load existing results into grid data frame (for edit mode)
load_grid_from_results <- function(tournament_id, con) {
  results <- dbGetQuery(con, "
    SELECT r.result_id, r.placement, p.display_name AS player_name,
           r.wins, r.losses, r.ties, r.archetype_id AS deck_id,
           p.player_id, p.member_number
    FROM results r
    JOIN players p ON r.player_id = p.player_id
    WHERE r.tournament_id = ?
    ORDER BY r.placement
  ", params = list(tournament_id))

  if (nrow(results) == 0) return(init_grid_data(8))

  data.frame(
    placement = results$placement,
    player_name = results$player_name,
    points = (results$wins * 3L) + results$ties,
    wins = results$wins,
    losses = results$losses,
    ties = results$ties,
    deck_id = results$deck_id,
    match_status = rep("matched", nrow(results)),
    matched_player_id = results$player_id,
    matched_member_number = results$member_number,
    result_id = results$result_id,
    stringsAsFactors = FALSE
  )
}

# Sync current grid input values back to data frame
sync_grid_inputs <- function(input, grid_data, record_format, prefix) {
  if (is.null(grid_data) || nrow(grid_data) == 0) return(grid_data)

  for (i in seq_len(nrow(grid_data))) {
    player_val <- input[[paste0(prefix, "player_", i)]]
    if (!is.null(player_val)) grid_data$player_name[i] <- player_val

    if (record_format == "points") {
      pts_val <- input[[paste0(prefix, "pts_", i)]]
      if (!is.null(pts_val) && !is.na(pts_val)) grid_data$points[i] <- as.integer(pts_val)
    } else {
      w_val <- input[[paste0(prefix, "w_", i)]]
      if (!is.null(w_val) && !is.na(w_val)) grid_data$wins[i] <- as.integer(w_val)
      l_val <- input[[paste0(prefix, "l_", i)]]
      if (!is.null(l_val) && !is.na(l_val)) grid_data$losses[i] <- as.integer(l_val)
      t_val <- input[[paste0(prefix, "t_", i)]]
      if (!is.null(t_val) && !is.na(t_val)) grid_data$ties[i] <- as.integer(t_val)
    }

    deck_val <- input[[paste0(prefix, "deck_", i)]]
    if (!is.null(deck_val) && nchar(deck_val) > 0 && deck_val != "__REQUEST_NEW__" && !grepl("^pending_", deck_val)) {
      grid_data$deck_id[i] <- as.integer(deck_val)
    }
  }
  grid_data
}

# Render grid UI rows
render_grid_ui <- function(grid_data, record_format, is_release, deck_choices, player_matches, prefix) {
  # Column widths depend on format and release event
  if (is_release) {
    col_widths <- if (record_format == "points") c(1, 1, 8, 2) else c(1, 1, 6, 2, 1, 1)
  } else {
    col_widths <- if (record_format == "points") c(1, 1, 4, 2, 4) else c(1, 1, 3, 1, 1, 1, 4)
  }

  # Header row
  header_cols <- if (is_release) {
    if (record_format == "points") list(div(""), div("#"), div("Player"), div("Pts"))
    else list(div(""), div("#"), div("Player"), div("W"), div("L"), div("T"))
  } else {
    if (record_format == "points") list(div(""), div("#"), div("Player"), div("Pts"), div("Deck"))
    else list(div(""), div("#"), div("Player"), div("W"), div("L"), div("T"), div("Deck"))
  }
  header <- do.call(layout_columns, c(list(col_widths = col_widths, class = "results-header-row"), header_cols))

  # Release event notice
  release_notice <- if (is_release) {
    div(class = "alert alert-info py-2 px-3 mb-3",
        bsicons::bs_icon("info-circle"),
        " Release event \u2014 deck archetype auto-set to UNKNOWN.")
  } else NULL

  # JS event name for delete (use prefix to namespace)
  delete_event <- paste0(prefix, "delete_row")

  # Data rows
  rows <- lapply(seq_len(nrow(grid_data)), function(i) {
    row <- grid_data[i, ]
    place_class <- if (i == 1) "place-1st" else if (i == 2) "place-2nd" else if (i == 3) "place-3rd" else ""

    # Player match badge
    match_info <- player_matches[[as.character(i)]]
    match_badge <- if (!is.null(match_info)) {
      if (match_info$status == "matched") {
        member_text <- if (!is.na(match_info$member_number) && nchar(match_info$member_number) > 0) {
          paste0("#", match_info$member_number)
        } else "(no member #)"
        div(class = "player-match-indicator matched",
            bsicons::bs_icon("check-circle-fill"),
            span(class = "match-label", paste0("Matched ", member_text)))
      } else if (match_info$status == "new") {
        div(class = "player-match-indicator new",
            bsicons::bs_icon("person-plus-fill"),
            span(class = "match-label", "New player"))
      } else NULL
    } else NULL

    # Delete button
    delete_btn <- div(
      class = "upload-result-delete",
      htmltools::tags$button(
        onclick = sprintf("Shiny.setInputValue('%s', %d, {priority: 'event'})", delete_event, i),
        class = "btn btn-sm btn-outline-danger p-0 result-action-btn",
        title = "Remove row",
        shiny::icon("xmark")
      )
    )

    # Placement column
    placement_col <- div(
      class = "upload-result-placement",
      span(class = paste("placement-badge", place_class), grid_ordinal(row$placement)),
      match_badge
    )

    # Player name input
    player_col <- div(textInput(paste0(prefix, "player_", i), NULL, value = row$player_name))

    # Build row based on format and release event
    if (is_release) {
      if (record_format == "points") {
        pts_col <- div(numericInput(paste0(prefix, "pts_", i), NULL, value = row$points, min = 0, max = 99))
        layout_columns(col_widths = col_widths, class = "upload-result-row",
                       delete_btn, placement_col, player_col, pts_col)
      } else {
        w_col <- div(numericInput(paste0(prefix, "w_", i), NULL, value = row$wins, min = 0))
        l_col <- div(numericInput(paste0(prefix, "l_", i), NULL, value = row$losses, min = 0))
        t_col <- div(numericInput(paste0(prefix, "t_", i), NULL, value = row$ties, min = 0))
        layout_columns(col_widths = col_widths, class = "upload-result-row",
                       delete_btn, placement_col, player_col, w_col, l_col, t_col)
      }
    } else {
      current_deck <- if (!is.na(row$deck_id)) as.character(row$deck_id) else ""
      deck_col <- div(selectInput(paste0(prefix, "deck_", i), NULL,
                                  choices = deck_choices, selected = current_deck,
                                  selectize = FALSE))

      if (record_format == "points") {
        pts_col <- div(numericInput(paste0(prefix, "pts_", i), NULL, value = row$points, min = 0, max = 99))
        layout_columns(col_widths = col_widths, class = "upload-result-row",
                       delete_btn, placement_col, player_col, pts_col, deck_col)
      } else {
        w_col <- div(numericInput(paste0(prefix, "w_", i), NULL, value = row$wins, min = 0))
        l_col <- div(numericInput(paste0(prefix, "l_", i), NULL, value = row$losses, min = 0))
        t_col <- div(numericInput(paste0(prefix, "t_", i), NULL, value = row$ties, min = 0))
        layout_columns(col_widths = col_widths, class = "upload-result-row",
                       delete_btn, placement_col, player_col, w_col, l_col, t_col, deck_col)
      }
    }
  })

  tagList(release_notice, header, rows)
}

# Parse pasted spreadsheet text into grid-ready rows
parse_paste_data <- function(text, all_decks) {
  lines <- strsplit(text, "\n")[[1]]
  lines <- lines[nchar(trimws(lines)) > 0]
  if (length(lines) == 0) return(list())

  lapply(lines, function(line) {
    parts <- strsplit(line, "\t")[[1]]
    if (length(parts) == 1) parts <- strsplit(trimws(line), "\\s{2,}")[[1]]
    parts <- trimws(parts)

    name <- parts[1]
    pts <- 0L; w <- 0L; l <- 0L; t_val <- 0L; deck_name <- ""

    if (length(parts) == 2) {
      pts <- suppressWarnings(as.integer(parts[2]))
      if (is.na(pts)) pts <- 0L
    } else if (length(parts) == 3) {
      pts <- suppressWarnings(as.integer(parts[2]))
      if (is.na(pts)) pts <- 0L
      deck_name <- parts[3]
    } else if (length(parts) == 4) {
      w <- suppressWarnings(as.integer(parts[2]))
      l <- suppressWarnings(as.integer(parts[3]))
      t_val <- suppressWarnings(as.integer(parts[4]))
      if (is.na(w)) w <- 0L
      if (is.na(l)) l <- 0L
      if (is.na(t_val)) t_val <- 0L
      pts <- w * 3L + t_val
    } else if (length(parts) >= 5) {
      w <- suppressWarnings(as.integer(parts[2]))
      l <- suppressWarnings(as.integer(parts[3]))
      t_val <- suppressWarnings(as.integer(parts[4]))
      if (is.na(w)) w <- 0L
      if (is.na(l)) l <- 0L
      if (is.na(t_val)) t_val <- 0L
      pts <- w * 3L + t_val
      deck_name <- parts[5]
    }

    # Match deck name
    deck_id <- NA_integer_
    if (nchar(deck_name) > 0 && !is.null(all_decks) && nrow(all_decks) > 0) {
      match_idx <- which(tolower(all_decks$archetype_name) == tolower(deck_name))
      if (length(match_idx) > 0) deck_id <- all_decks$archetype_id[match_idx[1]]
    }

    list(name = name, points = pts, wins = w, losses = l, ties = t_val, deck_id = deck_id)
  })
}

# Build deck choices for grid dropdown (reusable)
build_deck_choices <- function(con) {
  decks <- dbGetQuery(con, "
    SELECT archetype_id, archetype_name FROM deck_archetypes
    WHERE is_active = TRUE ORDER BY archetype_name
  ")
  pending_requests <- dbGetQuery(con, "
    SELECT request_id, deck_name FROM deck_requests
    WHERE status = 'pending' ORDER BY deck_name
  ")

  deck_choices <- c("Unknown" = "")
  deck_choices <- c(deck_choices, "\U2795 Request new deck..." = "__REQUEST_NEW__")
  if (nrow(pending_requests) > 0) {
    pending_choices <- setNames(
      paste0("pending_", pending_requests$request_id),
      paste0("Pending: ", pending_requests$deck_name)
    )
    deck_choices <- c(deck_choices, pending_choices)
  }
  deck_choices <- c(deck_choices, setNames(decks$archetype_id, decks$archetype_name))
  deck_choices
}

# Match a player name against the database and return match info
match_player <- function(name, con) {
  name <- trimws(name)
  if (nchar(name) == 0) return(NULL)

  player <- dbGetQuery(con, "
    SELECT player_id, display_name, member_number
    FROM players WHERE LOWER(display_name) = LOWER(?)
    LIMIT 1
  ", params = list(name))

  if (nrow(player) > 0) {
    list(status = "matched", player_id = player$player_id, member_number = player$member_number)
  } else {
    list(status = "new")
  }
}
```

**Step 2: Source the file in `app.R`**

Find where `R/db_connection.R` is sourced in `app.R` and add `R/admin_grid.R` nearby:

```r
source("R/admin_grid.R")
```

**Step 3: Commit**

```bash
git add R/admin_grid.R app.R
git commit -m "feat: create shared grid module R/admin_grid.R"
```

---

### Task 2: Refactor Enter Results to Use Shared Grid Functions

**Files:**
- Modify: `server/admin-results-server.R`

This task replaces inline code in admin-results-server.R with calls to the shared functions. The `admin_` prefix is used for all input IDs (same as current, so no UI changes needed).

**Step 1: Replace `init_admin_grid` with `init_grid_data`**

At the top of the file (lines 12-26), remove the `init_admin_grid` function and update all calls to use `init_grid_data` from `R/admin_grid.R`.

Search for all occurrences of `init_admin_grid(` and replace with `init_grid_data(`.

**Step 2: Replace `admin_ordinal` with `grid_ordinal`**

Remove the `admin_ordinal` function (lines 403-409). It's now in `R/admin_grid.R` as `grid_ordinal`. There should be no remaining references since the grid rendering will also be replaced.

**Step 3: Replace grid rendering with `render_grid_ui`**

Replace the `output$admin_grid_table` renderUI block (lines 429-589) with:

```r
output$admin_grid_table <- renderUI({
  req(rv$admin_grid_data)

  grid <- rv$admin_grid_data
  record_format <- rv$admin_record_format %||% "points"

  # Check if release event
  is_release <- FALSE
  if (!is.null(rv$active_tournament_id) && !is.null(rv$db_con) && dbIsValid(rv$db_con)) {
    t_info <- dbGetQuery(rv$db_con, "SELECT event_type FROM tournaments WHERE tournament_id = ?",
                         params = list(rv$active_tournament_id))
    if (nrow(t_info) > 0) is_release <- t_info$event_type[1] == "release_event"
  }

  deck_choices <- build_deck_choices(rv$db_con)

  render_grid_ui(grid, record_format, is_release, deck_choices, rv$admin_player_matches, "admin_")
})
```

**Step 4: Replace `sync_admin_grid_inputs` with `sync_grid_inputs`**

Remove the `sync_admin_grid_inputs` function (lines 596-623). Replace all calls throughout the file:

- `sync_admin_grid_inputs()` → `rv$admin_grid_data <- sync_grid_inputs(input, rv$admin_grid_data, rv$admin_record_format %||% "points", "admin_")`

There are ~5 call sites: delete row handler, player blur handler, paste apply handler, deck request submit handler, and submit results handler.

**Step 5: Update delete row handler for `result_id` column**

The delete row handler (lines 625-663) references `admin_delete_row`. Now the shared grid uses `paste0(prefix, "delete_row")` which for the `admin_` prefix is still `admin_delete_row` — no change needed to the event name.

But the blank row appended needs the `result_id` column:

```r
blank_row <- data.frame(
  placement = nrow(grid) + 1,
  player_name = "",
  points = 0L, wins = 0L, losses = 0L, ties = 0L,
  deck_id = NA_integer_,
  match_status = "",
  matched_player_id = NA_integer_,
  matched_member_number = NA_character_,
  result_id = NA_integer_,
  stringsAsFactors = FALSE
)
```

**Step 6: Replace paste parsing with `parse_paste_data`**

In the `paste_apply` observer (lines 765-888), replace the inline parsing logic with:

```r
observeEvent(input$paste_apply, {
  req(rv$admin_grid_data)

  paste_text <- input$paste_data
  if (is.null(paste_text) || nchar(trimws(paste_text)) == 0) {
    notify("No data to paste", type = "warning")
    return()
  }

  rv$admin_grid_data <- sync_grid_inputs(input, rv$admin_grid_data, rv$admin_record_format %||% "points", "admin_")
  grid <- rv$admin_grid_data

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

  # Player matching for all filled rows
  for (idx in seq_len(fill_count)) {
    match_info <- match_player(grid$player_name[idx], rv$db_con)
    if (!is.null(match_info)) {
      rv$admin_player_matches[[as.character(idx)]] <- match_info
      grid$match_status[idx] <- match_info$status
      if (match_info$status == "matched") {
        grid$matched_player_id[idx] <- match_info$player_id
        grid$matched_member_number[idx] <- match_info$member_number
      }
    }
  }
  rv$admin_grid_data <- grid
})
```

**Step 7: Replace inline player matching with `match_player`**

In the `admin_player_blur` observer (lines 683-726), replace the inline DB query + match logic with:

```r
observeEvent(input$admin_player_blur, {
  req(rv$db_con, rv$admin_grid_data)

  info <- input$admin_player_blur
  row_num <- info$row
  name <- trimws(info$name)

  if (is.null(row_num) || is.na(row_num)) return()
  if (row_num < 1 || row_num > nrow(rv$admin_grid_data)) return()

  rv$admin_grid_data <- sync_grid_inputs(input, rv$admin_grid_data, rv$admin_record_format %||% "points", "admin_")

  if (nchar(name) == 0) {
    rv$admin_player_matches[[as.character(row_num)]] <- NULL
    rv$admin_grid_data$match_status[row_num] <- ""
    rv$admin_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$admin_grid_data$matched_member_number[row_num] <- NA_character_
    return()
  }

  match_info <- match_player(name, rv$db_con)
  rv$admin_player_matches[[as.character(row_num)]] <- match_info
  rv$admin_grid_data$match_status[row_num] <- match_info$status
  if (match_info$status == "matched") {
    rv$admin_grid_data$matched_player_id[row_num] <- match_info$player_id
    rv$admin_grid_data$matched_member_number[row_num] <- match_info$member_number
  } else {
    rv$admin_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$admin_grid_data$matched_member_number[row_num] <- NA_character_
  }
})
```

**Step 8: Verify the app sources without errors**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "tryCatch({ source('app.R', local=TRUE); cat('OK') }, error=function(e) cat('ERROR:', e$message))"
```

Expected: No ERROR output. Warnings about date format and package versions are OK.

**Step 9: Commit**

```bash
git add server/admin-results-server.R
git commit -m "refactor: Enter Results uses shared grid functions from R/admin_grid.R"
```

---

### Task 3: Add Grid Section to Edit Tournaments UI

**Files:**
- Modify: `views/admin-tournaments-ui.R`

**Step 1: Add the hidden grid section below the existing layout**

After the closing `layout_columns` and the `.admin-panel` div, but still inside the `admin_tournaments_ui` tagList, add:

```r
  # Edit Results Grid (hidden initially, shown when View/Edit Results is clicked)
  shinyjs::hidden(
    div(
      id = "edit_results_grid_section",
      class = "admin-panel mt-3",

      # Tournament summary bar
      uiOutput("edit_grid_summary_bar"),

      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          div(
            class = "d-flex align-items-center gap-2",
            span("Edit Results"),
            uiOutput("edit_record_format_badge", inline = TRUE)
          ),
          div(
            class = "d-flex align-items-center gap-2",
            uiOutput("edit_filled_count", inline = TRUE),
            actionButton("edit_paste_btn", "Paste from Spreadsheet",
                         class = "btn-sm btn-outline-primary",
                         icon = icon("clipboard"))
          )
        ),
        card_body(
          uiOutput("edit_grid_table")
        )
      ),

      # Bottom navigation
      div(
        class = "d-flex justify-content-between mt-3",
        actionButton("edit_grid_cancel", "Cancel", class = "btn-secondary",
                     icon = icon("xmark")),
        actionButton("edit_grid_save", "Save Changes", class = "btn-primary btn-lg",
                     icon = icon("check"))
      )
    )
  )
```

This goes right before the closing `)` of the `admin_tournaments_ui` tagList.

**Step 2: Commit**

```bash
git add views/admin-tournaments-ui.R
git commit -m "feat: add hidden grid section to Edit Tournaments UI"
```

---

### Task 4: Add Edit Grid Server Logic — Load, Render, Sync

**Files:**
- Modify: `server/admin-tournaments-server.R`
- Modify: `app.R` (add reactive values)

**Step 1: Add reactive values in `app.R`**

Find the reactive values section (around line 950-970) and add:

```r
    edit_grid_data = NULL,
    edit_record_format = "points",
    edit_player_matches = list(),
    edit_deleted_result_ids = c(),
    edit_grid_tournament_id = NULL,
```

**Step 2: Replace the View/Edit Results button handler**

In `admin-tournaments-server.R`, replace the `observeEvent(input$view_edit_results, ...)` handler (lines 508-522) with the grid-loading logic:

```r
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
```

**Step 3: Add grid rendering output**

```r
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
```

**Step 4: Add summary bar, format badge, and filled count outputs**

```r
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

output$edit_record_format_badge <- renderUI({
  format <- rv$edit_record_format %||% "points"
  label <- if (format == "points") "Points mode" else "W-L-T mode"
  span(class = "badge bg-info", label)
})

output$edit_filled_count <- renderUI({
  req(rv$edit_grid_data)
  grid <- rv$edit_grid_data
  filled <- sum(nchar(trimws(grid$player_name)) > 0)
  total <- nrow(grid)
  span(class = "text-muted small", sprintf("Filled: %d/%d", filled, total))
})
```

**Step 5: Add cancel handler**

```r
observeEvent(input$edit_grid_cancel, {
  shinyjs::hide("edit_results_grid_section")
  rv$edit_grid_data <- NULL
  rv$edit_player_matches <- list()
  rv$edit_deleted_result_ids <- c()
  rv$edit_grid_tournament_id <- NULL
})
```

**Step 6: Verify**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "tryCatch({ source('app.R', local=TRUE); cat('OK') }, error=function(e) cat('ERROR:', e$message))"
```

**Step 7: Commit**

```bash
git add server/admin-tournaments-server.R app.R
git commit -m "feat: Edit Tournaments grid load, render, and cancel"
```

---

### Task 5: Add Edit Grid Interactivity — Delete, Player Matching, Paste

**Files:**
- Modify: `server/admin-tournaments-server.R`

**Step 1: Add delete row handler**

```r
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
```

**Step 2: Add player blur matching handler**

```r
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
```

**Step 3: Add paste from spreadsheet handler**

```r
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
```

**Step 4: Add deck request support for edit grid**

```r
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
          textInput("admin_deck_request_name", "Deck Name", placeholder = "e.g., Blue Flare"),
          layout_columns(
            col_widths = c(6, 6),
            selectInput("admin_deck_request_color", "Primary Color",
                        choices = c("Red", "Blue", "Yellow", "Green", "Purple", "Black", "White")),
            selectInput("admin_deck_request_color2", "Secondary Color (optional)",
                        choices = c("None" = "", "Red", "Blue", "Yellow", "Green", "Purple", "Black", "White"))
          ),
          textInput("admin_deck_request_card_id", "Card ID (optional)",
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

  deck_name <- trimws(input$admin_deck_request_name)
  if (nchar(deck_name) == 0) {
    notify("Please enter a deck name", type = "error")
    return()
  }

  primary_color <- input$admin_deck_request_color
  secondary_color <- if (!is.null(input$admin_deck_request_color2) && input$admin_deck_request_color2 != "") {
    input$admin_deck_request_color2
  } else NA_character_

  card_id <- if (!is.null(input$admin_deck_request_card_id) && trimws(input$admin_deck_request_card_id) != "") {
    trimws(input$admin_deck_request_card_id)
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
```

**Step 5: Verify**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "tryCatch({ source('app.R', local=TRUE); cat('OK') }, error=function(e) cat('ERROR:', e$message))"
```

**Step 6: Commit**

```bash
git add server/admin-tournaments-server.R
git commit -m "feat: Edit grid interactivity — delete, player matching, paste, deck requests"
```

---

### Task 6: Add Edit Grid Save Handler (Update/Insert/Delete Diff)

**Files:**
- Modify: `server/admin-tournaments-server.R`

**Step 1: Add the save handler**

This is the key logic that differentiates edit mode from create mode. It diffs the current grid against the original data to determine what to update, insert, and delete.

```r
observeEvent(input$edit_grid_save, {
  req(rv$is_admin, rv$db_con, rv$edit_grid_tournament_id)

  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_")
  grid <- rv$edit_grid_data
  record_format <- rv$edit_record_format %||% "points"
  tournament_id <- rv$edit_grid_tournament_id

  # Get tournament info
  tournament <- dbGetQuery(rv$db_con, "
    SELECT tournament_id, event_type, rounds FROM tournaments WHERE tournament_id = ?
  ", params = list(tournament_id))

  if (nrow(tournament) == 0) {
    notify("Tournament not found", type = "error")
    return()
  }

  rounds <- tournament$rounds
  is_release <- tournament$event_type == "release_event"

  # Get UNKNOWN archetype ID
  unknown_row <- dbGetQuery(rv$db_con, "SELECT archetype_id FROM deck_archetypes WHERE archetype_name = 'UNKNOWN' LIMIT 1")
  unknown_id <- if (nrow(unknown_row) > 0) unknown_row$archetype_id[1] else NA_integer_

  if (is_release && is.na(unknown_id)) {
    notify("UNKNOWN archetype not found in database", type = "error")
    return()
  }

  # Separate filled vs empty rows
  filled_rows <- grid[nchar(trimws(grid$player_name)) > 0, ]

  if (nrow(filled_rows) == 0) {
    notify("No results to save. Enter at least one player name.", type = "warning")
    return()
  }

  tryCatch({
    update_count <- 0L
    insert_count <- 0L
    delete_count <- 0L

    # 1. DELETE: rows that were deleted via X button
    for (rid in rv$edit_deleted_result_ids) {
      dbExecute(rv$db_con, "DELETE FROM results WHERE result_id = ?", params = list(rid))
      delete_count <- delete_count + 1L
    }

    # 2. DELETE: original rows that are now empty (user cleared the name)
    empty_rows <- grid[nchar(trimws(grid$player_name)) == 0 & !is.na(grid$result_id), ]
    for (idx in seq_len(nrow(empty_rows))) {
      dbExecute(rv$db_con, "DELETE FROM results WHERE result_id = ?",
                params = list(empty_rows$result_id[idx]))
      delete_count <- delete_count + 1L
    }

    # 3. UPDATE or INSERT filled rows
    max_result_id <- dbGetQuery(rv$db_con, "SELECT COALESCE(MAX(result_id), 0) as max_id FROM results")$max_id

    for (idx in seq_len(nrow(filled_rows))) {
      row <- filled_rows[idx, ]
      name <- trimws(row$player_name)

      # Resolve player
      player <- dbGetQuery(rv$db_con, "
        SELECT player_id FROM players WHERE LOWER(display_name) = LOWER(?) LIMIT 1
      ", params = list(name))

      if (nrow(player) > 0) {
        player_id <- player$player_id
      } else {
        max_pid <- dbGetQuery(rv$db_con, "SELECT COALESCE(MAX(player_id), 0) as max_id FROM players")$max_id
        player_id <- max_pid + 1
        dbExecute(rv$db_con, "INSERT INTO players (player_id, display_name) VALUES (?, ?)",
                  params = list(player_id, name))
      }

      # Convert record
      if (record_format == "points") {
        pts <- row$points
        wins <- pts %/% 3L
        ties <- pts %% 3L
        losses <- max(0L, rounds - wins - ties)
      } else {
        wins <- row$wins
        losses <- row$losses
        ties <- row$ties
      }

      # Resolve deck
      pending_deck_request_id <- NA_integer_
      if (is_release) {
        archetype_id <- unknown_id
      } else {
        deck_input <- input[[paste0("edit_deck_", row$placement)]]
        if (is.null(deck_input) || nchar(deck_input) == 0 || deck_input == "__REQUEST_NEW__") {
          archetype_id <- unknown_id
        } else if (grepl("^pending_", deck_input)) {
          pending_deck_request_id <- as.integer(sub("^pending_", "", deck_input))
          archetype_id <- unknown_id
        } else {
          archetype_id <- as.integer(deck_input)
        }
      }

      if (!is.na(row$result_id)) {
        # UPDATE existing result
        dbExecute(rv$db_con, "
          UPDATE results
          SET player_id = ?, archetype_id = ?, pending_deck_request_id = ?,
              placement = ?, wins = ?, losses = ?, ties = ?,
              updated_at = CURRENT_TIMESTAMP
          WHERE result_id = ?
        ", params = list(player_id, archetype_id, pending_deck_request_id,
                         row$placement, wins, losses, ties, row$result_id))
        update_count <- update_count + 1L
      } else {
        # INSERT new result
        max_result_id <- max_result_id + 1
        dbExecute(rv$db_con, "
          INSERT INTO results (result_id, tournament_id, player_id, archetype_id,
                               pending_deck_request_id, placement, wins, losses, ties)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ", params = list(max_result_id, tournament_id, player_id, archetype_id,
                         pending_deck_request_id, row$placement, wins, losses, ties))
        insert_count <- insert_count + 1L
      }
    }

    # Recalculate ratings
    recalculate_ratings_cache(rv$db_con)
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

    # Build summary message
    parts <- c()
    if (update_count > 0) parts <- c(parts, sprintf("%d updated", update_count))
    if (insert_count > 0) parts <- c(parts, sprintf("%d added", insert_count))
    if (delete_count > 0) parts <- c(parts, sprintf("%d removed", delete_count))
    msg <- paste("Results saved!", paste(parts, collapse = ", "))

    notify(msg, type = "message", duration = 5)

    # Collapse grid
    shinyjs::hide("edit_results_grid_section")
    rv$edit_grid_data <- NULL
    rv$edit_player_matches <- list()
    rv$edit_deleted_result_ids <- c()
    rv$edit_grid_tournament_id <- NULL

    # Refresh the tournament list table
    rv$admin_data_refresh <- (rv$admin_data_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error saving results:", e$message), type = "error")
  })
})
```

**Step 2: Verify**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "tryCatch({ source('app.R', local=TRUE); cat('OK') }, error=function(e) cat('ERROR:', e$message))"
```

**Step 3: Commit**

```bash
git add server/admin-tournaments-server.R
git commit -m "feat: Edit grid save handler with update/insert/delete diff"
```

---

### Task 7: Remove Old Modal-Based Results Editor

**Files:**
- Modify: `server/admin-tournaments-server.R`

**Step 1: Remove the modal-based code**

Delete these sections from `admin-tournaments-server.R`:

1. `show_results_editor()` helper function (lines ~373-437)
2. `show_edit_result_modal()` helper function (lines ~440-478)
3. `show_delete_result_confirm()` helper function (lines ~481-494)
4. `output$results_modal_summary` renderUI (lines ~525-544)
5. `output$modal_results_table` renderReactable (lines ~547-602)
6. All Edit/Delete result handlers (lines ~609-756):
   - `observeEvent(input$modal_result_clicked, ...)`
   - `observeEvent(input$modal_save_edit_result, ...)`
   - `observeEvent(input$modal_cancel_edit_result, ...)`
   - `observeEvent(input$modal_delete_result, ...)`
   - `observeEvent(input$modal_cancel_delete_result, ...)`
   - `observeEvent(input$modal_confirm_delete_result, ...)`
7. All Add New Result handlers (lines ~763-825):
   - `observeEvent(input$modal_add_result, ...)`
   - `observeEvent(input$modal_cancel_new_result, ...)`
   - `observeEvent(input$modal_save_new_result, ...)`

Keep everything else (tournament edit form, update handler, delete tournament handler, scene indicator).

**Step 2: Remove unused reactive values from `app.R`**

Remove `modal_tournament_id` and `modal_results_refresh` from the reactive values section if they are not used elsewhere.

**Step 3: Verify**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "tryCatch({ source('app.R', local=TRUE); cat('OK') }, error=function(e) cat('ERROR:', e$message))"
```

**Step 4: Commit**

```bash
git add server/admin-tournaments-server.R app.R
git commit -m "refactor: remove old modal-based results editor from Edit Tournaments"
```

---

### Task 8: Hide Grid on Tournament Deselect and Sync State

**Files:**
- Modify: `server/admin-tournaments-server.R`

**Step 1: Hide grid when tournament selection changes or form is cancelled**

Add to the cancel_edit_tournament handler:

```r
observeEvent(input$cancel_edit_tournament, {
  # ... existing reset code ...
  shinyjs::hide("edit_results_grid_section")
  rv$edit_grid_data <- NULL
  rv$edit_player_matches <- list()
  rv$edit_deleted_result_ids <- c()
  rv$edit_grid_tournament_id <- NULL
}, priority = -1)
```

Also hide the grid when a different tournament is clicked (add to the existing click handler):

```r
# In the existing admin_tournament_list_clicked handler, add:
shinyjs::hide("edit_results_grid_section")
rv$edit_grid_data <- NULL
rv$edit_player_matches <- list()
rv$edit_grid_tournament_id <- NULL
```

**Step 2: Hide grid after tournament deletion**

Add to the delete confirmation handler to also hide the grid section.

**Step 3: Verify**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "tryCatch({ source('app.R', local=TRUE); cat('OK') }, error=function(e) cat('ERROR:', e$message))"
```

**Step 4: Commit**

```bash
git add server/admin-tournaments-server.R
git commit -m "fix: hide edit grid on tournament deselect, cancel, and delete"
```

---

### Task 9: Update Help Text and Final Cleanup

**Files:**
- Modify: `views/admin-tournaments-ui.R`

**Step 1: Update the help text**

Change the info hint box text from:
```
"Select a tournament from the list to edit details or manage results. Use 'View/Edit Results' to modify individual placements."
```
To:
```
"Select a tournament from the list to edit details or manage results. Use 'View/Edit Results' to open the results grid for bulk editing."
```

**Step 2: Verify full app loads**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "tryCatch({ source('app.R', local=TRUE); cat('OK') }, error=function(e) cat('ERROR:', e$message))"
```

**Step 3: Commit**

```bash
git add views/admin-tournaments-ui.R
git commit -m "chore: update Edit Tournaments help text for grid-based editing"
```
