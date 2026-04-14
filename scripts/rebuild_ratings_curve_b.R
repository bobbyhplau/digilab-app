# Rebuild all player ratings with Curve B round multiplier
# Full rebuild: clears player_rating_history and recalculates from scratch.
# Also rebuilds player_ratings_cache, store_ratings_cache, rating_snapshots,
# leaderboard_stats_cache, and player_scenes.
#
# See docs/plans/2026-04-07-round-multiplier-curve-b.md for details.
# Usage: source("scripts/rebuild_ratings_curve_b.R")

library(pool)
library(RPostgres)
library(dotenv)

load_dot_env()

message("Connecting to database...")

db_pool <- dbPool(
  Postgres(),
  host = Sys.getenv("NEON_HOST"),
  dbname = Sys.getenv("NEON_DATABASE"),
  user = Sys.getenv("NEON_USER"),
  password = Sys.getenv("NEON_PASSWORD"),
  sslmode = "require"
)

# Source rating functions and DB helpers
source("R/safe_db.R")
source("R/ratings.R")

# UNRATED_EVENT_TYPES is defined in app.R but ratings.R references it
UNRATED_EVENT_TYPES <- c("casuals", "regulation_battle", "release_event", "other")

message("\n=== Full Rating Rebuild (Curve B) ===\n")

# Snapshot all current ratings for before/after comparison
ratings_before <- dbGetQuery(db_pool, "
  SELECT prc.player_id, p.display_name, prc.competitive_rating, prc.events_played
  FROM player_ratings_cache prc
  JOIN players p ON prc.player_id = p.player_id
")

top10_before <- ratings_before[order(-ratings_before$competitive_rating), ][1:min(10, nrow(ratings_before)), ]

message("Top 10 BEFORE rebuild:")
print(top10_before)
message("")

# Run full rebuild (from_date = NULL clears history and recalculates everything)
start_time <- Sys.time()
success <- recalculate_ratings_cache(db_pool, from_date = NULL)
elapsed <- round(difftime(Sys.time(), start_time, units = "secs"), 1)

if (success) {
  message(sprintf("\nRebuild completed in %s seconds", elapsed))

  # Snapshot new ratings and compare
  ratings_after <- dbGetQuery(db_pool, "
    SELECT prc.player_id, p.display_name, prc.competitive_rating, prc.events_played, prc.global_rank
    FROM player_ratings_cache prc
    JOIN players p ON prc.player_id = p.player_id
  ")

  top10_after <- ratings_after[order(-ratings_after$competitive_rating), ][1:min(10, nrow(ratings_after)), ]

  message("\nTop 10 AFTER rebuild:")
  print(top10_after)

  # Compute deltas by joining before/after on player_id
  deltas <- merge(
    ratings_before[, c("player_id", "competitive_rating")],
    ratings_after[, c("player_id", "display_name", "competitive_rating", "events_played")],
    by = "player_id", suffixes = c("_old", "_new")
  )
  deltas$delta <- deltas$competitive_rating_new - deltas$competitive_rating_old

  message("\nBiggest gains (top 10):")
  top_gains <- deltas[order(-deltas$delta), ][1:min(10, nrow(deltas)), c("display_name", "competitive_rating_old", "competitive_rating_new", "delta", "events_played")]
  print(top_gains)

  message("\nBiggest drops (top 10):")
  top_drops <- deltas[order(deltas$delta), ][1:min(10, nrow(deltas)), c("display_name", "competitive_rating_old", "competitive_rating_new", "delta", "events_played")]
  print(top_drops)

  message(sprintf("\nSummary: %d players changed, median delta = %+.0f, range = [%+.0f, %+.0f]",
    sum(deltas$delta != 0), median(deltas$delta),
    min(deltas$delta), max(deltas$delta)))
} else {
  message("\nRebuild FAILED — check logs above for errors")
}

poolClose(db_pool)
message("\nDone.")
