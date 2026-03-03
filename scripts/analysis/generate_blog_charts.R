# scripts/analysis/generate_blog_charts.R
# Generate interactive Highcharter charts for the rating system blog post
#
# Usage: Rscript scripts/analysis/generate_blog_charts.R
# Output: ../digilab-web/public/charts/*.html

library(highcharter)
library(htmlwidgets)
library(dplyr)
library(atomtemplates)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

INPUT_CSV <- "scripts/analysis/snapshots/algorithm_comparison_20260302_230314.csv"
OUTPUT_DIR <- normalizePath("../digilab-web/public/charts", mustWork = FALSE)

# Digimon card color palette
COL_BLUE   <- "#2D7DD2"
COL_ORANGE <- "#F7941D"
COL_GREEN  <- "#38A169"
COL_RED    <- "#E5383B"
COL_GRAY   <- "#6B7280"

# Base theme: atomtemplates dark + transparent background + dark text for embedding
blog_theme <- hc_theme_merge(
  hc_theme_atom_switch("dark"),
  hc_theme(
    chart = list(backgroundColor = "transparent"),
    colors = c(COL_BLUE, COL_ORANGE, COL_GREEN, COL_RED, COL_GRAY),
    title = list(style = list(color = "#1a1a1a")),
    subtitle = list(style = list(color = "#4a4a4a")),
    xAxis = list(
      title = list(style = list(color = "#333333")),
      labels = list(style = list(color = "#333333"))
    ),
    yAxis = list(
      title = list(style = list(color = "#333333")),
      labels = list(style = list(color = "#333333"))
    ),
    legend = list(itemStyle = list(color = "#333333"))
  )
)

# Helper to save a chart as self-contained HTML
save_chart <- function(hc, filename) {
  path <- file.path(OUTPUT_DIR, filename)
  saveWidget(hc, path, selfcontained = TRUE)
  # Clean up intermediary _files directory created by saveWidget
  lib_dir <- file.path(OUTPUT_DIR, sub("\\.html$", "_files", filename))
  if (dir.exists(lib_dir)) unlink(lib_dir, recursive = TRUE)
  message(sprintf("  Saved: %s", path))
}

# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------

message("Loading comparison data...")
data <- read.csv(INPUT_CSV, stringsAsFactors = FALSE)
message(sprintf("  Loaded %d players from %s", nrow(data), INPUT_CSV))

# Ensure output directory exists
if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
  message(sprintf("  Created output directory: %s", OUTPUT_DIR))
}

# ===========================================================================
# Chart 1: Rating Distribution Comparison (Overlaid Areaspline)
# ===========================================================================

message("\nChart 1: Rating Distribution Comparison")

build_histogram_series <- function(values, binwidth = 15) {
  breaks <- seq(
    floor(min(values) / binwidth) * binwidth,
    ceiling(max(values) / binwidth) * binwidth,
    by = binwidth
  )
  h <- hist(values, breaks = breaks, plot = FALSE)
  # Return midpoints and counts for areaspline
  data.frame(x = h$mids, y = h$counts)
}

old_hist <- build_histogram_series(data$competitive_rating_old, binwidth = 15)
new_hist <- build_histogram_series(data$competitive_rating_new, binwidth = 15)

chart1 <- highchart() %>%
  hc_chart(type = "areaspline") %>%
  hc_add_theme(blog_theme) %>%
  hc_title(text = "Rating Distribution: Before vs After") %>%
  hc_subtitle(text = "Old system (orange) produced a flat spread. New system (blue) produces a proper bell curve.") %>%
  hc_xAxis(title = list(text = "Rating")) %>%
  hc_yAxis(title = list(text = "Players")) %>%
  hc_add_series(
    data = list_parse2(old_hist),
    name = "Old Rating",
    color = COL_ORANGE,
    fillOpacity = 0.3,
    marker = list(enabled = FALSE),
    lineWidth = 2
  ) %>%
  hc_add_series(
    data = list_parse2(new_hist),
    name = "New Rating",
    color = COL_BLUE,
    fillOpacity = 0.5,
    marker = list(enabled = FALSE),
    lineWidth = 2
  ) %>%
  hc_tooltip(
    shared = TRUE,
    headerFormat = "Rating: {point.x}<br/>",
    pointFormat = "<span style='color:{series.color}'>\u25CF</span> {series.name}: <b>{point.y}</b> players<br/>"
  ) %>%
  hc_credits(enabled = FALSE) %>%
  hc_exporting(enabled = FALSE)

save_chart(chart1, "rating-distribution-comparison.html")

# ===========================================================================
# Chart 2: Rank Change Distribution (Column histogram, colored by direction)
# ===========================================================================

message("Chart 2: Rank Change Distribution")

bin_size <- 10
rc_breaks <- seq(
  floor(min(data$rank_change) / bin_size) * bin_size,
  ceiling(max(data$rank_change) / bin_size) * bin_size,
  by = bin_size
)
rc_hist <- hist(data$rank_change, breaks = rc_breaks, plot = FALSE)

# Color each bar based on bin center
rc_colors <- ifelse(rc_hist$mids > 0, COL_BLUE,
              ifelse(rc_hist$mids < 0, COL_ORANGE, COL_GRAY))

# Build data points with individual colors
rc_data <- lapply(seq_along(rc_hist$mids), function(i) {
  list(x = rc_hist$mids[i], y = rc_hist$counts[i], color = rc_colors[i])
})

pct_improved <- round(100 * sum(data$rank_change > 0) / nrow(data), 1)

chart2 <- highchart() %>%
  hc_chart(type = "column") %>%
  hc_add_theme(blog_theme) %>%
  hc_title(text = "How Rankings Changed") %>%
  hc_subtitle(text = sprintf(
    "Positive = moved up. %.1f%% of players improved their rank.", pct_improved
  )) %>%
  hc_xAxis(title = list(text = "Rank Change (positions)")) %>%
  hc_yAxis(title = list(text = "Number of Players")) %>%
  hc_add_series(
    data = rc_data,
    name = "Players",
    showInLegend = FALSE,
    borderWidth = 0
  ) %>%
  hc_tooltip(
    headerFormat = "",
    pointFormat = "Rank change ~{point.x}: <b>{point.y}</b> players"
  ) %>%
  hc_plotOptions(column = list(
    pointPadding = 0,
    groupPadding = 0,
    borderWidth = 0
  )) %>%
  hc_credits(enabled = FALSE) %>%
  hc_exporting(enabled = FALSE)

save_chart(chart2, "rank-change-distribution.html")

# ===========================================================================
# Chart 3: Rank Change vs Events Played (Scatter)
# ===========================================================================

message("Chart 3: Rank Change vs Events Played")

improved <- data %>%
  filter(rank_change > 0) %>%
  mutate(tooltip_name = display_name)

dropped <- data %>%
  filter(rank_change <= 0) %>%
  mutate(tooltip_name = display_name)

# Build tooltip-friendly data points
make_scatter_points <- function(df) {
  lapply(seq_len(nrow(df)), function(i) {
    list(
      x = df$events_played[i],
      y = df$rank_change[i],
      player = df$display_name[i],
      events = df$events_played[i],
      change = df$rank_change[i]
    )
  })
}

chart3 <- highchart() %>%
  hc_chart(type = "scatter") %>%
  hc_add_theme(blog_theme) %>%
  hc_title(text = "Rank Change vs Events Played") %>%
  hc_subtitle(text = "No correlation \u2014 skill matters, not frequency.") %>%
  hc_xAxis(title = list(text = "Events Played")) %>%
  hc_yAxis(
    title = list(text = "Rank Change (positions)"),
    plotLines = list(
      list(
        value = 0,
        color = "#9CA3AF",
        dashStyle = "Dash",
        width = 2,
        zIndex = 3
      )
    )
  ) %>%
  hc_add_series(
    data = make_scatter_points(improved),
    name = "Improved",
    color = COL_BLUE,
    marker = list(radius = 3, symbol = "circle"),
    opacity = 0.6
  ) %>%
  hc_add_series(
    data = make_scatter_points(dropped),
    name = "Dropped",
    color = COL_ORANGE,
    marker = list(radius = 3, symbol = "circle"),
    opacity = 0.6
  ) %>%
  hc_tooltip(
    headerFormat = "",
    pointFormat = "<b>{point.player}</b><br/>Events: {point.events}<br/>Rank change: {point.change}"
  ) %>%
  hc_credits(enabled = FALSE) %>%
  hc_exporting(enabled = FALSE)

save_chart(chart3, "rating-vs-events.html")

# ===========================================================================
# Done
# ===========================================================================

message(sprintf("\nAll 3 charts saved to: %s", OUTPUT_DIR))
message("Files:")
message("  1. rating-distribution-comparison.html")
message("  2. rank-change-distribution.html")
message("  3. rating-vs-events.html")
