# =============================================================================
# Onboarding Modal UI
# 3-step carousel: Welcome, Scene Selection, Community
# =============================================================================

#' Onboarding carousel with 3 steps
onboarding_ui <- function() {
  tagList(
    # --- Progress bar (thin, fills per step) ---
    div(class = "onboarding-progress-bar",
      div(id = "onboarding_progress_fill", class = "onboarding-progress-fill",
          style = "width: 33%;")
    ),

    # --- Dot indicators (pill-shaped active) ---
    div(
      class = "onboarding-dots",
      span(id = "onboarding_dot_1", class = "onboarding-dot active"),
      span(id = "onboarding_dot_2", class = "onboarding-dot upcoming"),
      span(id = "onboarding_dot_3", class = "onboarding-dot upcoming")
    ),

    # ===================== Step 1: Welcome =====================
    div(
      id = "onboarding_step_1",
      class = "onboarding-step",

      # Hero unit: mascot + app name side by side
      div(
        class = "onboarding-hero",
        div(class = "onboarding-hero-mascot", agumon_svg(size = "72px", color = "#F7941D")),
        div(class = "onboarding-hero-text",
          h2(class = "onboarding-title", "DigiLab"),
          p(class = "onboarding-tagline", "Your Local Digimon TCG Hub")
        )
      ),

      # Tagline sentence
      p(class = "onboarding-subtitle",
        "Track tournaments, player ratings, and deck meta for your community."
      ),

      # Vertical feature list
      div(
        class = "onboarding-feature-list",
        div(class = "onboarding-feature-row",
          div(class = "onboarding-feature-icon", bsicons::bs_icon("grid-3x3-gap")),
          div(class = "onboarding-feature-content",
              tags$strong("Dashboard"),
              span(HTML("&mdash;"), " trending decks, top performers, and scene health at a glance"))
        ),
        div(class = "onboarding-feature-row",
          div(class = "onboarding-feature-icon", bsicons::bs_icon("people")),
          div(class = "onboarding-feature-content",
              tags$strong("Players"),
              span(HTML("&mdash;"), " Elo-style ratings, win rates, and tournament history"))
        ),
        div(class = "onboarding-feature-row",
          div(class = "onboarding-feature-icon", bsicons::bs_icon("stack")),
          div(class = "onboarding-feature-content",
              tags$strong("Deck Meta"),
              span(HTML("&mdash;"), " which archetypes are winning and how the meta is shifting"))
        ),
        div(class = "onboarding-feature-row",
          div(class = "onboarding-feature-icon", bsicons::bs_icon("trophy")),
          div(class = "onboarding-feature-content",
              tags$strong("Tournaments"),
              span(HTML("&mdash;"), " full standings, decklists, and match records for every event"))
        ),
        div(class = "onboarding-feature-row",
          div(class = "onboarding-feature-icon", bsicons::bs_icon("geo-alt-fill")),
          div(class = "onboarding-feature-content",
              tags$strong("Stores"),
              span(HTML("&mdash;"), " find nearby stores with schedules and event history"))
        )
      )
    ),

    # ===================== Step 2: Scene Selection =====================
    shinyjs::hidden(
      div(
        id = "onboarding_step_2",
        class = "onboarding-step",

        # Step label
        div(class = "onboarding-step-label", "STEP 2 OF 3"),

        # Title + description
        h2(class = "onboarding-title", "Pick Your Scene"),
        p(class = "onboarding-subtitle",
          "Choose your local community to filter leaderboards, meta, and tournaments to your area."
        ),

        # Full-width map
        div(
          class = "onboarding-map-wrapper",
          div(
            class = "onboarding-map-container",
            mapgl::mapboxglOutput("onboarding_map", height = "300px")
          )
        ),

        # Find My Scene button (full width)
        div(
          class = "onboarding-find-scene",
          actionButton("find_my_scene",
                       tagList(bsicons::bs_icon("crosshair"), " Find My Scene"),
                       class = "btn-primary btn-sm w-100")
        ),

        # Divider
        div(class = "onboarding-divider",
            span("or choose")),

        # Two equal buttons
        div(
          class = "onboarding-scene-buttons",
          actionButton("select_scene_online",
                       tagList(bsicons::bs_icon("camera-video-fill"), " Online / Webcam"),
                       class = "btn-outline-secondary btn-sm"),
          actionButton("select_scene_all",
                       tagList(bsicons::bs_icon("globe2"), " All Scenes"),
                       class = "btn-outline-secondary btn-sm")
        ),

        # Confirmation (hidden by default, shown after selection)
        shinyjs::hidden(
          div(
            id = "onboarding_scene_confirmed",
            class = "onboarding-scene-confirmation",
            bsicons::bs_icon("check-circle-fill"),
            span(id = "onboarding_scene_label", "")
          )
        ),

        # Reassurance note
        p(class = "onboarding-muted-note",
          "You can change your scene anytime from the dropdown in the header."
        )
      )
    ),

    # ===================== Step 3: Community =====================
    shinyjs::hidden(
      div(
        id = "onboarding_step_3",
        class = "onboarding-step",

        # Step label
        div(class = "onboarding-step-label", "STEP 3 OF 3"),

        # Title + description
        h2(class = "onboarding-title", "Join the Community"),
        p(class = "onboarding-subtitle",
          "DigiLab is community-built and still in beta. Your feedback shapes what gets built next."
        ),

        # Tappable link rows
        div(
          class = "onboarding-link-list",
          tags$a(
            class = "onboarding-link-row",
            href = LINKS$discord,
            target = "_blank",
            div(class = "onboarding-link-icon", bsicons::bs_icon("discord")),
            div(class = "onboarding-link-content",
                tags$strong("Discord"),
                span("Chat with players, report bugs, and suggest features")),
            div(class = "onboarding-link-arrow", bsicons::bs_icon("chevron-right"))
          ),
          tags$a(
            class = "onboarding-link-row",
            href = LINKS$kofi,
            target = "_blank",
            div(class = "onboarding-link-icon", bsicons::bs_icon("cup-hot")),
            div(class = "onboarding-link-content",
                tags$strong("Ko-fi"),
                span("Support server costs and ongoing development")),
            div(class = "onboarding-link-arrow", bsicons::bs_icon("chevron-right"))
          ),
          div(
            class = "onboarding-link-row",
            style = "cursor: pointer;",
            onclick = "Shiny.setInputValue('onboarding_to_organizers', true, {priority: 'event'});",
            div(class = "onboarding-link-icon", bsicons::bs_icon("megaphone")),
            div(class = "onboarding-link-content",
                tags$strong("For Organizers"),
                span("Want your community on DigiLab? Here's how")),
            div(class = "onboarding-link-arrow", bsicons::bs_icon("chevron-right"))
          )
        ),

        # Subtle divider + footer links
        tags$hr(class = "onboarding-subtle-divider"),
        p(class = "onboarding-muted-note",
          "Visit ",
          actionLink("onboarding_goto_about", "About"),
          ", ",
          actionLink("onboarding_goto_faq", "FAQ"),
          ", and ",
          actionLink("onboarding_goto_organizers", "For Organizers"),
          " anytime from the footer."
        )
      )
    ),

    # ===================== Navigation Buttons =====================
    div(
      class = "onboarding-nav-buttons",
      div(
        class = "onboarding-nav-left",
        # Step 1 only
        actionButton("onboarding_skip", "Skip for now",
                     class = "onboarding-skip-btn"),
        # Steps 2-3
        shinyjs::hidden(
          actionButton("onboarding_back",
                       tagList(bsicons::bs_icon("arrow-left"), " Back"),
                       class = "btn-outline-secondary btn-sm")
        )
      ),
      div(
        class = "onboarding-nav-right",
        # Step 1
        actionButton("onboarding_next",
                     tagList("Get Started ", bsicons::bs_icon("arrow-right")),
                     class = "btn-primary btn-sm"),
        # Step 2
        shinyjs::hidden(
          actionButton("onboarding_next_2",
                       tagList("Almost Done ", bsicons::bs_icon("arrow-right")),
                       class = "btn-primary btn-sm")
        ),
        # Step 3
        shinyjs::hidden(
          actionButton("onboarding_finish",
                       tagList(bsicons::bs_icon("check-lg"), " Enter DigiLab"),
                       class = "btn-primary btn-sm")
        )
      )
    )
  )
}
