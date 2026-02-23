# ADM2: Enter Results & Submit Results UX Polish — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bring visual and functional parity between admin Enter Results and public Submit Results tabs — shared grid, searchable deck dropdown, member # column, validation fixes, and OCR quality checks.

**Architecture:** Extend the shared grid module (`R/admin_grid.R`) with member #, mode parameter, and selectize dropdown. Migrate the public Submit Results Step 2 from its custom inline rendering to the shared grid. Add independent fixes (event types, summary bars, validation) in parallel.

**Tech Stack:** R Shiny, bslib layout_columns, shinyjs, selectizeInput, CSS

**Design Doc:** `docs/plans/2026-02-23-enter-submit-results-ux-design.md`

---

## Key Data Structures

Before implementing, understand these two data frames that must be reconciled:

**Admin grid (`rv$admin_grid_data`):**
```
placement, player_name, points, wins, losses, ties, deck_id,
match_status, matched_player_id, matched_member_number, result_id
```

**Submit OCR results (`rv$submit_ocr_results`):**
```
placement, username, member_number, points, wins, losses, ties,
deck_id, matched_player_id, match_status, matched_player_name
```

Column name differences: `player_name` vs `username`, `matched_member_number` vs `member_number`. The admin grid stores match info in a separate `rv$admin_player_matches` list; submit stores it inline. Task 4 bridges this gap.

---

## Task 1: Add Member # Column to Shared Grid

**Files:**
- Modify: `R/admin_grid.R` — `init_grid_data()`, `load_grid_from_results()`, `sync_grid_inputs()`, `render_grid_ui()`

This task adds a `member_number` column to the shared grid data frame and renders it as a text input in the grid UI. The admin Enter Results tab gets the column too (blank by default, optional).

**Step 1: Add `member_number` to `init_grid_data()`**

In `R/admin_grid.R:19-34`, add `member_number` to the data frame:

```r
init_grid_data <- function(player_count) {
  data.frame(
    placement = seq_len(player_count),
    player_name = rep("", player_count),
    member_number = rep("", player_count),
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
```

**Step 2: Add `member_number` to `load_grid_from_results()`**

In `R/admin_grid.R:42-71`, the function already queries `p.member_number` and stores it as `matched_member_number`. Add `member_number` column that copies from it:

```r
  data.frame(
    placement = rows$placement,
    player_name = rows$display_name,
    member_number = ifelse(is.na(rows$member_number), "", rows$member_number),
    points = as.integer((rows$wins * 3L) + rows$ties),
    wins = as.integer(rows$wins),
    losses = as.integer(rows$losses),
    ties = as.integer(rows$ties),
    deck_id = as.integer(rows$archetype_id),
    match_status = rep("matched", nrow(rows)),
    matched_player_id = as.integer(rows$player_id),
    matched_member_number = as.character(rows$member_number),
    result_id = as.integer(rows$result_id),
    stringsAsFactors = FALSE
  )
```

**Step 3: Sync `member_number` in `sync_grid_inputs()`**

In `R/admin_grid.R:82-109`, add member number sync after player name:

```r
    member_val <- input[[paste0(prefix, "member_", i)]]
    if (!is.null(member_val)) grid_data$member_number[i] <- member_val
```

**Step 4: Add member # column to `render_grid_ui()`**

In `R/admin_grid.R:122-254`, add the member # column between player and points/W-L-T columns. Update column widths and add the input.

For non-release events:
- Points mode: `c(1, 1, 3, 2, 2, 3)` — delete, #, player, member, pts, deck
- WLT mode: `c(1, 1, 2, 2, 1, 1, 1, 3)` — delete, #, player, member, W, L, T, deck

For release events:
- Points mode: `c(1, 1, 5, 2, 2)` — delete, #, player, member, pts (wider player since no deck)
- WLT mode: `c(1, 1, 4, 2, 2, 1, 1)` — delete, #, player, member, W, L, T

Add the member # header label and input:
```r
    # Member number input
    member_col <- div(
      textInput(paste0(prefix, "member_", i), NULL,
                value = if (!is.na(row$member_number)) row$member_number else "",
                placeholder = "0000...")
    )
```

Insert `member_col` after `player_col` in all layout_columns calls.

**Step 5: Update admin delete row handler**

In `server/admin-results-server.R:437-447`, add `member_number` to the blank row appended after deletion:

```r
    blank_row <- data.frame(
      placement = nrow(grid) + 1,
      player_name = "",
      member_number = "",
      points = 0L, wins = 0L, losses = 0L, ties = 0L,
      deck_id = NA_integer_,
      match_status = "",
      matched_player_id = NA_integer_,
      matched_member_number = NA_character_,
      result_id = NA_integer_,
      stringsAsFactors = FALSE
    )
```

**Step 6: Verify**

Run: `shiny::runApp()`
- Go to Enter Results → create tournament → verify grid has Member # column
- Verify column header shows "Member #"
- Verify typing in member # field works
- Verify Edit Tournaments grid also shows Member # (it uses same shared grid)

**Step 7: Commit**

```bash
git add R/admin_grid.R server/admin-results-server.R
git commit -m "feat(grid): add member # column to shared grid"
```

---

## Task 2: Add Mode Parameter (entry/review) to Shared Grid

**Files:**
- Modify: `R/admin_grid.R` — `render_grid_ui()` signature and row CSS class
- Modify: `www/custom.css` — add `.ocr-populated` styles

This adds a `mode` parameter to `render_grid_ui()` and a corresponding `ocr_rows` vector. In "review" mode, rows that were OCR-populated get a CSS class for subtle visual distinction.

**Step 1: Update `render_grid_ui()` signature**

In `R/admin_grid.R:122-123`, add `mode = "entry"` and `ocr_rows = NULL` parameters:

```r
render_grid_ui <- function(grid_data, record_format, is_release, deck_choices,
                           player_matches, prefix, mode = "entry", ocr_rows = NULL) {
```

`ocr_rows` is an integer vector of row indices that were populated by OCR. Only used when `mode = "review"`.

**Step 2: Apply CSS class to OCR-populated rows**

In the row-building `lapply` inside `render_grid_ui()`, add `ocr-populated` class to the row's `layout_columns` class when the row is OCR-populated:

```r
    # Row CSS class — add ocr-populated for review mode
    row_class <- "upload-result-row"
    if (mode == "review" && !is.null(ocr_rows) && i %in% ocr_rows) {
      row_class <- "upload-result-row grid-row ocr-populated"
    } else if (mode == "review") {
      row_class <- "upload-result-row grid-row"
    }
```

Use `row_class` instead of `"upload-result-row"` in all `layout_columns(class = ...)` calls for data rows.

**Step 3: Add CSS for review mode visual distinction**

In `www/custom.css`, add to the admin grid section:

```css
/* Review mode: OCR-populated rows have subtle background */
.grid-row.ocr-populated input,
.grid-row.ocr-populated select,
.grid-row.ocr-populated .selectize-input {
  background-color: rgba(var(--bs-info-rgb), 0.05);
  border-color: rgba(var(--bs-info-rgb), 0.2);
}
```

**Step 4: Verify**

Run: `shiny::runApp()`
- Enter Results still works normally (mode defaults to "entry", no visual change)
- Edit Tournaments still works (same default)

**Step 5: Commit**

```bash
git add R/admin_grid.R www/custom.css
git commit -m "feat(grid): add mode parameter with review mode CSS"
```

---

## Task 3: Switch Deck Dropdown to selectizeInput

**Files:**
- Modify: `R/admin_grid.R` — `render_grid_ui()` deck column

Replace `selectInput(..., selectize = FALSE)` with `selectizeInput()` in the shared grid. This enables type-to-filter search for deck selection.

**Step 1: Change selectInput to selectizeInput**

In `R/admin_grid.R`, find the deck column construction (around line 232-237):

```r
      current_deck <- if (!is.na(row$deck_id)) as.character(row$deck_id) else ""
      deck_col <- div(
        selectInput(paste0(prefix, "deck_", i), NULL,
                    choices = deck_choices, selected = current_deck,
                    selectize = FALSE)
      )
```

Replace with:

```r
      current_deck <- if (!is.na(row$deck_id)) as.character(row$deck_id) else ""
      deck_col <- div(
        selectizeInput(paste0(prefix, "deck_", i), NULL,
                       choices = deck_choices, selected = current_deck,
                       options = list(placeholder = "Search deck..."))
      )
```

**Step 2: Verify**

Run: `shiny::runApp()`
- Enter Results → create tournament → verify deck dropdown is now searchable
- Type "blue" and verify it filters to decks containing "blue"
- Verify "Request new deck..." option still works
- Verify "Pending:" deck requests still appear
- Verify Edit Tournaments grid also has searchable dropdown

**Step 3: Commit**

```bash
git add R/admin_grid.R
git commit -m "feat(grid): switch deck dropdown to searchable selectizeInput"
```

---

## Task 4: Sync Event Types to Constant

**Files:**
- Modify: `views/submit-ui.R:79-85`

Replace the hardcoded event type list with the shared `EVENT_TYPES` constant.

**Step 1: Replace hardcoded choices**

In `views/submit-ui.R:79-85`, find:

```r
                  selectInput("submit_event_type", "Event Type",
                              choices = c("Select..." = "",
                                          "Locals" = "locals",
                                          "Evo Cup" = "evo_cup",
                                          "Store Championship" = "store_championship",
                                          "Regional" = "regional",
                                          "Online" = "online"),
                              selectize = FALSE),
```

Replace with:

```r
                  selectInput("submit_event_type", "Event Type",
                              choices = c("Select..." = "", EVENT_TYPES),
                              selectize = FALSE),
```

This adds the missing event types: "Regulation Battle", "Release Event", "Other". It also fixes the label inconsistencies (e.g., "Evo Cup" → "Evolution Cup", "Regional" → "Regionals").

**Step 2: Verify**

Run: `shiny::runApp()`
- Navigate to Upload Results tab → check Event Type dropdown
- Verify all event types match what's in Enter Results (admin)
- Verify "Release Event" appears as an option

**Step 3: Commit**

```bash
git add views/submit-ui.R
git commit -m "fix(submit): sync event types to shared EVENT_TYPES constant"
```

---

## Task 5: Add Format to Both Summary Bars

**Files:**
- Modify: `server/admin-results-server.R:355-379` — `tournament_summary_bar`
- Modify: `server/public-submit-server.R:455-501` — `submit_summary_banner`

Both summary bars currently omit the format/set. Add it.

**Step 1: Add format to admin summary bar**

In `server/admin-results-server.R:359-364`, add `t.format` to the SQL query:

```r
  info <- dbGetQuery(rv$db_con, "
    SELECT s.name as store_name, t.event_date, t.event_type, t.format, t.player_count
    FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = ?
  ", params = list(rv$active_tournament_id))
```

Then in the div (lines 368-378), add a format item after event_type:

```r
    span(class = "summary-divider", "|"),
    span(class = "summary-item", info$event_type),
    if (!is.null(info$format) && !is.na(info$format) && nchar(info$format) > 0) tagList(
      span(class = "summary-divider", "|"),
      span(class = "summary-item", info$format)
    ),
    span(class = "summary-divider", "|"),
```

Note: The query already includes `t.format` — just needs the UI element added.

**Step 2: Fix format display in submit summary banner**

In `server/public-submit-server.R:489-491`, the banner currently shows `input$submit_format` which is the format_id, not the display name. Fix it to look up the format name:

```r
  # Get format name
  format_name <- input$submit_format
  if (!is.null(input$submit_format) && input$submit_format != "") {
    fmt <- safe_query(rv$db_con, "SELECT display_name FROM formats WHERE format_id = ?",
                      params = list(input$submit_format))
    if (nrow(fmt) > 0) format_name <- fmt$display_name[1]
  }
```

Then use `format_name` in the banner div instead of `input$submit_format`.

Also add `event_type` to the submit summary banner — it's currently missing. Add between date and format:

```r
      div(class = "summary-item",
          bsicons::bs_icon("tag"),
          span(input$submit_event_type)),
      div(class = "summary-item",
          bsicons::bs_icon("collection"),
          span(format_name)),
```

**Step 3: Verify**

Run: `shiny::runApp()`
- Enter Results → create tournament → verify summary bar shows format
- Upload Results → process OCR → verify summary bar shows format name (not ID)

**Step 4: Commit**

```bash
git add server/admin-results-server.R server/public-submit-server.R
git commit -m "feat(summary): add format and event type to both summary bars"
```

---

## Task 6: Enter Results Validation + Form Reset

**Files:**
- Modify: `server/admin-results-server.R:56-163` — create tournament handler

**Step 1: Add event type validation**

In `server/admin-results-server.R:56-98`, after the date validation block (line 86-87), add:

```r
  # Event type validation
  if (is.null(event_type) || nchar(trimws(event_type)) == 0) {
    show_field_error(session, "tournament_type")
    notify("Please select an event type", type = "error")
    return()
  }

  # Format validation
  if (is.null(format) || nchar(trimws(format)) == 0) {
    show_field_error(session, "tournament_format")
    notify("Please select a format", type = "error")
    return()
  }
```

**Step 2: Clear form fields after successful submit**

In `server/admin-results-server.R:795-813`, after the reset block (lines 803-808), add form field resets:

```r
    # Reset to Step 1
    rv$active_tournament_id <- NULL
    rv$wizard_step <- 1
    rv$current_results <- data.frame()
    rv$admin_grid_data <- NULL
    rv$admin_player_matches <- list()

    # Clear Step 1 form fields
    updateSelectInput(session, "tournament_store", selected = "")
    updateDateInput(session, "tournament_date", value = NA)
    updateSelectInput(session, "tournament_type", selected = "")
    updateSelectInput(session, "tournament_format", selected = "")
    updateNumericInput(session, "tournament_players", value = 8)
    updateNumericInput(session, "tournament_rounds", value = 3)
    updateRadioButtons(session, "admin_record_format", selected = "points")
```

**Step 3: Verify**

Run: `shiny::runApp()`
- Enter Results → try to create tournament with blank event type → verify error shown
- Try with blank format → verify error shown
- Fill all fields, create tournament, enter results, submit → verify form resets to empty state

**Step 4: Commit**

```bash
git add server/admin-results-server.R
git commit -m "fix(admin): add event type/format validation and clear form after submit"
```

---

## Task 7: OCR Output Validation

**Files:**
- Modify: `server/public-submit-server.R:216-232` — after OCR processing, before step 2 transition

Add quality checks on OCR parse results to prevent bad data from reaching the review grid.

**Step 1: Add validation after OCR combines results**

In `server/public-submit-server.R`, after `removeModal()` on line 214 and the `length(all_results) == 0` check that ends on line 232, add validation before the deduplication section (before line 234):

The existing `length(all_results) == 0` block already handles the "0 players" case with a good error message. Add a quality warning for low-parse-count scenarios after `combined <- do.call(rbind, all_results)` (line 235):

```r
  # Quality validation: warn if very few players found
  raw_count <- nrow(combined)
  has_valid_members <- any(!is.na(combined$member_number) & combined$member_number != "" &
                           !grepl("^GUEST", combined$member_number, ignore.case = TRUE))

  if (raw_count < (total_players * 0.5) && !has_valid_members) {
    # Low confidence parse — show warning modal with option to proceed or re-upload
    showModal(modalDialog(
      title = tagList(bsicons::bs_icon("exclamation-triangle-fill", class = "text-warning"), " Low Confidence Results"),
      div(
        p(sprintf("Only %d of %d expected players could be read from the screenshot(s).", raw_count, total_players)),
        p("This might mean:"),
        tags$ul(
          tags$li("The screenshot doesn't show Bandai TCG+ standings"),
          tags$li("The image is too blurry or cropped"),
          tags$li("The standings span multiple pages (upload all screenshots)")
        ),
        p("You can proceed and fill in the rest manually, or go back and try different screenshots.")
      ),
      footer = tagList(
        actionButton("ocr_proceed_anyway", "Proceed Anyway", class = "btn-warning"),
        actionButton("ocr_reupload", "Re-upload", class = "btn-primary")
      ),
      easyClose = FALSE
    ))
    # Store combined for if they click "proceed anyway"
    rv$ocr_pending_combined <- combined
    return()
  }
```

**Step 2: Add handlers for the quality warning modal**

After the OCR processing handler, add:

```r
# Handle "Proceed Anyway" from OCR quality warning
observeEvent(input$ocr_proceed_anyway, {
  removeModal()
  # Resume OCR flow with the stored combined results
  combined <- rv$ocr_pending_combined
  rv$ocr_pending_combined <- NULL
  if (is.null(combined)) return()

  # Continue with the rest of the OCR processing flow
  # (This is the same code from after the quality check in the main handler)
  # Set a flag to trigger continuation
  rv$ocr_continue_combined <- combined
})

# Handle "Re-upload" from OCR quality warning
observeEvent(input$ocr_reupload, {
  removeModal()
  rv$ocr_pending_combined <- NULL
  # User stays on step 1 — they can upload new screenshots
})
```

**Important implementation note:** Because the OCR processing flow is long (deduplication, padding, player matching, step transition), the cleanest approach is to extract the post-validation processing into a helper function that both the main handler and the "proceed anyway" handler can call. Create:

```r
# Helper: complete OCR processing after validation passes
process_ocr_results <- function(combined, total_players, total_rounds, parsed_count) {
  # ... deduplication, padding, player matching, step transition ...
}
```

Move lines 238-443 of the OCR handler into this helper. Call it from both the main handler (when validation passes) and the `ocr_proceed_anyway` handler.

**Step 3: Add reactive values**

At the top of `server/public-submit-server.R`, add:

```r
rv$ocr_pending_combined <- NULL
```

**Step 4: Verify**

Run: `shiny::runApp()`
- Upload a non-standings screenshot → verify warning modal appears
- Click "Re-upload" → verify returns to step 1
- Click "Proceed Anyway" → verify proceeds to step 2 with whatever was parsed
- Upload a valid standings screenshot → verify no warning, proceeds normally

**Step 5: Commit**

```bash
git add server/public-submit-server.R
git commit -m "feat(submit): add OCR output validation with quality warning"
```

---

## Task 8: Migrate Submit Results Step 2 to Shared Grid

**Files:**
- Modify: `server/public-submit-server.R` — grid rendering, sync, delete handler, reject match, deck request
- Modify: `views/submit-ui.R` — card header (add paste button, filled count)
- Modify: `R/admin_grid.R` — small adjustments if needed

This is the largest task. It replaces the custom inline grid in `public-submit-server.R` with calls to the shared grid module.

### Preparation: Understand the column mapping

The submit OCR results data frame uses different column names from the shared grid. The migration needs to either:
- **Option A**: Rename OCR columns to match grid format at OCR time
- **Option B**: Keep OCR columns and add an adapter

**Recommended: Option A** — rename columns when OCR results are finalized. This keeps the shared grid clean.

### Sub-step 8a: Add adapter functions

**Step 1: Create `ocr_to_grid_data()` helper**

In `R/admin_grid.R`, add a helper that converts OCR results into the shared grid data frame format:

```r
# -----------------------------------------------------------------------------
# ocr_to_grid_data: Convert OCR results data frame to shared grid format
# Maps column names: username → player_name, etc.
# Returns grid-compatible data frame
# -----------------------------------------------------------------------------
ocr_to_grid_data <- function(ocr_results) {
  data.frame(
    placement = ocr_results$placement,
    player_name = ocr_results$username,
    member_number = ifelse(is.na(ocr_results$member_number), "", ocr_results$member_number),
    points = as.integer(ocr_results$points),
    wins = as.integer(ocr_results$wins),
    losses = as.integer(ocr_results$losses),
    ties = as.integer(ocr_results$ties),
    deck_id = if ("deck_id" %in% names(ocr_results)) ocr_results$deck_id else rep(NA_integer_, nrow(ocr_results)),
    match_status = ocr_results$match_status,
    matched_player_id = ocr_results$matched_player_id,
    matched_member_number = rep(NA_character_, nrow(ocr_results)),
    result_id = rep(NA_integer_, nrow(ocr_results)),
    stringsAsFactors = FALSE
  )
}
```

**Step 2: Create `grid_to_submit_data()` helper**

Also in `R/admin_grid.R`, add the reverse conversion for when submitting:

```r
# -----------------------------------------------------------------------------
# grid_to_submit_data: Convert grid data frame back to submit format
# Used by Submit Results to read grid state before submission
# -----------------------------------------------------------------------------
grid_to_submit_data <- function(grid_data, matched_player_names = NULL) {
  data.frame(
    placement = grid_data$placement,
    username = grid_data$player_name,
    member_number = grid_data$member_number,
    points = grid_data$points,
    wins = grid_data$wins,
    losses = grid_data$losses,
    ties = grid_data$ties,
    deck_id = grid_data$deck_id,
    matched_player_id = grid_data$matched_player_id,
    match_status = grid_data$match_status,
    matched_player_name = if (!is.null(matched_player_names)) matched_player_names
                          else rep(NA_character_, nrow(grid_data)),
    stringsAsFactors = FALSE
  )
}
```

### Sub-step 8b: Add new reactive values for submit grid

**Step 3: Add submit grid reactive values**

In `server/public-submit-server.R`, at the top where reactive values are initialized, add:

```r
rv$submit_grid_data <- NULL
rv$submit_player_matches <- list()
rv$submit_record_format <- "points"  # Public submit always uses points
rv$submit_ocr_row_indices <- NULL    # Which rows were OCR-populated (for review mode CSS)
rv$submit_matched_player_names <- NULL  # Preserve matched_player_name for display
```

### Sub-step 8c: Convert OCR results to grid format

**Step 4: After OCR processing, convert to grid format**

In the OCR processing handler, after player matching is complete and before the step 2 transition, convert the OCR results:

Replace the lines that set `rv$submit_ocr_results <- combined` with:

```r
  # Track which rows were populated by OCR (non-blank username)
  ocr_rows <- which(nchar(trimws(combined$username)) > 0)

  # Convert to shared grid format
  rv$submit_grid_data <- ocr_to_grid_data(combined)
  rv$submit_ocr_row_indices <- ocr_rows
  rv$submit_record_format <- "points"

  # Build player matches list from OCR match data (for match badges in grid)
  matches_list <- list()
  for (i in seq_len(nrow(combined))) {
    if (combined$match_status[i] == "matched") {
      matches_list[[as.character(i)]] <- list(
        status = "matched",
        player_id = combined$matched_player_id[i],
        member_number = combined$member_number[i]
      )
    } else if (combined$match_status[i] == "possible") {
      matches_list[[as.character(i)]] <- list(
        status = "matched",  # Grid UI only shows matched/new, so treat possible as matched
        player_id = combined$matched_player_id[i],
        member_number = combined$member_number[i]
      )
    } else if (nchar(trimws(combined$username[i])) > 0) {
      matches_list[[as.character(i)]] <- list(status = "new")
    }
  }
  rv$submit_player_matches <- matches_list

  # Preserve matched_player_name for match summary badges and submission
  rv$submit_matched_player_names <- combined$matched_player_name

  # Keep parsed/total for summary
  rv$submit_parsed_count <- parsed_count
  rv$submit_total_players <- total_players
```

Also keep `rv$submit_ocr_results <- combined` for backward compatibility with the match summary badges and submission handler.

### Sub-step 8d: Replace custom grid rendering with shared grid

**Step 5: Replace `output$submit_results_table`**

In `server/public-submit-server.R`, replace the entire `output$submit_results_table <- renderUI({...})` block (lines 619-757) with:

```r
output$submit_results_table <- renderUI({
  req(rv$submit_grid_data)

  # Re-render when deck requests change
  rv$submit_refresh_trigger

  grid <- rv$submit_grid_data
  deck_choices <- build_deck_choices(rv$db_con)

  render_grid_ui(
    grid_data = grid,
    record_format = "points",
    is_release = FALSE,
    deck_choices = deck_choices,
    player_matches = rv$submit_player_matches,
    prefix = "submit_",
    mode = "review",
    ocr_rows = rv$submit_ocr_row_indices
  )
})
```

**Step 6: Add filled count badge**

In `server/public-submit-server.R`, add:

```r
output$submit_filled_count <- renderUI({
  req(rv$submit_grid_data)
  grid <- rv$submit_grid_data
  filled <- sum(nchar(trimws(grid$player_name)) > 0)
  total <- nrow(grid)
  span(class = "text-muted small", sprintf("Filled: %d/%d", filled, total))
})
```

### Sub-step 8e: Update the card header in submit-ui.R

**Step 7: Update card header to match admin layout**

In `views/submit-ui.R:172-177`, replace the simple card header:

```r
            card(
              class = "mt-3",
              card_header("Player Results"),
```

With:

```r
            card(
              class = "mt-3",
              card_header(
                class = "d-flex justify-content-between align-items-center",
                div(
                  class = "d-flex align-items-center gap-2",
                  span("Player Results"),
                  span(class = "badge bg-info", "Points mode")
                ),
                div(
                  class = "d-flex align-items-center gap-2",
                  uiOutput("submit_filled_count", inline = TRUE),
                  actionButton("submit_paste_btn", "Paste from Spreadsheet",
                               class = "btn-sm btn-outline-primary",
                               icon = icon("clipboard"))
                )
              ),
```

### Sub-step 8f: Replace custom sync and delete handlers

**Step 8: Replace `sync_submit_inputs()` with shared `sync_grid_inputs()`**

Delete the custom `sync_submit_inputs()` function (lines 547-566) and the custom `ordinal()` function (lines 537-543).

Replace all calls to `sync_submit_inputs()` with:

```r
rv$submit_grid_data <- sync_grid_inputs(input, rv$submit_grid_data, "points", "submit_")
```

**Step 9: Replace the delete row handler**

Replace the custom `observeEvent(input$submit_delete_row, {...})` block (lines 568-616) with one that uses the shared grid data:

```r
observeEvent(input$submit_delete_row, {
  req(rv$submit_grid_data)

  row_idx <- as.integer(input$submit_delete_row)
  total_players <- rv$submit_total_players

  if (is.null(row_idx) || row_idx < 1 || row_idx > nrow(rv$submit_grid_data)) return()

  # Sync current inputs before mutation
  rv$submit_grid_data <- sync_grid_inputs(input, rv$submit_grid_data, "points", "submit_")
  grid <- rv$submit_grid_data

  # Remove the row
  grid <- grid[-row_idx, ]

  # Pad with blank row to maintain total_players count
  if (nrow(grid) < total_players) {
    blank_row <- data.frame(
      placement = nrow(grid) + 1,
      player_name = "",
      member_number = "",
      points = 0L, wins = 0L, losses = 0L, ties = 0L,
      deck_id = NA_integer_,
      match_status = "new",
      matched_player_id = NA_integer_,
      matched_member_number = NA_character_,
      result_id = NA_integer_,
      stringsAsFactors = FALSE
    )
    grid <- rbind(grid, blank_row)
  }

  # Re-assign placements
  grid$placement <- seq_len(nrow(grid))

  # Shift player matches
  new_matches <- list()
  for (j in seq_len(nrow(grid))) {
    old_idx <- if (j < row_idx) j else j + 1
    if (!is.null(rv$submit_player_matches[[as.character(old_idx)]])) {
      new_matches[[as.character(j)]] <- rv$submit_player_matches[[as.character(old_idx)]]
    }
  }
  rv$submit_player_matches <- new_matches

  # Update OCR row indices (shift down)
  if (!is.null(rv$submit_ocr_row_indices)) {
    rv$submit_ocr_row_indices <- setdiff(
      ifelse(rv$submit_ocr_row_indices > row_idx,
             rv$submit_ocr_row_indices - 1,
             rv$submit_ocr_row_indices),
      row_idx
    )
  }

  rv$submit_grid_data <- grid
  notify(paste0("Row removed. Players renumbered 1-", nrow(grid), "."), type = "message", duration = 3)
})
```

### Sub-step 8g: Update the match summary to use grid data

**Step 10: Update match summary badges**

The `output$submit_match_summary` reads from `rv$submit_ocr_results`. Update it to use `rv$submit_grid_data` with the stored match data:

```r
output$submit_match_summary <- renderUI({
  req(rv$submit_grid_data)

  grid <- rv$submit_grid_data
  matched_count <- sum(grid$match_status == "matched", na.rm = TRUE)
  possible_count <- 0  # Grid doesn't distinguish possible from matched
  new_count <- sum(grid$match_status == "new" & nchar(trimws(grid$player_name)) > 0, na.rm = TRUE)
  blank_count <- sum(nchar(trimws(grid$player_name)) == 0)
  # ... rest of the badge rendering stays the same
```

Actually, it's simpler to keep using `rv$submit_ocr_results` for the summary badges since it preserves the "possible" distinction. Keep this as-is.

### Sub-step 8h: Update the submission handler

**Step 11: Update final submission to read from grid**

In the `observeEvent(input$submit_tournament, {...})` handler, it currently reads from `rv$submit_ocr_results`. Update it to sync from the grid first:

At the top of the handler, after `req(rv$submit_ocr_results)`, add:

```r
  # Sync grid inputs back to results
  if (!is.null(rv$submit_grid_data)) {
    rv$submit_grid_data <- sync_grid_inputs(input, rv$submit_grid_data, "points", "submit_")
    # Update OCR results from grid data for submission
    grid <- rv$submit_grid_data
    results <- rv$submit_ocr_results
    for (i in seq_len(min(nrow(grid), nrow(results)))) {
      results$username[i] <- grid$player_name[i]
      results$member_number[i] <- grid$member_number[i]
      results$points[i] <- grid$points[i]
    }
    rv$submit_ocr_results <- results
  }
  results <- rv$submit_ocr_results
```

### Sub-step 8i: Update reject match handlers

**Step 12: Update reject match to work with grid data**

The existing reject match observer (lines 759-772) works with `rv$submit_ocr_results`. Since the grid now drives rendering, also update `rv$submit_grid_data` and `rv$submit_player_matches`:

```r
observe({
  req(rv$submit_grid_data)
  grid <- rv$submit_grid_data

  lapply(seq_len(nrow(grid)), function(i) {
    observeEvent(input[[paste0("reject_match_", i)]], {
      # Update grid data
      rv$submit_grid_data$match_status[i] <- "new"
      rv$submit_grid_data$matched_player_id[i] <- NA_integer_
      rv$submit_player_matches[[as.character(i)]] <- list(status = "new")

      # Also update OCR results for submission
      if (!is.null(rv$submit_ocr_results) && i <= nrow(rv$submit_ocr_results)) {
        rv$submit_ocr_results$match_status[i] <- "new"
        rv$submit_ocr_results$matched_player_id[i] <- NA_integer_
        rv$submit_ocr_results$matched_player_name[i] <- NA_character_
      }

      notify("Match rejected - will create as new player", type = "message")
    }, ignoreInit = TRUE, once = TRUE)
  })
})
```

**Note:** The shared grid doesn't render reject buttons — it uses the `player_matches` list to show match badges. The reject buttons were inline in the old custom grid. We have two options:
- A: Add reject button support to the shared grid (complex)
- B: Keep match badges from shared grid, add a separate reject mechanism

**Recommended: B** — The shared grid already shows "Matched #1234" or "New player" badges. For the submit review mode, show a separate clickable element. Actually, looking at the admin grid, it doesn't have reject buttons either — it re-matches on blur. For the submit grid in review mode, the match indicator from the shared grid is sufficient. Users can clear the player name and retype to trigger a new match (once blur matching is added in Task 10).

Remove the old reject match observer and the reject buttons. The shared grid's match badges handle the display.

### Sub-step 8j: Update deck request handler

**Step 13: Update deck request handlers**

The existing deck request handler uses `rv$submit_ocr_results` for iteration. Replace references with `rv$submit_grid_data`:

The `observe` that watches for `__REQUEST_NEW__` selections (lines 778-823) currently iterates over `rv$submit_ocr_results`. Change to iterate over `rv$submit_grid_data`.

The deck request submission handler (lines 826-933) updates all dropdowns. This should still work since it uses `updateSelectInput` with `submit_deck_` prefix — the shared grid uses the same prefix.

However, since we switched to `selectizeInput`, change `updateSelectInput` calls to `updateSelectizeInput`:

```r
    updateSelectizeInput(session, paste0("submit_deck_", i),
                         choices = updated_choices,
                         selected = new_selection)
```

**Step 14: Verify**

Run: `shiny::runApp()`
- Upload Results → upload valid screenshots → verify grid renders using shared grid layout
- Verify member # column appears
- Verify deck dropdown is searchable (selectize)
- Verify OCR-populated rows have subtle blue background
- Verify blank rows look normal
- Verify delete row works
- Verify deck request works
- Verify submission creates tournament correctly
- Verify Enter Results (admin) still works unchanged

**Step 15: Commit**

```bash
git add R/admin_grid.R server/public-submit-server.R views/submit-ui.R
git commit -m "feat(submit): migrate results grid to shared grid module"
```

---

## Task 9: Add Paste-from-Spreadsheet to Submit Results

**Files:**
- Modify: `server/public-submit-server.R`

Since the submit grid now uses the shared grid with prefix `"submit_"`, add paste-from-spreadsheet support using the same pattern as admin.

**Step 1: Add paste button handler**

In `server/public-submit-server.R`, add (copied from `admin-results-server.R:521-552` with prefix changed):

```r
# Paste from spreadsheet for submit grid
observeEvent(input$submit_paste_btn, {
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
        tags$div(class = "fw-bold mb-1", "Names + Points + Deck:"),
        tags$div(class = "text-muted", "PlayerOne\t9\tBlue Flare\nPlayerTwo\t7\tRed Hybrid")
      ),
      tags$textarea(id = "submit_paste_data", class = "form-control", rows = "10",
                    placeholder = "Paste data here...")
    ),
    footer = tagList(
      actionButton("submit_paste_apply", "Fill Grid", class = "btn-primary", icon = icon("table")),
      modalButton("Cancel")
    ),
    size = "l",
    easyClose = TRUE
  ))
})
```

**Step 2: Add paste apply handler**

```r
observeEvent(input$submit_paste_apply, {
  req(rv$submit_grid_data)

  paste_text <- input$submit_paste_data
  if (is.null(paste_text) || nchar(trimws(paste_text)) == 0) {
    notify("No data to paste", type = "warning")
    return()
  }

  rv$submit_grid_data <- sync_grid_inputs(input, rv$submit_grid_data, "points", "submit_")
  grid <- rv$submit_grid_data

  all_decks <- safe_query(rv$db_con, "
    SELECT archetype_id, archetype_name FROM deck_archetypes WHERE is_active = TRUE
  ", default = data.frame(archetype_id = integer(), archetype_name = character()))
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
    if (!is.na(p$deck_id)) grid$deck_id[idx] <- p$deck_id
    fill_count <- fill_count + 1L
  }

  removeModal()
  notify(sprintf("Filled %d rows from pasted data", fill_count), type = "message")

  # Trigger player match lookup for pasted names
  for (idx in seq_len(fill_count)) {
    name <- trimws(grid$player_name[idx])
    if (nchar(name) == 0) next
    match_info <- match_player(name, rv$db_con)
    rv$submit_player_matches[[as.character(idx)]] <- match_info
    grid$match_status[idx] <- match_info$status
    if (match_info$status == "matched") {
      grid$matched_player_id[idx] <- match_info$player_id
    } else {
      grid$matched_player_id[idx] <- NA_integer_
    }
  }

  rv$submit_grid_data <- grid
})
```

**Step 3: Verify**

Run: `shiny::runApp()`
- Upload Results → process screenshots → verify "Paste from Spreadsheet" button in card header
- Click it → paste some data → verify grid fills
- Verify player matching runs on pasted names

**Step 4: Commit**

```bash
git add server/public-submit-server.R
git commit -m "feat(submit): add paste-from-spreadsheet support"
```

---

## Task 10: Add Blur-Based Player Matching to Submit Results

**Files:**
- Modify: `server/public-submit-server.R`

Add delegated blur handlers for `submit_player_` inputs, matching the admin pattern.

**Step 1: Add blur event delegation**

In `server/public-submit-server.R`, after the step 2 transition code, add:

```r
# Attach blur handlers for submit grid player matching
observe({
  req(rv$submit_grid_data)
  shinyjs::runjs("
    $(document).off('blur.submitGrid').on('blur.submitGrid', 'input[id^=\"submit_player_\"]', function() {
      var id = $(this).attr('id');
      var rowNum = parseInt(id.replace('submit_player_', ''));
      if (!isNaN(rowNum)) {
        Shiny.setInputValue('submit_player_blur', {row: rowNum, name: $(this).val(), ts: Date.now()}, {priority: 'event'});
      }
    });
  ")
})
```

**Step 2: Add blur handler**

```r
observeEvent(input$submit_player_blur, {
  req(rv$db_con, rv$submit_grid_data)

  info <- input$submit_player_blur
  row_num <- info$row
  name <- trimws(info$name)

  if (is.null(row_num) || is.na(row_num)) return()
  if (row_num < 1 || row_num > nrow(rv$submit_grid_data)) return()

  # Sync all inputs before modifying reactive
  rv$submit_grid_data <- sync_grid_inputs(input, rv$submit_grid_data, "points", "submit_")

  if (nchar(name) == 0) {
    rv$submit_player_matches[[as.character(row_num)]] <- NULL
    rv$submit_grid_data$match_status[row_num] <- ""
    rv$submit_grid_data$matched_player_id[row_num] <- NA_integer_
    return()
  }

  match_info <- match_player(name, rv$db_con)
  rv$submit_player_matches[[as.character(row_num)]] <- match_info
  rv$submit_grid_data$match_status[row_num] <- match_info$status
  if (match_info$status == "matched") {
    rv$submit_grid_data$matched_player_id[row_num] <- match_info$player_id
  } else {
    rv$submit_grid_data$matched_player_id[row_num] <- NA_integer_
  }
})
```

**Step 3: Verify**

Run: `shiny::runApp()`
- Upload Results → process screenshots → in review grid, type a known player name in a blank row
- Tab away (blur) → verify match badge appears ("Matched" or "New player")
- Clear the name → verify match badge disappears

**Step 4: Commit**

```bash
git add server/public-submit-server.R
git commit -m "feat(submit): add blur-based player matching in review grid"
```

---

## Implementation Order

Execute tasks in this order (dependencies noted):

| Order | Task | Depends On | Risk |
|-------|------|------------|------|
| 1 | Task 1: Member # column | — | Low |
| 2 | Task 2: Mode parameter + CSS | — | Low |
| 3 | Task 3: Selectize dropdown | — | Low |
| 4 | Task 4: Sync event types | — | Low |
| 5 | Task 5: Format in summary bars | — | Low |
| 6 | Task 6: Admin validation + reset | — | Low |
| 7 | Task 7: OCR output validation | — | Medium |
| 8 | Task 8: Migrate submit grid | Tasks 1-3 | High |
| 9 | Task 9: Paste from spreadsheet | Task 8 | Low |
| 10 | Task 10: Blur player matching | Task 8 | Low |

Tasks 1-7 are independent and can be done in any order. Tasks 8-10 must be sequential. Task 8 is the highest-risk task since it replaces the entire submit grid — test thoroughly.

## Verification Checklist

After all tasks complete, verify the full flow end-to-end:

- [ ] **Admin Enter Results:** Create tournament → fill grid → submit → form resets
- [ ] **Admin Enter Results:** Member # column visible and optional
- [ ] **Admin Enter Results:** Deck dropdown is searchable
- [ ] **Admin Enter Results:** Event type/format validation works
- [ ] **Admin Enter Results:** Summary bar shows format
- [ ] **Admin Edit Tournaments:** Grid shows member # column, deck is searchable
- [ ] **Submit Results:** Upload screenshots → OCR processes → review grid shows
- [ ] **Submit Results:** Grid matches admin layout (member #, searchable deck, placement badges)
- [ ] **Submit Results:** OCR-populated rows have subtle visual distinction
- [ ] **Submit Results:** Delete row works
- [ ] **Submit Results:** Deck request works
- [ ] **Submit Results:** Paste from spreadsheet works
- [ ] **Submit Results:** Blur player matching works on manual name entry
- [ ] **Submit Results:** Event types match admin (all types including Release Event)
- [ ] **Submit Results:** Summary bar shows format name (not ID) and event type
- [ ] **Submit Results:** Confirmation checkbox still required
- [ ] **Submit Results:** Tournament submission works correctly
- [ ] **Submit Results:** Low-quality OCR shows warning modal
