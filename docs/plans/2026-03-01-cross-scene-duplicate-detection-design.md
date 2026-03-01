# Cross-Scene Player Duplicate Detection Design

**Date:** 2026-03-01
**Status:** Approved
**Author:** Claude (with Michael)

## Overview

An R script that analyzes the database for potential player duplicates caused by name collisions across different local scenes. Generates a markdown report documenting findings for manual review.

**Context:** Scene admins have been backfilling historical data for their scenes. Players with common names may have been incorrectly merged across scenes (e.g., "John" in DFW merged with "John" in Houston). This analysis identifies these collisions before we proceed with rating system improvements.

## Scope

**What it does:**
- Finds players with tournament results in multiple non-Online scenes
- Flags suspicious patterns (few results in one scene, many in another)
- Outputs a markdown report with player details, store breakdown, and recommendations

**What it doesn't do (yet):**
- Automatically fix or split players
- Modify any database records
- Touch Online/Limitless tournament data

## Detection Logic

### Step 1: Map players to scenes

```
For each player:
  → Get all their results
  → Join results → tournaments → stores → scenes
  → Exclude stores where scene is "Online" or scene_type = 'online'
  → Count results per scene
```

### Step 2: Flag potential duplicates

```
Flag players where:
  - They have results in 2+ distinct local scenes
  - AND at least one scene has ≤3 results (suggests accidental merge, not regular traveler)
```

The "≤3 results" threshold is a starting point - can be adjusted after reviewing initial results.

### Step 3: Enrich flagged players

```
For each flagged player, collect:
  - display_name, player_id, member_number (Bandai ID)
  - Per-scene breakdown: scene name, store names, result count, date range
  - Total events played
```

## Report Structure

**File location:** `docs/analysis/YYYY-MM-DD-cross-scene-duplicates.md`

### Sections

```markdown
# Cross-Scene Player Duplicate Analysis
**Generated:** 2026-03-01
**Total players analyzed:** X
**Players flagged:** Y

## Summary
- X players have results in multiple local scenes
- Y players flagged as potential duplicates (≤3 results in one scene)
- Z players have Bandai IDs that may need clearing

## Flagged Players

### 1. [Player Name] (player_id: 123)
**Bandai ID:** 0000123456 (or "None")
**Total events:** 15

| Scene | Store(s) | Results | Date Range |
|-------|----------|---------|------------|
| DFW | Common Ground Games, Madness | 14 | 2025-10 to 2026-02 |
| Houston | Asgard Games | 1 | 2026-01-15 |

**Recommendation:** Likely duplicate - single Houston result suggests name collision

### 2. [Next Player]...

## Multi-Scene Players (Not Flagged)
Players with results in multiple scenes but consistent activity (likely legitimate travelers)

## Next Steps
- [ ] Review flagged players manually
- [ ] Decide: split into separate players or confirm as same person
- [ ] Clear Bandai IDs where needed to prevent future re-merging
```

## Script Details

**File location:** `scripts/analysis/detect_cross_scene_duplicates.R`

**How to run:**
```r
# From R console
source("scripts/analysis/detect_cross_scene_duplicates.R")

# Generates: docs/analysis/2026-03-01-cross-scene-duplicates.md
```

**Dependencies:**
- Uses existing `db_pool` connection pattern (loads `.env` credentials)
- No new packages needed - just base R + DBI/RPostgres

**No side effects:**
- Read-only database queries
- Only writes the markdown report file
- Safe to run multiple times

## Future Work

After reviewing the analysis report:

1. **Fix tooling** - Build scripts to split duplicate players based on findings
2. **Prevention** - Enhance player matching in the app to be scene-aware
3. **Rating recalculation** - Proceed with rating system fixes once data is clean

## Related

- `ROADMAP.md` - DI1 (Player name collision resolution), DI2 (Player disambiguation UI)
- `docs/plans/2026-02-01-rating-system-design.md` - Rating methodology (to be fixed after data cleanup)
