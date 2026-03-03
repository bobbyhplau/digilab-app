# scripts/analysis/generate_scene_map.R
# Generate an interactive Highcharts world map with scene markers
#
# Usage: Rscript scripts/analysis/generate_scene_map.R
# Output: ../digilab-web/public/charts/scene-map.html

dotenv::load_dot_env()
library(highcharter)
library(htmlwidgets)
library(jsonlite)
library(pool)
library(RPostgres)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

OUTPUT_DIR <- normalizePath("../digilab-web/public/charts", mustWork = FALSE)

COL_BLUE   <- "#2D7DD2"
COL_ORANGE <- "#F7941D"

# ---------------------------------------------------------------------------
# Load scene data from database
# ---------------------------------------------------------------------------

message("Connecting to database...")
db_pool <- dbPool(
  drv = Postgres(),
  host = Sys.getenv("NEON_HOST"),
  dbname = Sys.getenv("NEON_DATABASE"),
  user = Sys.getenv("NEON_USER"),
  password = Sys.getenv("NEON_PASSWORD"),
  sslmode = "require"
)
on.exit(poolClose(db_pool))

message("Querying scene data...")
scenes <- dbGetQuery(db_pool, "
  SELECT
    sc.name,
    sc.latitude,
    sc.longitude,
    sc.country,
    sc.created_at::date as joined,
    COALESCE(stats.players, 0)::int as players,
    COALESCE(stats.tournaments, 0)::int as tournaments,
    COALESCE(stats.stores, 0)::int as stores
  FROM scenes sc
  LEFT JOIN (
    SELECT
      st.scene_id,
      COUNT(DISTINCT r.player_id)::int as players,
      COUNT(DISTINCT t.tournament_id)::int as tournaments,
      COUNT(DISTINCT t.store_id)::int as stores
    FROM stores st
    JOIN tournaments t ON t.store_id = st.store_id
    JOIN results r ON r.tournament_id = t.tournament_id
    WHERE t.event_date <= '2026-03-01'
    GROUP BY st.scene_id
  ) stats ON stats.scene_id = sc.scene_id
  WHERE sc.scene_type = 'metro'
    AND sc.name != 'test'
    AND sc.latitude IS NOT NULL
    AND sc.longitude IS NOT NULL
    AND sc.created_at <= '2026-03-01 23:59:59'
  ORDER BY stats.players DESC NULLS LAST
")

message(sprintf("  Found %d scenes", nrow(scenes)))

# ---------------------------------------------------------------------------
# Build map
# ---------------------------------------------------------------------------

message("Building map chart...")

# Build point data for mappoint series
scene_points <- lapply(seq_len(nrow(scenes)), function(i) {
  s <- scenes[i, ]
  list(
    name = s$name,
    lat = s$latitude,
    lon = s$longitude,
    country = s$country,
    players = s$players,
    tournaments = s$tournaments,
    stores = s$stores,
    joined = as.character(s$joined),
    color = if (s$players > 0) COL_BLUE else COL_ORANGE
  )
})

# Load GeoJSON map data from local file (avoids Highcharts CDN rate limits)
world_geojson <- jsonlite::fromJSON(
  "scripts/analysis/world-lowres.geo.json",
  simplifyVector = FALSE
)

chart <- highchart(type = "map") %>%
  hc_chart(backgroundColor = "transparent") %>%
  hc_add_series(
    mapData = world_geojson,
    showInLegend = FALSE,
    borderColor = "#d0d0d0",
    nullColor = "#f0f0f0",
    borderWidth = 0.5,
    enableMouseTracking = FALSE
  ) %>%
  hc_title(
    text = "DigiLab Scenes Around the World",
    style = list(color = "#1a1a1a")
  ) %>%
  hc_subtitle(
    text = "25 scenes across 9 countries in one week",
    style = list(color = "#4a4a4a")
  ) %>%
  hc_mapNavigation(
    enabled = TRUE,
    buttonOptions = list(verticalAlign = "bottom")
  ) %>%
  hc_add_series(
    type = "mappoint",
    name = "Scenes",
    data = scene_points,
    marker = list(
      symbol = "circle",
      radius = 6,
      lineWidth = 1,
      lineColor = "#ffffff",
      fillColor = COL_BLUE
    ),
    dataLabels = list(enabled = FALSE),
    showInLegend = FALSE
  ) %>%
  hc_tooltip(
    headerFormat = "",
    pointFormat = paste0(
      "<b>{point.name}</b><br/>",
      "{point.country}<br/>",
      "Players: {point.players}<br/>",
      "Tournaments: {point.tournaments}<br/>",
      "Stores: {point.stores}<br/>",
      "Joined: {point.joined}"
    )
  ) %>%
  hc_colorAxis(enabled = FALSE) %>%
  hc_legend(enabled = FALSE) %>%
  hc_credits(enabled = FALSE) %>%
  hc_exporting(enabled = FALSE)

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
}

path <- file.path(OUTPUT_DIR, "scene-map.html")
saveWidget(chart, path, selfcontained = TRUE)

# Clean up intermediary _files directory
lib_dir <- file.path(OUTPUT_DIR, "scene-map_files")
if (dir.exists(lib_dir)) unlink(lib_dir, recursive = TRUE)

message(sprintf("Saved: %s", path))
