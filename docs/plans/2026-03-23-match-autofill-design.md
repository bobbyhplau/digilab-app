# Match-by-Match Auto-Fill & Player Matching

**Date:** 2026-03-23
**Status:** Planning
**Target:** v1.9.0 (post-release enhancement)
**Depends on:** Unified Submit Tab (v1.9.0), Match-by-Match Bandai ID redesign (done)

---

## Problem

When a player uploads a match history screenshot, OCR extracts opponent names and member numbers. Currently these are dumped into editable text inputs with no validation or enrichment. The user must manually verify every field. Meanwhile:

1. The tournament already has a `results` table with all participants — we know who played
2. Other players may have already submitted their match history — we have their perspective on the same rounds
3. The `match_player()` function already does fuzzy matching with colored status indicators in the standings grid — but the match-by-match flow doesn't use it

## Goal

After OCR processes a match screenshot, automatically:
- Match opponent names/IDs against known tournament participants
- Pre-fill member numbers from matched players
- Pre-fill game scores from other players' prior submissions (flipped perspective)
- Show colored match indicators (green/yellow/red) so the user knows which opponents were confidently identified

---

## Architecture

### Three layers, each building on the last

```
OCR Output
    │
    ▼
┌─────────────────────────────┐
│  Layer 1: Results Lookup    │  Match opponents against tournament participants
│  (results + players tables) │  Auto-fill member numbers
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│  Layer 2: Matches Lookup    │  Find rounds already submitted by opponents
│  (matches table)            │  Flip W/L to pre-fill game scores
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│  Layer 3: Status Indicators │  Run match_player() for unresolved opponents
│  (match_player + UI)        │  Show green/yellow/red badges
│                             │  Interactive resolution for ambiguous
└─────────────────────────────┘
```

---

## Layer 1: Auto-Fill from `results` Table

### What it does
After OCR extracts opponent names and member numbers, match each opponent against the tournament's participant list. Auto-fill member numbers for matched players.

### Query
```sql
-- Get all participants in this tournament
SELECT p.player_id, p.display_name, p.member_number
FROM results r
JOIN players p ON r.player_id = p.player_id
WHERE r.tournament_id = $1
```

### Matching logic (per OCR row)
1. **Member number match (exact):** If OCR extracted a non-GUEST member number, look for exact match in participants. Highest confidence.
2. **Name match (exact, case-insensitive):** If member number didn't match, try `tolower(ocr_name) == tolower(participant_name)`.
3. **Name match (fuzzy):** If no exact match, use `stringdist` or `agrepl()` with a similarity threshold (>0.8) against participant names only. Much cheaper than DB-level `pg_trgm` since the participant list is small (8-64 players).

### Output per row
- `opponent_player_id`: Matched player ID (or NA)
- `opponent_member_number`: Filled from matched player (or left as OCR value)
- `autofill_source`: "results_exact_member", "results_exact_name", "results_fuzzy_name", or NA

### Where it runs
New helper function `autofill_from_participants()` called in `submit-match-server.R` after OCR parsing, before rendering the review table.

```r
autofill_from_participants <- function(parsed_matches, tournament_id, pool) {
  # Fetch participants
  participants <- safe_query(pool, "...", params = list(tournament_id))

  # For each parsed row, attempt match
  for (i in seq_len(nrow(parsed_matches))) {
    # Try member number first, then exact name, then fuzzy name
    # Fill opponent_player_id and opponent_member_number
  }

  return(parsed_matches)  # with new columns added
}
```

---

## Layer 2: Auto-Fill from `matches` Table

### What it does
For opponents matched in Layer 1, check if they already submitted their match history. If so, we have their perspective on the same round — flip W/L to pre-fill game scores.

### Query
```sql
-- Find rounds where matched opponent submitted their results against our player
SELECT m.round_number, m.games_won, m.games_lost, m.games_tied, m.match_points
FROM matches m
WHERE m.tournament_id = $1
  AND m.player_id = $2       -- the opponent (they submitted)
  AND m.opponent_id = $3     -- our player (they played against us)
```

### Score flipping
If opponent A submitted: `games_won=2, games_lost=1, games_tied=0`
Then from our perspective: `games_won=1, games_lost=2, games_tied=0`

- `our_games_won = opponent_games_lost`
- `our_games_lost = opponent_games_won`
- `our_games_tied = opponent_games_tied` (ties are symmetric)
- `our_match_points`: derive from our W/L (3 if we won majority, 0 if lost, 1 if tied)

### Where it runs
Called after Layer 1, only for rows where `opponent_player_id` is not NA.

```r
autofill_from_prior_matches <- function(parsed_matches, tournament_id, player_id, pool) {
  for (i in seq_len(nrow(parsed_matches))) {
    opp_id <- parsed_matches$opponent_player_id[i]
    if (is.na(opp_id)) next

    prior <- safe_query(pool, "...", params = list(tournament_id, opp_id, player_id))
    if (nrow(prior) == 0) next

    round_match <- prior[prior$round_number == parsed_matches$round[i], ]
    if (nrow(round_match) == 0) next

    # Flip and fill
    parsed_matches$games_won[i] <- round_match$games_lost
    parsed_matches$games_lost[i] <- round_match$games_won
    parsed_matches$games_tied[i] <- round_match$games_tied
    parsed_matches$autofill_source[i] <- paste0(parsed_matches$autofill_source[i], "+matches")
  }
  return(parsed_matches)
}
```

### Edge cases
- **Both players submit:** The `UNIQUE(tournament_id, round_number, player_id)` constraint allows both perspectives. No collision — each player's submission is their own row.
- **OCR round number mismatch:** If OCR parsed round 3 but opponent submitted round 3 with different opponent, the `opponent_id` check prevents false matches.
- **Partial submissions:** Opponent may have submitted only some rounds. Fill what we can, leave rest for manual entry.

---

## Layer 3: Player Matching with Status Indicators

### What it does
For opponents NOT matched in Layer 1 (not in tournament participants), run `match_player()` with full DB scope. Show colored indicators in the review table so the user can see match confidence.

### Matching scope priority
1. **Tournament participants** (Layer 1 — already done by this point)
2. **Scene-scoped `match_player()`:** Use the tournament's store scene_id
3. **Global fallback:** `match_player()` without scene_id

### Status indicators
Reuse the existing `.player-match-indicator` CSS classes from the standings grid:

| Status | Color | Icon | Meaning |
|--------|-------|------|---------|
| `matched` | Green | check-circle | Exact match — player_id linked |
| `ambiguous` | Amber | exclamation-triangle | Multiple players with same name |
| `new_similar` | Cyan | diamond | Fuzzy matches found |
| `new` | Gray | plus-circle | Completely new player |

### UI additions to review table
Each opponent row gets a match indicator badge next to the name input:

```r
# In the review table render (sr_match_results_preview)
div(
  class = "d-flex align-items-center gap-2",
  textInput(paste0("sr_match_opponent_", i), NULL, value = row$opponent_username),
  if (!is.na(row$match_status)) {
    render_match_indicator(row$match_status, row$opponent_username, row$opponent_player_id)
  }
)
```

### Ambiguous resolution
When status is "ambiguous" or "new_similar", clicking the indicator opens a resolution modal (same pattern as standings grid `sr_resolve_match_modal`):

- Shows candidate list with player names, member numbers, home scenes
- User picks the correct player or confirms "Create New"
- Selection updates the row's `opponent_player_id` and `match_status`

### Where it runs
After Layer 1+2, for rows where `opponent_player_id` is still NA:

```r
enrich_with_match_player <- function(parsed_matches, tournament_id, pool) {
  # Get scene_id for the tournament
  scene_id <- get_tournament_scene(pool, tournament_id)

  for (i in seq_len(nrow(parsed_matches))) {
    if (!is.na(parsed_matches$opponent_player_id[i])) next  # already matched

    name <- parsed_matches$opponent_username[i]
    member <- parsed_matches$opponent_member_number[i]
    if (nchar(name) == 0) next

    info <- match_player(name, pool, member_number = member, scene_id = scene_id)
    parsed_matches$match_status[i] <- info$status

    if (info$status == "matched") {
      parsed_matches$opponent_player_id[i] <- info$player_id
      parsed_matches$opponent_member_number[i] <- info$member_number %||% parsed_matches$opponent_member_number[i]
    }
    # ambiguous/new_similar: store candidates for resolution UI
  }
  return(parsed_matches)
}
```

---

## Data Flow Summary

```
User uploads screenshot
        │
        ▼
  parse_match_history(ocr_text)
        │  Returns: round, opponent_username, opponent_member_number,
        │           games_won, games_lost, games_tied, match_points
        ▼
  autofill_from_participants(parsed, tournament_id)     ← Layer 1
        │  Adds: opponent_player_id, fills member_number
        ▼
  autofill_from_prior_matches(parsed, tournament_id, player_id)  ← Layer 2
        │  Fills: games_won/lost/tied from flipped opponent data
        ▼
  enrich_with_match_player(parsed, tournament_id)       ← Layer 3
        │  Adds: match_status for unresolved rows
        ▼
  rv$sr_match_ocr_results <- parsed
        │
        ▼
  Render review table with:
    - Pre-filled fields (editable)
    - Match indicators (green/yellow/red)
    - Resolution UI for ambiguous matches
        │
        ▼
  User reviews, corrects, submits
```

---

## New Columns on `parsed_matches` Data Frame

Added by auto-fill layers (not persisted to DB — used only for review UI):

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| `opponent_player_id` | integer | Layer 1/3 | Matched player ID |
| `match_status` | character | Layer 1/3 | "matched", "ambiguous", "new_similar", "new" |
| `autofill_source` | character | Layer 1/2 | Tracking: "results_exact_member", "results_fuzzy_name+matches", etc. |
| `match_candidates` | list | Layer 3 | Candidate data frames for ambiguous/new_similar rows |

---

## Files Modified

| File | Changes |
|------|---------|
| `server/submit-match-server.R` | Add auto-fill calls after OCR, update review table render with indicators |
| `R/admin_grid.R` (or new `R/match_autofill.R`) | `autofill_from_participants()`, `autofill_from_prior_matches()`, `enrich_with_match_player()` |
| `www/custom.css` | Minor — reuse existing `.player-match-indicator` styles, may add match-specific row highlights |

---

## Implementation Order

1. **Layer 1** — `autofill_from_participants()` + wire into OCR processing
2. **Layer 2** — `autofill_from_prior_matches()` + wire after Layer 1
3. **Layer 3** — `enrich_with_match_player()` + indicator rendering + resolution modal
4. **Testing** — Upload screenshots for tournaments with known participants and prior match submissions

Each layer is independently useful and can be shipped separately.

---

## Verification Checklist

- [ ] OCR opponents are matched against tournament participants (Layer 1)
- [ ] Member numbers auto-filled from matched participants
- [ ] Game scores pre-filled from prior opponent submissions (Layer 2)
- [ ] Flipped W/L is correct (our wins = their losses)
- [ ] Unmatched opponents show colored indicators (Layer 3)
- [ ] Ambiguous matches have resolution modal
- [ ] All auto-filled fields remain editable
- [ ] Submission still works correctly with auto-filled data
- [ ] No regression: tournaments with no prior data work as before (all fields blank/OCR-only)
- [ ] Performance: auto-fill queries complete quickly (small participant lists, indexed columns)
