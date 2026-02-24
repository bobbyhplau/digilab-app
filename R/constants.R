# R/constants.R
# Shared constants used across UI and server modules

# =============================================================================
# COUNTRY CHOICES
# Full list of countries for store admin forms (physical and online)
# Uses countrycode package for ISO 3166-1 country names
# USA pinned to top, then alphabetical
# =============================================================================

.build_country_choices <- function() {
  # Get all country names from countrycode package
  all_countries <- countrycode::codelist$country.name.en
  all_countries <- sort(unique(all_countries[!is.na(all_countries)]))

  # Remove USA from alphabetical list (we'll pin it to the top)
  all_countries <- all_countries[all_countries != "United States"]

  # Build named list: display name = stored value
  # Pin USA at top for convenience (most common case)
  choices <- c("USA" = "USA")
  other_choices <- setNames(all_countries, all_countries)
  choices <- c(choices, other_choices)

  choices
}

COUNTRY_CHOICES <- .build_country_choices()
