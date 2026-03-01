# scripts/analysis/detect_cross_scene_duplicates.R
# Detects potential player duplicates caused by name collisions across scenes
# See: docs/plans/2026-03-01-cross-scene-duplicate-detection-design.md
#
# Usage: source("scripts/analysis/detect_cross_scene_duplicates.R")
# Output: docs/analysis/YYYY-MM-DD-cross-scene-duplicates.md

library(DBI)
library(RPostgres)
library(dotenv)

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Threshold: flag players with ≤ this many results in any one scene
FLAG_THRESHOLD <- 3

# Output file
OUTPUT_DIR <- "docs/analysis"
OUTPUT_FILE <- file.path(OUTPUT_DIR, paste0(Sys.Date(), "-cross-scene-duplicates.md"))

# -----------------------------------------------------------------------------
# Database Connection
# -----------------------------------------------------------------------------

load_dot_env()

db_con <- dbConnect(

  Postgres(),
  host = Sys.getenv("NEON_HOST"),
  dbname = Sys.getenv("NEON_DATABASE"),
  user = Sys.getenv("NEON_USER"),
  password = Sys.getenv("NEON_PASSWORD"),
  sslmode = "require"
)

on.exit(dbDisconnect(db_con), add = TRUE)

message("[analysis] Connected to database")

# -----------------------------------------------------------------------------
# Step 1: Get all player results with scene info (excluding Online)
# -----------------------------------------------------------------------------

message("[analysis] Querying player results by scene...")

player_scene_data <- dbGetQuery(db_con, "
  SELECT
    p.player_id,
    p.display_name,
    p.member_number,
    r.result_id,
    r.tournament_id,
    t.event_date,
    t.store_id,
    s.name AS store_name,
    s.scene_id,
    sc.name AS scene_name,
    sc.slug AS scene_slug,
    sc.scene_type
  FROM players p
  JOIN results r ON p.player_id = r.player_id
  JOIN tournaments t ON r.tournament_id = t.tournament_id
  JOIN stores s ON t.store_id = s.store_id
  JOIN scenes sc ON s.scene_id = sc.scene_id
  WHERE sc.scene_type != 'online'
    AND sc.slug != 'online'
  ORDER BY p.player_id, sc.scene_id, t.event_date
")

message(sprintf("[analysis] Found %d results across %d players",
                nrow(player_scene_data),
                length(unique(player_scene_data$player_id))))

# -----------------------------------------------------------------------------
# Step 2: Aggregate by player and scene
# -----------------------------------------------------------------------------

message("[analysis] Aggregating by player and scene...")

# Count results per player per scene
player_scene_summary <- aggregate(
  result_id ~ player_id + display_name + member_number + scene_id + scene_name,
  data = player_scene_data,
  FUN = length
)
names(player_scene_summary)[names(player_scene_summary) == "result_id"] <- "result_count"

# Get date ranges per player per scene
date_ranges <- aggregate(
  event_date ~ player_id + scene_id,
  data = player_scene_data,
  FUN = function(x) paste(min(x), "to", max(x))
)
names(date_ranges)[names(date_ranges) == "event_date"] <- "date_range"

# Get stores per player per scene
stores_per_scene <- aggregate(
  store_name ~ player_id + scene_id,
  data = player_scene_data,
  FUN = function(x) paste(unique(x), collapse = ", ")
)
names(stores_per_scene)[names(stores_per_scene) == "store_name"] <- "stores"

# Merge all together
player_scene_summary <- merge(player_scene_summary, date_ranges, by = c("player_id", "scene_id"))
player_scene_summary <- merge(player_scene_summary, stores_per_scene, by = c("player_id", "scene_id"))

# Count how many scenes each player appears in
scenes_per_player <- aggregate(
  scene_id ~ player_id,
  data = player_scene_summary,
  FUN = length
)
names(scenes_per_player)[names(scenes_per_player) == "scene_id"] <- "scene_count"

player_scene_summary <- merge(player_scene_summary, scenes_per_player, by = "player_id")

# -----------------------------------------------------------------------------
# Step 3: Identify multi-scene players
# -----------------------------------------------------------------------------

multi_scene_players <- player_scene_summary[player_scene_summary$scene_count >= 2, ]

message(sprintf("[analysis] Found %d players with results in multiple local scenes",
                length(unique(multi_scene_players$player_id))))

# -----------------------------------------------------------------------------
# Step 4: Flag potential duplicates (≤ threshold results in any scene)
# -----------------------------------------------------------------------------

# For each multi-scene player, check if any scene has ≤ threshold results
flagged_player_ids <- unique(multi_scene_players$player_id[multi_scene_players$result_count <= FLAG_THRESHOLD])

flagged_players <- multi_scene_players[multi_scene_players$player_id %in% flagged_player_ids, ]
not_flagged_players <- multi_scene_players[!multi_scene_players$player_id %in% flagged_player_ids, ]

message(sprintf("[analysis] Flagged %d players as potential duplicates (≤%d results in one scene)",
                length(flagged_player_ids), FLAG_THRESHOLD))

# -----------------------------------------------------------------------------
# Step 5: Get total events per player
# -----------------------------------------------------------------------------

total_events <- dbGetQuery(db_con, "
  SELECT player_id, COUNT(DISTINCT tournament_id) as total_events
  FROM results
  GROUP BY player_id
")

flagged_players <- merge(flagged_players, total_events, by = "player_id", all.x = TRUE)
not_flagged_players <- merge(not_flagged_players, total_events, by = "player_id", all.x = TRUE)

# -----------------------------------------------------------------------------
# Step 6: Generate Markdown Report
# -----------------------------------------------------------------------------

message("[analysis] Generating report...")

# Helper to generate recommendation
get_recommendation <- function(player_data) {
  min_results <- min(player_data$result_count)
  max_results <- max(player_data$result_count)

  if (min_results == 1) {
    return("**Likely duplicate** - single result in one scene suggests name collision")
  } else if (min_results <= 2) {
    return("**Probable duplicate** - very few results in one scene")
  } else {
    return("**Review needed** - low result count in one scene, could be collision or new traveler")
  }
}

# Start building report
report <- character()
report <- c(report, "# Cross-Scene Player Duplicate Analysis")
report <- c(report, "")
report <- c(report, sprintf("**Generated:** %s", Sys.Date()))
report <- c(report, sprintf("**Total players analyzed:** %d", length(unique(player_scene_data$player_id))))
report <- c(report, sprintf("**Players in multiple local scenes:** %d", length(unique(multi_scene_players$player_id))))
report <- c(report, sprintf("**Players flagged as potential duplicates:** %d", length(flagged_player_ids)))
report <- c(report, "")

# Summary section
report <- c(report, "## Summary")
report <- c(report, "")
report <- c(report, sprintf("- %d players have results in multiple local scenes",
                            length(unique(multi_scene_players$player_id))))
report <- c(report, sprintf("- %d players flagged as potential duplicates (≤%d results in one scene)",
                            length(flagged_player_ids), FLAG_THRESHOLD))

# Count flagged players with Bandai IDs
flagged_with_bandai <- sum(!is.na(unique(flagged_players[, c("player_id", "member_number")])$member_number) &
                            unique(flagged_players[, c("player_id", "member_number")])$member_number != "")
report <- c(report, sprintf("- %d flagged players have Bandai IDs that may need clearing", flagged_with_bandai))
report <- c(report, "")

# Flagged Players section
report <- c(report, "## Flagged Players")
report <- c(report, "")

if (length(flagged_player_ids) == 0) {
  report <- c(report, "*No potential duplicates detected.*")
  report <- c(report, "")
} else {
  # Sort flagged players by minimum result count (most suspicious first)
  min_results_per_player <- aggregate(result_count ~ player_id, data = flagged_players, FUN = min)
  names(min_results_per_player)[2] <- "min_result_count"
  flagged_order <- min_results_per_player[order(min_results_per_player$min_result_count), "player_id"]

  counter <- 1
  for (pid in flagged_order) {
    player_data <- flagged_players[flagged_players$player_id == pid, ]
    player_data <- player_data[order(-player_data$result_count), ]  # Most results first

    display_name <- player_data$display_name[1]
    member_number <- player_data$member_number[1]
    total_events <- player_data$total_events[1]

    bandai_display <- if (is.na(member_number) || member_number == "") "None" else member_number

    report <- c(report, sprintf("### %d. %s (player_id: %d)", counter, display_name, pid))
    report <- c(report, "")
    report <- c(report, sprintf("**Bandai ID:** %s", bandai_display))
    report <- c(report, sprintf("**Total events:** %d", as.integer(total_events)))
    report <- c(report, "")
    report <- c(report, "| Scene | Store(s) | Results | Date Range |")
    report <- c(report, "|-------|----------|---------|------------|")

    for (i in 1:nrow(player_data)) {
      report <- c(report, sprintf("| %s | %s | %d | %s |",
                                  player_data$scene_name[i],
                                  player_data$stores[i],
                                  player_data$result_count[i],
                                  player_data$date_range[i]))
    }

    report <- c(report, "")
    report <- c(report, sprintf("**Recommendation:** %s", get_recommendation(player_data)))
    report <- c(report, "")

    counter <- counter + 1
  }
}

# Multi-Scene Players (Not Flagged) section
report <- c(report, "## Multi-Scene Players (Not Flagged)")
report <- c(report, "")
report <- c(report, "Players with results in multiple scenes but consistent activity (likely legitimate travelers or confirmed same person).")
report <- c(report, "")

if (nrow(not_flagged_players) == 0) {
  report <- c(report, "*No multi-scene players outside the flagged list.*")
  report <- c(report, "")
} else {
  not_flagged_ids <- unique(not_flagged_players$player_id)

  report <- c(report, "| Player | Scenes | Total Events | Min Results/Scene |")
  report <- c(report, "|--------|--------|--------------|-------------------|")

  for (pid in not_flagged_ids) {
    player_data <- not_flagged_players[not_flagged_players$player_id == pid, ]
    display_name <- player_data$display_name[1]
    scene_count <- player_data$scene_count[1]
    total_events <- player_data$total_events[1]
    min_results <- min(player_data$result_count)

    scenes_list <- paste(unique(player_data$scene_name), collapse = ", ")

    report <- c(report, sprintf("| %s | %s | %d | %d |",
                                display_name, scenes_list, as.integer(total_events), as.integer(min_results)))
  }
  report <- c(report, "")
}

# Next Steps section
report <- c(report, "## Next Steps")
report <- c(report, "")
report <- c(report, "- [ ] Review flagged players manually")
report <- c(report, "- [ ] Decide: split into separate players or confirm as same person")
report <- c(report, "- [ ] Clear Bandai IDs where needed to prevent future re-merging")
report <- c(report, "- [ ] Run rating recalculation after data cleanup")
report <- c(report, "")

# Write report
if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
}

writeLines(report, OUTPUT_FILE)

message(sprintf("[analysis] Report written to: %s", OUTPUT_FILE))
message("[analysis] Done!")
