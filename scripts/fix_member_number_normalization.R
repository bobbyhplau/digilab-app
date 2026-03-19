# =============================================================================
# Fix Member Number Normalization
# Normalizes all Bandai IDs to 10-digit zero-padded format,
# then merges duplicate players caused by padding differences.
# =============================================================================

library(dotenv)
load_dot_env()
library(RPostgres)

con <- dbConnect(Postgres(),
  host = Sys.getenv("NEON_HOST"),
  dbname = Sys.getenv("NEON_DATABASE"),
  user = Sys.getenv("NEON_USER"),
  password = Sys.getenv("NEON_PASSWORD"),
  sslmode = "require")

# =========================================================================
# Step 1: Normalize all member_numbers to 10-digit zero-padded
# =========================================================================
cat("=== Step 1: Normalize member_numbers ===\n")

# Process row by row to handle unique constraint conflicts gracefully
to_fix <- dbGetQuery(con, "
  SELECT player_id, member_number,
         LPAD(REGEXP_REPLACE(TRIM(BOTH FROM REPLACE(member_number, '#', '')), '[^0-9]', '', 'g'), 10, '0') as normalized
  FROM players
  WHERE member_number IS NOT NULL
    AND member_number != ''
    AND member_number !~ '^GUEST'
    AND (LENGTH(member_number) != 10 OR member_number ~ '[^0-9]')
  ORDER BY player_id")
cat(sprintf("Found %d member_numbers to normalize\n", nrow(to_fix)))

updated <- 0
skipped <- 0
for (i in seq_len(nrow(to_fix))) {
  pid <- to_fix$player_id[i]
  normalized <- to_fix$normalized[i]
  tryCatch({
    dbExecute(con, sprintf("UPDATE players SET member_number = '%s', updated_at = NOW() WHERE player_id = %d",
                           normalized, pid))
    updated <- updated + 1
  }, error = function(e) {
    # Unique constraint violation — will be handled by merge step
    skipped <<- skipped + 1
  })
}
cat(sprintf("Normalized: %d, Skipped (will merge): %d\n", updated, skipped))

# =========================================================================
# Step 2: Find and merge duplicate players (same normalized member_number)
# =========================================================================
cat("\n=== Step 2: Find duplicate player pairs ===\n")

# Use normalized comparison to catch remaining un-normalized pairs
dupes <- dbGetQuery(con, "
  SELECT p1.player_id as keep_id, p1.display_name as keep_name,
         p2.player_id as remove_id, p2.display_name as remove_name,
         LPAD(REGEXP_REPLACE(REPLACE(p1.member_number, '#', ''), '[^0-9]', '', 'g'), 10, '0') as member_number,
         (SELECT COUNT(*) FROM results WHERE player_id = p1.player_id) as keep_results,
         (SELECT COUNT(*) FROM results WHERE player_id = p2.player_id) as remove_results
  FROM players p1
  JOIN players p2 ON
    LPAD(REGEXP_REPLACE(REPLACE(p1.member_number, '#', ''), '[^0-9]', '', 'g'), 10, '0') =
    LPAD(REGEXP_REPLACE(REPLACE(p2.member_number, '#', ''), '[^0-9]', '', 'g'), 10, '0')
    AND p1.player_id < p2.player_id
  WHERE p1.is_active IS NOT FALSE AND p2.is_active IS NOT FALSE
    AND p1.member_number IS NOT NULL AND p1.member_number != ''
    AND p1.member_number !~ '^GUEST'
    AND p2.member_number IS NOT NULL AND p2.member_number != ''
    AND p2.member_number !~ '^GUEST'
  ORDER BY member_number")

if (nrow(dupes) == 0) {
  cat("No duplicate pairs found.\n")
} else {
  cat(sprintf("Found %d duplicate pairs to merge:\n", nrow(dupes)))
  print(dupes, right = FALSE)

  for (i in seq_len(nrow(dupes))) {
    keep_id <- dupes$keep_id[i]
    remove_id <- dupes$remove_id[i]
    cat(sprintf("\n  Merging player %d (%s) into %d (%s)...\n",
        remove_id, dupes$remove_name[i], keep_id, dupes$keep_name[i]))

    # Move results (skip if duplicate tournament — keep target's result)
    existing_tournaments <- dbGetQuery(con, sprintf(
      "SELECT tournament_id FROM results WHERE player_id = %d", keep_id))$tournament_id

    if (length(existing_tournaments) > 0) {
      # Delete conflicting results from source (same tournament)
      conflict_clause <- paste(existing_tournaments, collapse = ",")
      deleted <- dbExecute(con, sprintf(
        "DELETE FROM results WHERE player_id = %d AND tournament_id IN (%s)",
        remove_id, conflict_clause))
      if (deleted > 0) cat(sprintf("    Deleted %d conflicting results\n", deleted))
    }

    # Move remaining results
    moved <- dbExecute(con, sprintf(
      "UPDATE results SET player_id = %d WHERE player_id = %d", keep_id, remove_id))
    cat(sprintf("    Moved %d results\n", moved))

    # Move matches (player_id side)
    dbExecute(con, sprintf(
      "UPDATE matches SET player_id = %d WHERE player_id = %d", keep_id, remove_id))
    # Move matches (opponent_id side)
    dbExecute(con, sprintf(
      "UPDATE matches SET opponent_id = %d WHERE opponent_id = %d", keep_id, remove_id))

    # Clean up rating data for the duplicate
    dbExecute(con, sprintf(
      "DELETE FROM player_rating_history WHERE player_id = %d", remove_id))
    dbExecute(con, sprintf(
      "DELETE FROM player_ratings_cache WHERE player_id = %d", remove_id))
    dbExecute(con, sprintf(
      "DELETE FROM rating_snapshots WHERE player_id = %d", remove_id))

    # Clear member_number (free unique constraint) and deactivate the duplicate
    dbExecute(con, sprintf(
      "UPDATE players SET member_number = NULL, is_active = FALSE, updated_at = NOW(), updated_by = 'bandai-normalization' WHERE player_id = %d",
      remove_id))
    cat("    Deactivated duplicate\n")

    # Now normalize the kept player's member_number if not already done
    dbExecute(con, sprintf(
      "UPDATE players SET member_number = LPAD(REGEXP_REPLACE(REPLACE(member_number, '#', ''), '[^0-9]', '', 'g'), 10, '0'), updated_at = NOW() WHERE player_id = %d AND LENGTH(member_number) != 10",
      keep_id))
  }
}

# =========================================================================
# Step 3: Refresh materialized views
# =========================================================================
cat("\n=== Step 3: Refresh materialized views ===\n")
for (v in c("mv_player_store_stats", "mv_archetype_store_stats",
            "mv_tournament_list", "mv_store_summary", "mv_dashboard_counts")) {
  cat(sprintf("  %s...\n", v))
  tryCatch(dbExecute(con, sprintf("REFRESH MATERIALIZED VIEW %s", v)),
           error = function(e) cat("    SKIP:", e$message, "\n"))
}

# =========================================================================
# Step 4: Verify
# =========================================================================
cat("\n=== Verification ===\n")
remaining <- dbGetQuery(con, "
  SELECT COUNT(*) as n FROM players
  WHERE is_active = TRUE
    AND member_number IS NOT NULL AND member_number != ''
    AND member_number !~ '^GUEST'
    AND LENGTH(member_number) != 10")
cat(sprintf("Active players with non-10-digit Bandai IDs: %d\n", remaining$n))

remaining_dupes <- dbGetQuery(con, "
  SELECT COUNT(*) as n FROM (
    SELECT member_number FROM players
    WHERE is_active IS NOT FALSE AND member_number IS NOT NULL AND member_number != ''
      AND member_number !~ '^GUEST'
    GROUP BY member_number HAVING COUNT(*) > 1
  ) d")
cat(sprintf("Remaining duplicate Bandai IDs: %d\n", remaining_dupes$n))

dbDisconnect(con)
cat("\nDone.\n")
