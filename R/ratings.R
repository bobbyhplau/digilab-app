# R/ratings.R
# Rating calculation functions for player and store ratings
# See docs/plans/2026-02-01-rating-system-design.md for methodology

# -----------------------------------------------------------------------------
# COMPETITIVE PLAYER RATING (Elo-style with implied results)
# -----------------------------------------------------------------------------

#' Calculate competitive ratings for all players
#' Uses Elo-style system with implied results from tournament placements
#'
#' @param db_con Database connection (pool or DBI)
#' @param format_filter Optional format filter (e.g., "BT19")
#' @param date_cutoff Optional date cutoff (character "YYYY-MM-DD") to limit
#'   which tournaments are included. Only tournaments on or before this date
#'   are used for rating calculation.
#' @return Data frame with player_id and competitive_rating
calculate_competitive_ratings <- function(db_con, format_filter = NULL, date_cutoff = NULL) {

  # Build conditions
  conditions <- character(0)
  if (!is.null(format_filter) && format_filter != "") {
    conditions <- c(conditions, sprintf("AND t.format = '%s'", format_filter))
  }
  if (!is.null(date_cutoff)) {
    if (!grepl("^\\d{4}-\\d{2}-\\d{2}$", date_cutoff)) stop("Invalid date_cutoff format")
    conditions <- c(conditions, sprintf("AND t.event_date <= '%s'", date_cutoff))
  }
  extra_conditions <- paste(conditions, collapse = " ")

  # Get all tournament results with player counts and dates
  results <- DBI::dbGetQuery(db_con, sprintf("
    SELECT r.tournament_id, r.player_id, r.placement,
           t.event_date, t.player_count, t.rounds,
           p.display_name
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN players p ON r.player_id = p.player_id
    WHERE r.placement IS NOT NULL
      AND t.player_count IS NOT NULL
      AND t.player_count >= 4
      %s
    ORDER BY t.event_date ASC, r.tournament_id, r.placement
  ", extra_conditions))

  if (nrow(results) == 0) {
    return(data.frame(player_id = integer(), competitive_rating = numeric()))
  }

  # Initialize all players at 1500
  players <- unique(results$player_id)
  ratings <- setNames(rep(1500, length(players)), as.character(players))
  events_played <- setNames(rep(0, length(players)), as.character(players))

  # Get unique tournaments in chronological order
  tournaments <- unique(results[, c("tournament_id", "event_date", "player_count", "rounds")])
  tournaments <- tournaments[order(tournaments$event_date), ]

  # Calculate months ago for decay
  current_date <- Sys.Date()

  # Iterate through tournaments (multiple passes for convergence)
  for (pass in 1:5) {
    for (i in 1:nrow(tournaments)) {
      tourney <- tournaments[i, ]
      tourney_results <- results[results$tournament_id == tourney$tournament_id, ]
      tourney_results <- tourney_results[order(tourney_results$placement), ]

      if (nrow(tourney_results) < 2) next

      # Calculate decay weight (4-month half-life)
      months_ago <- as.numeric(difftime(current_date, tourney$event_date, units = "days")) / 30.44
      decay_weight <- 0.5 ^ (months_ago / 4)

      # Calculate round multiplier: min(1.0 + (rounds - 3) * 0.1, 1.4)
      rounds <- if (is.na(tourney$rounds)) 3 else tourney$rounds
      round_mult <- min(1.0 + (rounds - 3) * 0.1, 1.4)

      # Process each player's implied results
      for (j in 1:nrow(tourney_results)) {
        player_id <- as.character(tourney_results$player_id[j])
        placement <- tourney_results$placement[j]
        player_rating <- ratings[player_id]

        # Determine K-factor (provisional vs established)
        k_factor <- if (events_played[player_id] < 5) 48 else 24

        # Calculate rating change from implied results
        rating_change <- 0

        for (k in 1:nrow(tourney_results)) {
          if (j == k) next

          opponent_id <- as.character(tourney_results$player_id[k])
          opponent_placement <- tourney_results$placement[k]
          opponent_rating <- ratings[opponent_id]

          # Determine if win or loss (lower placement = better)
          actual_result <- if (placement < opponent_placement) 1 else 0

          # Expected score (Elo formula)
          expected <- 1 / (1 + 10^((opponent_rating - player_rating) / 400))

          # Accumulate rating change
          rating_change <- rating_change + k_factor * (actual_result - expected)
        }

        # Apply decay and round multiplier
        rating_change <- rating_change * decay_weight * round_mult

        # Scale down based on number of opponents (normalize)
        num_opponents <- nrow(tourney_results) - 1
        rating_change <- rating_change / num_opponents

        # Update rating
        ratings[player_id] <- ratings[player_id] + rating_change
      }

      # Update events played (only on first pass)
      if (pass == 1) {
        for (pid in tourney_results$player_id) {
          events_played[as.character(pid)] <- events_played[as.character(pid)] + 1
        }
      }
    }
  }

  # Return as data frame
  data.frame(
    player_id = as.integer(names(ratings)),
    competitive_rating = round(as.numeric(ratings), 0),
    stringsAsFactors = FALSE
  )
}


# -----------------------------------------------------------------------------
# ACHIEVEMENT SCORE (Points-based)
# -----------------------------------------------------------------------------

#' Calculate achievement scores for all players
#' Points-based system rewarding placements, diversity, and milestones
#'
#' @param db_con Database connection (pool or DBI)
#' @return Data frame with player_id and achievement_score
calculate_achievement_scores <- function(db_con) {

  # Get all results with tournament info
  # Include archetype_name to filter out UNKNOWN for deck variety calculation
  results <- DBI::dbGetQuery(db_con, "
    SELECT r.player_id, r.tournament_id, r.placement, r.archetype_id,
           t.player_count, t.store_id, t.format, da.archetype_name
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    LEFT JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
    WHERE r.placement IS NOT NULL
  ")

  if (nrow(results) == 0) {
    return(data.frame(player_id = integer(), achievement_score = numeric()))
  }

  # Base placement points
  get_placement_points <- function(placement, player_count) {
    base_points <- if (placement == 1) 50
      else if (placement == 2) 30
      else if (placement == 3) 20
      else if (placement <= 4) 15
      else if (placement <= 8) 10
      else 5

    # Size multiplier
    size_mult <- if (is.na(player_count) || player_count < 8) 1.0
      else if (player_count < 12) 1.0
      else if (player_count < 16) 1.25
      else if (player_count < 24) 1.5
      else if (player_count < 32) 1.75
      else 2.0

    round(base_points * size_mult)
  }

  # Calculate per-player scores
  players <- unique(results$player_id)
  scores <- sapply(players, function(pid) {
    player_results <- results[results$player_id == pid, ]

    # Placement points
    placement_pts <- sum(sapply(1:nrow(player_results), function(i) {
      get_placement_points(player_results$placement[i], player_results$player_count[i])
    }))

    # Store diversity bonus
    unique_stores <- length(unique(player_results$store_id))
    store_bonus <- if (unique_stores >= 6) 50
      else if (unique_stores >= 4) 25
      else if (unique_stores >= 2) 10
      else 0

    # Deck variety bonus (3+ different decks)
    # Exclude UNKNOWN archetype from variety count
    known_decks <- player_results[!is.na(player_results$archetype_name) &
                                  player_results$archetype_name != "UNKNOWN", ]
    unique_decks <- length(unique(known_decks$archetype_id))
    deck_bonus <- if (unique_decks >= 3) 15 else 0

    # Format variety bonus (2+ formats)
    unique_formats <- length(unique(na.omit(player_results$format)))
    format_bonus <- if (unique_formats >= 2) 10 else 0

    placement_pts + store_bonus + deck_bonus + format_bonus
  })

  data.frame(
    player_id = players,
    achievement_score = as.integer(scores),
    stringsAsFactors = FALSE
  )
}


# -----------------------------------------------------------------------------
# STORE AVERAGE PLAYER RATING (Weighted by participation)
# -----------------------------------------------------------------------------

#' Calculate average player rating for each store
#' Weighted by number of appearances (regulars count more)
#'
#' @param db_con Database connection (pool or DBI)
#' @param player_ratings Data frame from calculate_competitive_ratings()
#' @return Data frame with store_id and avg_player_rating
calculate_store_avg_player_rating <- function(db_con, player_ratings) {

  # Get player appearances per store (all time)
  store_appearances <- DBI::dbGetQuery(db_con, "
    SELECT t.store_id, r.player_id, COUNT(*) as appearances
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    WHERE s.is_active = TRUE
    GROUP BY t.store_id, r.player_id
  ")

  if (nrow(store_appearances) == 0) {
    return(data.frame(store_id = integer(), avg_player_rating = numeric()))
  }

  # Join with player ratings
  store_appearances <- merge(store_appearances, player_ratings, by = "player_id", all.x = TRUE)
  store_appearances$competitive_rating[is.na(store_appearances$competitive_rating)] <- 1500

  # Calculate weighted average per store
  # Formula: SUM(rating * appearances) / SUM(appearances)
  store_avg <- aggregate(
    cbind(weighted_rating = competitive_rating * appearances, appearances) ~ store_id,
    data = store_appearances,
    FUN = sum
  )
  store_avg$avg_player_rating <- round(store_avg$weighted_rating / store_avg$appearances, 0)

  store_avg[, c("store_id", "avg_player_rating")]
}


# -----------------------------------------------------------------------------
# RATINGS CACHE MANAGEMENT
# -----------------------------------------------------------------------------

#' Recalculate and cache all player and store ratings
#' Called after result submission to keep cache fresh
#'
#' @param db_con Database connection (pool or DBI)
#' @return TRUE on success, FALSE on error
recalculate_ratings_cache <- function(db_con) {
  tryCatch({
    # Calculate fresh ratings
    player_ratings <- calculate_competitive_ratings(db_con)
    achievement_scores <- calculate_achievement_scores(db_con)
    store_ratings <- calculate_store_avg_player_rating(db_con, player_ratings)

    # Merge player data
    if (nrow(player_ratings) > 0) {
      player_cache <- merge(player_ratings, achievement_scores, by = "player_id", all = TRUE)
      player_cache$competitive_rating[is.na(player_cache$competitive_rating)] <- 1500
      player_cache$achievement_score[is.na(player_cache$achievement_score)] <- 0

      # Count events per player
      events <- DBI::dbGetQuery(db_con, "
        SELECT player_id, COUNT(DISTINCT tournament_id) as events_played
        FROM results GROUP BY player_id
      ")
      player_cache <- merge(player_cache, events, by = "player_id", all.x = TRUE)
      player_cache$events_played[is.na(player_cache$events_played)] <- 0

      # Clear and repopulate player cache
      DBI::dbExecute(db_con, "DELETE FROM player_ratings_cache")
      DBI::dbExecute(db_con, sprintf("
        INSERT INTO player_ratings_cache (player_id, competitive_rating, achievement_score, events_played)
        VALUES %s
      ", paste(sprintf("(%d, %d, %d, %d)",
               player_cache$player_id,
               player_cache$competitive_rating,
               player_cache$achievement_score,
               player_cache$events_played), collapse = ", ")))
    }

    # Clear and repopulate store cache
    if (nrow(store_ratings) > 0) {
      DBI::dbExecute(db_con, "DELETE FROM store_ratings_cache")
      DBI::dbExecute(db_con, sprintf("
        INSERT INTO store_ratings_cache (store_id, avg_player_rating)
        VALUES %s
      ", paste(sprintf("(%d, %d)", store_ratings$store_id, store_ratings$avg_player_rating), collapse = ", ")))
    }

    message("[ratings] Cache updated: ", nrow(player_ratings), " players, ", nrow(store_ratings), " stores")
    TRUE
  }, error = function(e) {
    message("[ratings] Cache update failed: ", e$message)
    FALSE
  })
}


# -----------------------------------------------------------------------------
# RATING SNAPSHOTS (Historical format-era snapshots)
# -----------------------------------------------------------------------------

#' Generate rating snapshot for a specific format era
#' Computes ratings using all tournaments up to the format's end date
#'
#' @param db_con Database connection (pool or DBI)
#' @param format_id Format identifier (e.g., "BT18")
#' @param end_date Date cutoff (last day of this format era)
#' @return Number of player snapshots created
generate_format_snapshot <- function(db_con, format_id, end_date) {
  tryCatch({
    # Calculate global cumulative ratings up to this date (Elo accumulates across format eras)
    ratings <- calculate_competitive_ratings(db_con, date_cutoff = end_date)
    scores <- calculate_achievement_scores(db_con)  # Achievement is cumulative

    if (nrow(ratings) == 0) return(0L)

    # Merge ratings with achievement scores
    snapshot <- merge(ratings, scores, by = "player_id", all.x = TRUE)
    snapshot$achievement_score[is.na(snapshot$achievement_score)] <- 0

    # Count events per player up to cutoff
    events <- DBI::dbGetQuery(db_con,
      "SELECT r.player_id, COUNT(DISTINCT r.tournament_id) as events_played
       FROM results r
       JOIN tournaments t ON r.tournament_id = t.tournament_id
       WHERE t.event_date <= $1
       GROUP BY r.player_id",
      params = list(end_date))

    snapshot <- merge(snapshot, events, by = "player_id", all.x = TRUE)
    snapshot$events_played[is.na(snapshot$events_played)] <- 0

    # Add rank
    snapshot <- snapshot[order(-snapshot$competitive_rating), ]
    snapshot$player_rank <- seq_len(nrow(snapshot))

    # Delete existing snapshot for this format (idempotent)
    DBI::dbExecute(db_con, "DELETE FROM rating_snapshots WHERE format_id = $1",
                   params = list(format_id))

    # Insert snapshot
    if (nrow(snapshot) > 0) {
      DBI::dbExecute(db_con, sprintf("
        INSERT INTO rating_snapshots (player_id, format_id, competitive_rating,
                                       achievement_score, events_played, player_rank, snapshot_date)
        VALUES %s
      ", paste(sprintf("(%d, '%s', %d, %d, %d, %d, '%s')",
               snapshot$player_id, format_id,
               snapshot$competitive_rating, snapshot$achievement_score,
               snapshot$events_played, snapshot$player_rank,
               end_date), collapse = ", ")))
    }

    message(sprintf("[snapshots] Generated %d player snapshots for %s (cutoff: %s)",
                    nrow(snapshot), format_id, end_date))
    nrow(snapshot)
  }, error = function(e) {
    message(sprintf("[snapshots] ERROR generating snapshot for %s: %s", format_id, e$message))
    0L
  })
}


#' Backfill rating snapshots for all historical formats
#' Uses format release dates to determine era boundaries
#'
#' @param db_con Database connection (pool or DBI)
backfill_rating_snapshots <- function(db_con) {
  # Get formats ordered by release date
  formats <- DBI::dbGetQuery(db_con, "
    SELECT format_id, set_name, release_date
    FROM formats
    WHERE release_date IS NOT NULL
    ORDER BY release_date ASC
  ")

  if (nrow(formats) < 2) {
    message("[snapshots] Need at least 2 formats to compute snapshots")
    return(invisible(NULL))
  }

  # Each format's "end date" is the day before the next format's release
  # Last format is excluded — the current era uses live player_ratings_cache, not frozen snapshots
  for (i in 1:(nrow(formats) - 1)) {
    format_id <- formats$format_id[i]
    end_date <- as.Date(formats$release_date[i + 1]) - 1

    message(sprintf("[snapshots] Processing %s (end date: %s)...", format_id, end_date))
    n <- generate_format_snapshot(db_con, format_id, as.character(end_date))
    if (n == 0) {
      message(sprintf("[snapshots] No players rated for %s - snapshot skipped", format_id))
    }
  }

  message("[snapshots] Backfill complete")
}
