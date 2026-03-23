# =============================================================================
# Submit Results: Match-by-Match Server
# Personal match history screenshot upload and submission
# Extracted from public-submit-server.R, adapted for sr_match_ prefix
# =============================================================================

# Initialize match history reactive values
rv$sr_match_ocr_results <- NULL
rv$sr_match_uploaded_file <- NULL
rv$sr_match_parsed_count <- 0
rv$sr_match_total_rounds <- 0

# Populate store dropdown for match history
observe({
  req("submit_results" %in% visited_tabs())

  stores <- safe_query(db_pool, "
    SELECT store_id, name FROM stores
    WHERE is_active = TRUE
    ORDER BY name
  ")
  if (nrow(stores) == 0) { invalidateLater(500); return() }
  choices <- setNames(stores$store_id, stores$name)
  updateSelectInput(session, "sr_match_store",
                    choices = c("All stores" = "", choices))
})

# Populate tournament dropdown based on store selection
observe({
  req("submit_results" %in% visited_tabs())

  has_store_filter <- !is.null(input$sr_match_store) && input$sr_match_store != ""

  if (has_store_filter) {
    tournaments <- safe_query(db_pool, "
      SELECT t.tournament_id, t.event_date, t.event_type, s.name as store_name
      FROM tournaments t
      JOIN stores s ON t.store_id = s.store_id
      WHERE t.store_id = $1
      ORDER BY t.event_date DESC
      LIMIT 50
    ", params = list(as.integer(input$sr_match_store)))
  } else {
    tournaments <- safe_query(db_pool, "
      SELECT t.tournament_id, t.event_date, t.event_type, s.name as store_name
      FROM tournaments t
      JOIN stores s ON t.store_id = s.store_id
      ORDER BY t.event_date DESC
      LIMIT 50
    ")
  }

  if (nrow(tournaments) > 0 && !is.null(tournaments$tournament_id)) {
    labels <- paste0(tournaments$store_name, " - ",
                     format(as.Date(tournaments$event_date), "%b %d, %Y"),
                     " (", tournaments$event_type, ")")
    choices <- setNames(tournaments$tournament_id, labels)
    updateSelectInput(session, "sr_match_tournament",
                      choices = c("Select a tournament..." = "", choices))
  } else {
    updateSelectInput(session, "sr_match_tournament",
                      choices = c("No tournaments found" = ""))
  }
})

# Show tournament info when selected
output$sr_match_tournament_info <- renderUI({
  req(input$sr_match_tournament)
  req(input$sr_match_tournament != "")

  tournament <- safe_query(db_pool, "
    SELECT t.*, s.name as store_name
    FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(as.integer(input$sr_match_tournament)))

  if (nrow(tournament) == 0) return(NULL)

  t <- tournament[1, ]
  div(
    class = "mt-2 p-2 rounded",
    style = "background: rgba(15, 76, 129, 0.1);",
    tags$small(
      strong(t$store_name), " | ",
      format(as.Date(t$event_date), "%B %d, %Y"), " | ",
      t$event_type, " | ",
      t$player_count, " players | ",
      t$rounds, " rounds"
    )
  )
})

# Preview uploaded match history screenshot
output$sr_match_screenshot_preview <- renderUI({
  req(input$sr_match_screenshots)

  file <- input$sr_match_screenshots
  if (is.null(file)) return(NULL)

  rv$sr_match_uploaded_file <- file

  file_ext <- tolower(tools::file_ext(file$name))
  mime_type <- switch(file_ext,
    "png" = "image/png",
    "jpg" = "image/jpeg",
    "jpeg" = "image/jpeg",
    "webp" = "image/webp",
    "image/png"
  )

  img_data <- base64enc::base64encode(file$datapath)
  img_src <- paste0("data:", mime_type, ";base64,", img_data)

  div(
    class = "screenshot-thumbnails",
    div(
      class = "screenshot-thumb",
      tags$img(src = img_src, alt = file$name),
      div(
        class = "screenshot-thumb-label",
        span(class = "filename", file$name)
      )
    )
  )
})

# Process match history OCR
observeEvent(input$sr_match_process_ocr, {
  req(rv$sr_match_uploaded_file)

  # Validate required fields
  if (is.null(input$sr_match_tournament) || input$sr_match_tournament == "") {
    notify("Please select a tournament", type = "error")
    return()
  }

  if (is.null(input$sr_match_player_username) || trimws(input$sr_match_player_username) == "") {
    notify("Please enter your username", type = "error")
    shinyjs::removeClass("sr_match_username_hint", "d-none")
    return()
  } else {
    shinyjs::addClass("sr_match_username_hint", "d-none")
  }

  if (is.null(input$sr_match_player_member) || trimws(input$sr_match_player_member) == "") {
    notify("Please enter your member number", type = "error")
    shinyjs::removeClass("sr_match_member_hint", "d-none")
    return()
  } else {
    shinyjs::addClass("sr_match_member_hint", "d-none")
  }

  # Get the round count from the selected tournament
  tournament <- safe_query(db_pool, "
    SELECT rounds FROM tournaments WHERE tournament_id = $1
  ", params = list(as.integer(input$sr_match_tournament)))

  total_rounds <- if (nrow(tournament) > 0 && !is.na(tournament$rounds[1])) {
    tournament$rounds[1]
  } else {
    4
  }

  file <- rv$sr_match_uploaded_file

  # Show processing modal
  showModal(modalDialog(
    div(
      class = "text-center py-4",
      div(class = "processing-spinner mb-3"),
      h5(class = "text-primary", "Processing Screenshot"),
      p(class = "text-muted mb-0", "Extracting match data...")
    ),
    title = NULL,
    footer = NULL,
    easyClose = FALSE,
    size = "s"
  ))

  message("[MATCH SUBMIT] Processing file: ", file$name)
  message("[MATCH SUBMIT] File path: ", file$datapath)

  # Call OCR
  ocr_result <- tryCatch({
    gcv_detect_text(file$datapath, verbose = TRUE)
  }, error = function(e) {
    message("[MATCH SUBMIT] OCR error: ", e$message)
    NULL
  })

  ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result

  if (is.null(ocr_text) || ocr_text == "") {
    removeModal()
    notify("Could not read the screenshot. Make sure the image is clear and shows the match history screen.", type = "error")
    return()
  }

  message("[MATCH SUBMIT] OCR text length: ", nchar(ocr_text))

  # Parse match history
  parsed <- tryCatch({
    parse_match_history(ocr_text, verbose = TRUE)
  }, error = function(e) {
    message("[MATCH SUBMIT] Parse error: ", e$message)
    data.frame()
  })

  removeModal()

  parsed_count <- nrow(parsed)

  # Ensure we have exactly total_rounds rows
  if (parsed_count < total_rounds) {
    existing_rounds <- if (parsed_count > 0) parsed$round else integer()
    for (r in seq_len(total_rounds)) {
      if (!(r %in% existing_rounds)) {
        blank_row <- data.frame(
          round = r,
          opponent_username = "",
          opponent_member_number = "",
          games_won = 0,
          games_lost = 0,
          games_tied = 0,
          match_points = 0,
          stringsAsFactors = FALSE
        )
        parsed <- rbind(parsed, blank_row)
      }
    }
    parsed <- parsed[order(parsed$round), ]
  } else if (parsed_count > total_rounds) {
    parsed <- parsed[parsed$round <= total_rounds, ]
  }

  # Store results and counts
  rv$sr_match_ocr_results <- parsed
  rv$sr_match_parsed_count <- parsed_count
  rv$sr_match_total_rounds <- total_rounds

  # Show appropriate notification
  if (parsed_count == 0) {
    notify(paste("No matches found - fill in all", total_rounds, "rounds manually"),
           type = "warning", duration = 8)
  } else if (parsed_count == total_rounds) {
    notify(paste("All", total_rounds, "rounds found"), type = "message")
  } else if (parsed_count < total_rounds) {
    notify(paste("Parsed", parsed_count, "of", total_rounds, "rounds - fill in remaining manually"),
           type = "warning", duration = 8)
  } else {
    notify(paste("Found", parsed_count, "rounds, showing", total_rounds),
           type = "warning", duration = 8)
  }
})

# Render match history preview table with editable fields
output$sr_match_results_preview <- renderUI({
  req(rv$sr_match_ocr_results)

  results <- rv$sr_match_ocr_results
  parsed_count <- rv$sr_match_parsed_count
  total_rounds <- rv$sr_match_total_rounds

  status_badge <- if (parsed_count == total_rounds) {
    span(class = "badge bg-success", paste("All", total_rounds, "rounds found"))
  } else {
    span(class = "badge bg-warning text-dark", paste("Parsed", parsed_count, "of", total_rounds, "rounds"))
  }

  card(
    class = "mt-3",
    card_header(
      class = "d-flex justify-content-between align-items-center",
      span("Review & Edit Match History"),
      status_badge
    ),
    card_body(
      div(
        class = "alert alert-info d-flex mb-3",
        bsicons::bs_icon("pencil-square", class = "me-2 flex-shrink-0"),
        tags$small("Review and edit the extracted data. Correct any OCR errors before submitting.",
                   if (parsed_count < total_rounds) " Fill in missing rounds manually." else "")
      ),

      # Header row
      layout_columns(
        col_widths = c(1, 4, 3, 2, 2),
        class = "results-header-row",
        div("Rd"),
        div("Opponent"),
        div("Member #"),
        div("W-L-T"),
        div("Pts")
      ),

      # Editable rows
      lapply(seq_len(nrow(results)), function(i) {
        row <- results[i, ]

        layout_columns(
          col_widths = c(1, 4, 3, 2, 2),
          class = "upload-result-row",
          div(span(class = "placement-badge", row$round)),
          div(textInput(paste0("sr_match_opponent_", i), NULL,
                        value = row$opponent_username)),
          div(textInput(paste0("sr_match_member_", i), NULL,
                        value = if (!is.na(row$opponent_member_number)) row$opponent_member_number else "",
                        placeholder = "0000...")),
          div(textInput(paste0("sr_match_games_", i), NULL,
                        value = paste0(row$games_won, "-", row$games_lost, "-", row$games_tied),
                        placeholder = "W-L-T")),
          div(numericInput(paste0("sr_match_points_", i), NULL,
                           value = as.integer(row$match_points),
                           min = 0, max = 9))
        )
      })
    )
  )
})

# Match history submit button
output$sr_match_final_button <- renderUI({
  req(rv$sr_match_ocr_results)

  div(
    class = "mt-3 d-flex justify-content-end gap-2",
    actionButton("sr_match_cancel", "Cancel", class = "btn-outline-secondary"),
    actionButton("sr_match_submit", "Submit Match History",
                 class = "btn-primary", icon = icon("check"))
  )
})

# Handle match history submission
observeEvent(input$sr_match_submit, {
  req(rv$sr_match_ocr_results)
  req(input$sr_match_tournament)

  if (is.null(input$sr_match_player_username) || trimws(input$sr_match_player_username) == "") {
    notify("Please enter your username", type = "error")
    return()
  }

  if (is.null(input$sr_match_player_member) || trimws(input$sr_match_player_member) == "") {
    notify("Please enter your member number", type = "error")
    return()
  }

  results <- rv$sr_match_ocr_results
  tournament_id <- as.integer(input$sr_match_tournament)
  submitter_username <- trimws(input$sr_match_player_username)
  submitter_member <- normalize_member_number(input$sr_match_player_member)
  if (is.na(submitter_member)) submitter_member <- ""

  tryCatch({
    conn <- pool::localCheckout(db_pool)
    DBI::dbExecute(conn, "BEGIN")

    # Get scene_id for the tournament's store
    match_scene <- DBI::dbGetQuery(conn, "
      SELECT s.scene_id FROM tournaments t JOIN stores s ON t.store_id = s.store_id
      WHERE t.tournament_id = $1
    ", params = list(tournament_id))
    match_scene_id <- if (nrow(match_scene) > 0) match_scene$scene_id[1] else NULL

    # Find or create submitting player
    submitter_has_real_id <- nchar(submitter_member) > 0 &&
                             !grepl("^GUEST", submitter_member, ignore.case = TRUE)
    clean_submitter_member <- if (submitter_has_real_id) submitter_member else NA_character_

    match_info <- match_player(submitter_username, conn, member_number = clean_submitter_member, scene_id = match_scene_id)
    if (match_info$status == "matched" || match_info$status == "ambiguous") {
      player_id <- if (match_info$status == "matched") match_info$player_id else match_info$candidates$player_id[1]
      if (submitter_has_real_id) {
        DBI::dbExecute(conn, "
          UPDATE players SET member_number = $1, identity_status = 'verified'
          WHERE player_id = $2 AND (member_number IS NULL OR member_number = '')
        ", params = list(clean_submitter_member, player_id))
      }
    } else {
      identity_status <- if (submitter_has_real_id) "verified" else "unverified"
      player_slug <- generate_unique_slug(db_pool, submitter_username)
      new_player <- DBI::dbGetQuery(conn, "
        INSERT INTO players (display_name, slug, member_number, identity_status, home_scene_id)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING player_id
      ", params = list(submitter_username, player_slug, clean_submitter_member, identity_status, match_scene_id))
      player_id <- new_player$player_id[1]
    }

    # Insert each match - read from editable inputs
    matches_inserted <- 0
    for (i in seq_len(nrow(results))) {
      row <- results[i, ]

      opponent_username <- input[[paste0("sr_match_opponent_", i)]]
      if (is.null(opponent_username) || opponent_username == "") opponent_username <- row$opponent_username

      opponent_member_input <- input[[paste0("sr_match_member_", i)]]
      opponent_member <- normalize_member_number(opponent_member_input)

      # Parse games W-L-T from input
      games_input <- input[[paste0("sr_match_games_", i)]]
      games_won <- row$games_won
      games_lost <- row$games_lost
      games_tied <- row$games_tied
      if (!is.null(games_input) && grepl("^\\d+-\\d+-\\d+$", games_input)) {
        parts <- strsplit(games_input, "-")[[1]]
        games_won <- as.integer(parts[1])
        games_lost <- as.integer(parts[2])
        games_tied <- as.integer(parts[3])
      }

      match_points_input <- input[[paste0("sr_match_points_", i)]]
      match_points <- if (!is.null(match_points_input) && !is.na(match_points_input)) {
        as.integer(match_points_input)
      } else {
        as.integer(row$match_points)
      }

      opp_has_real_id <- !is.na(opponent_member) && nchar(opponent_member) > 0 &&
                         !grepl("^GUEST", opponent_member, ignore.case = TRUE)
      clean_opp_member <- if (opp_has_real_id) opponent_member else NA_character_

      opp_match_info <- match_player(opponent_username, conn, member_number = clean_opp_member, scene_id = match_scene_id)
      if (opp_match_info$status == "matched" || opp_match_info$status == "ambiguous") {
        opponent_id <- if (opp_match_info$status == "matched") opp_match_info$player_id else opp_match_info$candidates$player_id[1]
        if (opp_has_real_id) {
          DBI::dbExecute(conn, "
            UPDATE players SET member_number = $1, identity_status = 'verified'
            WHERE player_id = $2 AND (member_number IS NULL OR member_number = '')
          ", params = list(clean_opp_member, opponent_id))
        }
      } else {
        opp_identity <- if (opp_has_real_id) "verified" else "unverified"
        opp_slug <- generate_unique_slug(db_pool, opponent_username)
        new_opponent <- DBI::dbGetQuery(conn, "
          INSERT INTO players (display_name, slug, member_number, identity_status, home_scene_id)
          VALUES ($1, $2, $3, $4, $5)
          RETURNING player_id
        ", params = list(opponent_username, opp_slug, clean_opp_member, opp_identity, match_scene_id))
        opponent_id <- new_opponent$player_id[1]
      }

      tryCatch({
        DBI::dbExecute(conn, "
          INSERT INTO matches (tournament_id, round_number, player_id, opponent_id, games_won, games_lost, games_tied, match_points)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ", params = list(
          tournament_id,
          as.integer(row$round),
          player_id,
          opponent_id,
          games_won,
          games_lost,
          games_tied,
          match_points
        ))
        matches_inserted <- matches_inserted + 1
      }, error = function(e) {
        message("[MATCH SUBMIT] Skipping duplicate match round ", row$round)
      })
    }

    DBI::dbExecute(conn, "COMMIT")

    # Clear form and return to picker
    rv$sr_match_ocr_results <- NULL
    rv$sr_match_uploaded_file <- NULL
    rv$sr_match_parsed_count <- 0
    rv$sr_match_total_rounds <- 0
    updateSelectInput(session, "sr_match_tournament", selected = "")
    updateTextInput(session, "sr_match_player_username", value = "")
    updateTextInput(session, "sr_match_player_member", value = "")
    shinyjs::reset("sr_match_screenshots")

    notify(
      paste("Match history submitted!", matches_inserted, "matches recorded."),
      type = "message"
    )

  }, error = function(e) {
    tryCatch(DBI::dbExecute(conn, "ROLLBACK"), error = function(re) NULL)
    notify(paste("Error submitting match history:", e$message), type = "error")
  })
})

# Handle match history cancel
observeEvent(input$sr_match_cancel, {
  rv$sr_match_ocr_results <- NULL
  rv$sr_match_uploaded_file <- NULL
  rv$sr_match_parsed_count <- 0
  rv$sr_match_total_rounds <- 0
  shinyjs::reset("sr_match_screenshots")
})
