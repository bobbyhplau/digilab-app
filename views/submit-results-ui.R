# views/submit-results-ui.R
# Unified Submit Results tab UI — card picker landing + shared 3-step wizard

submit_results_ui <- tagList(
  # Title strip
  div(
    class = "page-title-strip mb-3",
    div(
      class = "title-strip-content",
      div(
        class = "title-strip-context",
        bsicons::bs_icon("cloud-upload", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", "Submit Results")
      ),
      div(
        class = "title-strip-controls",
        span(class = "small text-muted", "Add tournament data via upload, manual entry, or match history")
      )
    )
  ),

  # =========================================================================
  # Card Picker Landing Page (id = "sr_method_picker")
  # =========================================================================
  div(
    id = "sr_method_picker",

    layout_columns(
      col_widths = breakpoints(sm = 12, md = 6),
      class = "sr-card-picker",

      # Card 1: Bandai TCG+ Upload (everyone)
      actionButton("sr_card_upload", NULL, class = "sr-method-card",
        div(
          class = "sr-method-card-inner",
          bsicons::bs_icon("cloud-upload", size = "2rem", class = "sr-card-icon text-primary"),
          div(class = "sr-card-title", "Bandai TCG+ Upload"),
          div(class = "sr-card-desc", "Upload standings screenshots (OCR) or CSV export from the Bandai TCG+ app"),
          tags$small(class = "sr-card-help text-muted", "TOs can export standings CSV from the Bandai TCG+ platform after the event")
        )
      ),

      # Card 2: Paste from Spreadsheet (admin only)
      conditionalPanel(
        condition = "output.is_admin",
        actionButton("sr_card_paste", NULL, class = "sr-method-card",
          div(
            class = "sr-method-card-inner",
            bsicons::bs_icon("clipboard", size = "2rem", class = "sr-card-icon text-primary"),
            div(class = "sr-card-title", "Paste from Spreadsheet"),
            div(class = "sr-card-desc", "Paste tab-separated data in flexible formats (name, points, W/L/T, deck)"),
            tags$small(class = "sr-card-help text-muted", "Supports names-only, names+points, names+W/L/T, and more")
          )
        )
      ),

      # Card 3: Manual Entry (admin only)
      conditionalPanel(
        condition = "output.is_admin",
        actionButton("sr_card_manual", NULL, class = "sr-method-card",
          div(
            class = "sr-method-card-inner",
            bsicons::bs_icon("pencil-square", size = "2rem", class = "sr-card-icon text-primary"),
            div(class = "sr-card-title", "Manual Entry"),
            div(class = "sr-card-desc", "Type player results directly into an editable grid"),
            tags$small(class = "sr-card-help text-muted", "For when you have the data on hand")
          )
        )
      ),

      # Card 4: Match-by-Match (everyone)
      actionButton("sr_card_match", NULL, class = "sr-method-card",
        div(
          class = "sr-method-card-inner",
          bsicons::bs_icon("list-ol", size = "2rem", class = "sr-card-icon text-primary"),
          div(class = "sr-card-title", "Match-by-Match"),
          div(class = "sr-card-desc", "Upload your personal match history screenshot from Bandai TCG+"),
          tags$small(class = "sr-card-help text-muted", "Submits individual round results for one player")
        )
      ),

      # Card 5: Add Decklists (everyone)
      actionButton("sr_card_decklist", NULL, class = "sr-method-card",
        div(
          class = "sr-method-card-inner",
          bsicons::bs_icon("link-45deg", size = "2rem", class = "sr-card-icon text-primary"),
          div(class = "sr-card-title", "Add Decklists"),
          div(class = "sr-card-desc", "Submit decklist URLs for an existing tournament"),
          tags$small(class = "sr-card-help text-muted", "Look up your tournaments by Bandai Member ID")
        )
      ),

      # Card 6: Match Results CSV (admin, Coming Soon)
      conditionalPanel(
        condition = "output.is_admin",
        div(class = "sr-method-card sr-method-card--disabled",
          div(
            class = "sr-method-card-inner",
            span(class = "badge bg-secondary position-absolute top-0 end-0 m-2", "Coming Soon"),
            bsicons::bs_icon("filetype-csv", size = "2rem", class = "sr-card-icon text-muted"),
            div(class = "sr-card-title text-muted", "Match Results CSV"),
            div(class = "sr-card-desc text-muted", "Upload CSV of full match-by-match results"),
            tags$small(class = "sr-card-help text-muted", "TOs can export match data from the Bandai TCG+ platform after the event")
          )
        )
      )
    )
  ),

  # =========================================================================
  # Shared Wizard (id = "sr_wizard", hidden initially)
  # For Upload, Paste, and Manual entry methods
  # =========================================================================
  shinyjs::hidden(
    div(
      id = "sr_wizard",

      # Back to picker button
      div(
        class = "mb-3",
        actionButton("sr_back_to_picker", tagList(bsicons::bs_icon("arrow-left"), " Back"),
                     class = "btn-sm btn-outline-secondary")
      ),

      # Wizard step indicator
      div(
        class = "wizard-steps d-flex gap-3 mb-4",
        div(
          id = "sr_step1_indicator",
          class = "wizard-step active",
          span(class = "step-number", "1"),
          span(class = "step-label", "Tournament Details")
        ),
        div(
          id = "sr_step2_indicator",
          class = "wizard-step",
          span(class = "step-number", "2"),
          span(class = "step-label", "Add Results")
        ),
        div(
          id = "sr_step3_indicator",
          class = "wizard-step",
          span(class = "step-number", "3"),
          span(class = "step-label", "Decklists")
        )
      ),

      # Step 1: Tournament Details (shared across upload/paste/manual)
      div(
        id = "sr_step1",
        card(
          card_header(
            class = "d-flex align-items-center gap-2",
            bsicons::bs_icon("clipboard-data"),
            "Tournament Information"
          ),
          card_body(
            class = "admin-form-body",

            # --- Tournament Details section ---
            div(class = "admin-form-section submit-form-inputs",
              div(class = "admin-form-section-label",
                bsicons::bs_icon("calendar-event"),
                "Tournament Details"
              ),
              layout_columns(
                col_widths = breakpoints(sm = c(12, 12, 12), md = c(4, 4, 4)),
                selectInput("sr_scene", tags$span("Scene", tags$span(class = "required-indicator", "*")),
                            choices = c("Loading..." = ""),
                            selectize = FALSE),
                div(
                  selectInput("sr_store", tags$span("Store", tags$span(class = "required-indicator", "*")),
                              choices = c("Select scene first..." = ""),
                              selectize = FALSE),
                  actionLink("sr_request_store", "Store not listed? Request it",
                             class = "small text-primary")
                ),
                div(
                  class = "date-required",
                  dateInput("sr_date", tags$span("Date", tags$span(class = "required-indicator", "*")),
                            value = character(0)),
                  div(id = "sr_date_required_hint", class = "date-required-hint", "Required")
                )
              ),
              layout_columns(
                col_widths = breakpoints(sm = c(6, 6, 6, 6), md = c(4, 4, 2, 2)),
                selectInput("sr_event_type", tags$span("Event Type", tags$span(class = "required-indicator", "*")),
                            choices = c("Select..." = "", EVENT_TYPES),
                            selectize = FALSE),
                selectInput("sr_format", tags$span("Format", tags$span(class = "required-indicator", "*")),
                            choices = c("Loading..." = ""),
                            selectize = FALSE),
                numericInput("sr_players", "Total Players", value = 8, min = 2, max = 256),
                numericInput("sr_rounds", "Total Rounds", value = 4, min = 1, max = 15)
              ),

              # Record format (admin only)
              conditionalPanel(
                condition = "output.is_admin",
                div(
                  class = "row g-3",
                  div(class = "col-12 col-md-6",
                    radioButtons("sr_record_format", "Record Format",
                                 choices = c("Points" = "points", "W-L-T" = "wlt"),
                                 selected = "points", inline = TRUE),
                    tags$small(class = "form-text text-muted",
                      "Points: Total match points (e.g., from Bandai TCG+ standings). ",
                      "W-L-T: Individual wins, losses, and ties.")
                  )
                )
              ),

              # Duplicate warning
              uiOutput("sr_duplicate_warning")
            ),

            # --- Upload section (shown only for upload method) ---
            shinyjs::hidden(
              div(
                id = "sr_upload_section",
                class = "admin-form-section",
                div(class = "admin-form-section-label",
                  bsicons::bs_icon("cloud-upload"),
                  "Upload Standings"
                ),
                div(
                  class = "d-flex align-items-start gap-3",
                  div(
                    class = "upload-dropzone flex-shrink-0",
                    fileInput("sr_screenshots", NULL,
                              multiple = TRUE,
                              accept = c("image/png", "image/jpeg", "image/jpg", "image/webp",
                                         ".png", ".jpg", ".jpeg", ".webp",
                                         "text/csv", ".csv"),
                              placeholder = "No files selected",
                              buttonLabel = tags$span(bsicons::bs_icon("cloud-upload"), " Browse"))
                  ),
                  div(
                    class = "upload-tips small text-muted",
                    div(class = "mb-1 fw-semibold", bsicons::bs_icon("filetype-csv", class = "me-1"), "Bandai TCG+ CSV export (recommended)"),
                    div(class = "mb-1", bsicons::bs_icon("camera", class = "me-1"), "Or upload standings screenshots from Bandai TCG+"),
                    div(bsicons::bs_icon("images", class = "me-1"), "Multiple screenshots OK if standings span screens")
                  )
                ),

                # Image thumbnails preview
                uiOutput("sr_screenshot_preview")
              )
            ),

            # Process/Create button
            div(
              class = "admin-form-actions justify-content-end",
              actionButton("sr_step1_next", "Continue",
                           class = "btn-primary btn-lg",
                           icon = icon("arrow-right"))
            )
          )
        )
      ),

      # Step 2: Results Entry (method-specific, hidden initially)
      shinyjs::hidden(
        div(
          id = "sr_step2",
          uiOutput("sr_step2_content")
        )
      ),

      # Step 3: Decklists (hidden initially)
      shinyjs::hidden(
        div(
          id = "sr_step3",
          uiOutput("sr_decklist_summary_bar"),
          card(
            card_header(
              class = "d-flex justify-content-between align-items-center",
              span("Add Decklist Links"),
              span(class = "text-muted small", "Optional — paste external decklist URLs for any players")
            ),
            card_body(
              uiOutput("sr_decklist_table")
            )
          ),
          div(
            class = "d-flex justify-content-between mt-3",
            actionButton("sr_skip_decklists", "Skip", class = "btn-outline-secondary",
                         icon = icon("forward")),
            div(
              class = "d-flex gap-2",
              actionButton("sr_save_decklists", "Save Progress", class = "btn-primary",
                           icon = icon("floppy-disk")),
              actionButton("sr_done_decklists", "Done", class = "btn-success",
                           icon = icon("check"))
            )
          )
        )
      )
    )
  ),

  # =========================================================================
  # Match-by-Match Section (separate flow, hidden initially)
  # =========================================================================
  shinyjs::hidden(
    div(
      id = "sr_match_section",

      # Back to picker
      div(
        class = "mb-3",
        actionButton("sr_match_back_to_picker", tagList(bsicons::bs_icon("arrow-left"), " Back"),
                     class = "btn-sm btn-outline-secondary")
      ),

      # Combined card for all match history input
      card(
        card_header(
          class = "d-flex align-items-center gap-2",
          bsicons::bs_icon("list-check"),
          "Submit Match History"
        ),
        card_body(
          class = "admin-form-body",

          # --- Tournament Selection section ---
          div(class = "admin-form-section",
            div(class = "admin-form-section-label",
              bsicons::bs_icon("trophy"),
              "Select Tournament"
            ),
            layout_columns(
              col_widths = breakpoints(sm = c(12, 12), md = c(6, 6)),
              selectInput("sr_match_store", "Store",
                          choices = c("All stores" = ""),
                          selectize = FALSE),
              selectInput("sr_match_tournament", "Tournament",
                          choices = c("Select a tournament..." = ""),
                          selectize = FALSE)
            ),
            uiOutput("sr_match_tournament_info")
          ),

          # --- Player Info section ---
          div(class = "admin-form-section",
            div(class = "admin-form-section-label",
              bsicons::bs_icon("person-fill"),
              "Your Player Info"
            ),
            layout_columns(
              col_widths = breakpoints(sm = c(12, 12), md = c(6, 6)),
              div(
                textInput("sr_match_player_username", "Username",
                          placeholder = "e.g., HappyCat"),
                div(id = "sr_match_username_hint", class = "form-text text-danger d-none", "Required")
              ),
              div(
                textInput("sr_match_player_member", "Member Number",
                          placeholder = "e.g., 0000123456"),
                div(id = "sr_match_member_hint", class = "form-text text-danger d-none", "Required")
              )
            )
          ),

          # --- Screenshot section ---
          div(class = "admin-form-section",
            div(class = "admin-form-section-label",
              bsicons::bs_icon("camera"),
              "Match History Screenshot"
            ),
            div(
              class = "d-flex align-items-start gap-3",
              div(
                class = "upload-dropzone flex-shrink-0",
                fileInput("sr_match_screenshots", NULL,
                          multiple = FALSE,
                          accept = c("image/png", "image/jpeg", "image/jpg", "image/webp",
                                     ".png", ".jpg", ".jpeg", ".webp"),
                          placeholder = "No file selected",
                          buttonLabel = tags$span(bsicons::bs_icon("cloud-upload"), " Browse"))
              ),
              div(
                class = "upload-tips small text-muted",
                div(bsicons::bs_icon("info-circle", class = "me-1"), "Screenshot from Bandai TCG+ match history screen")
              )
            ),

            # Image thumbnail preview
            uiOutput("sr_match_screenshot_preview")
          ),

          # Process button
          div(
            class = "admin-form-actions justify-content-end",
            actionButton("sr_match_process_ocr", "Process Screenshot",
                         class = "btn-primary",
                         icon = icon("magic"))
          )
        )
      ),

      # Match History Preview (shown after OCR)
      uiOutput("sr_match_results_preview"),

      # Submit Button (shown after OCR)
      uiOutput("sr_match_final_button")
    )
  ),

  # =========================================================================
  # Add Decklists Section (standalone flow, hidden initially)
  # =========================================================================
  shinyjs::hidden(
    div(
      id = "sr_decklist_standalone",

      # Back to picker
      div(
        class = "mb-3",
        actionButton("sr_decklist_back_to_picker", tagList(bsicons::bs_icon("arrow-left"), " Back"),
                     class = "btn-sm btn-outline-secondary")
      ),

      card(
        card_header(
          class = "d-flex align-items-center gap-2",
          bsicons::bs_icon("link-45deg"),
          "Add Decklists"
        ),
        card_body(
          class = "admin-form-body",

          # --- Bandai ID lookup ---
          div(class = "admin-form-section",
            div(class = "admin-form-section-label",
              bsicons::bs_icon("person-badge"),
              "Bandai Member ID"
            ),
            layout_columns(
              col_widths = breakpoints(sm = c(12, 4), md = c(6, 3)),
              textInput("sr_decklist_member_id", NULL,
                        placeholder = "e.g., 0000123456"),
              actionButton("sr_decklist_lookup", "Look Up",
                           class = "btn-primary mt-auto",
                           icon = icon("search"))
            ),
            tags$small(class = "form-text text-muted",
                       "Enter your Bandai TCG+ Member Number to find your tournaments")
          ),

          # --- Tournament history (populated after lookup) ---
          uiOutput("sr_decklist_player_info"),
          uiOutput("sr_decklist_tournament_history"),
          uiOutput("sr_decklist_entry_form")
        )
      )
    )
  )
)
