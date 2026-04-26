# views/migration-banner-ui.R
# Persistent non-dismissible banner announcing migration to digilab.cards

migration_banner_ui <- function() {
  div(
    class = "migration-banner",
    div(
      class = "migration-banner-content",
      div(
        class = "migration-banner-text",
        bsicons::bs_icon("megaphone-fill", class = "migration-banner-icon"),
        span(
          HTML("<strong>DigiLab has moved!</strong> All data views and submissions are now on "),
          tags$a(href = "https://digilab.cards", target = "_blank", rel = "noopener", "digilab.cards"),
          HTML(". Submit results, decklists & match data at "),
          tags$a(href = "https://digilab.cards/submit", target = "_blank", rel = "noopener", "digilab.cards/submit"),
          HTML(". <strong>Data submission on this app has been turned off.</strong> Admins can now log in with Discord at "),
          tags$a(href = "https://digilab.cards/admin", target = "_blank", rel = "noopener", "digilab.cards/admin"),
          HTML(".")
        )
      ),
      tags$a(
        href = "https://digilab.cards",
        target = "_blank",
        rel = "noopener",
        class = "migration-banner-btn",
        bsicons::bs_icon("box-arrow-up-right"),
        "Visit digilab.cards"
      )
    )
  )
}
