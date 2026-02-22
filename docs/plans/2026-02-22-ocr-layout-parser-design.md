# OCR Layout-Aware Parser Design

**Date:** 2026-02-22
**Scope:** Replace text-based OCR parser with layout-aware parser using GCV bounding boxes
**Target Version:** v0.29

---

## Problem

The current OCR parser (`R/ocr.R` > `parse_tournament_standings()`) extracts plain text from Google Cloud Vision and scans it line-by-line to reconstruct player data. This approach loses the visual table structure of Bandai TCG+ standings screenshots, causing:

1. **Jumbled ordering in multi-screenshot merges** — Without real ranking numbers, combining overlapping screenshots produces incorrect placement order (e.g., 1, 2, 3, 8, 9, 10 instead of 1-10)
2. **Skipped players shift placements** — If OCR misses a player, all subsequent placements shift up incorrectly (ranks 1-3, 5-8 become 1-7)
3. **Points misassignment** — Numbers can be attributed to the wrong field (a "6" could be ranking, points, or even a username)
4. **Numeric username confusion** — Usernames like "1596" or "K2" are ambiguous in a text stream but unambiguous when you know they're in the username column
5. **Different phone dimensions** — Screenshots from different devices have different layouts that the text parser can't normalize

## Solution

Use Google Cloud Vision's **word-level bounding box coordinates** to understand the visual grid structure. Each text element's position on screen tells us which column it belongs to (ranking, username, points), eliminating ambiguity.

---

## Design

### 1. GCV API Changes

**File:** `R/ocr.R` > `gcv_detect_text()`

The GCV `DOCUMENT_TEXT_DETECTION` response includes:
- `textAnnotations[0].description` — full text (what we use today)
- `textAnnotations[1..N]` — individual words with `boundingPoly.vertices` (4 corner coordinates)

Modify `gcv_detect_text()` to return both:

```r
list(
  text = "full text string...",
  annotations = data.frame(
    text = character(),   # the word/phrase
    x_min = numeric(),    # left edge
    y_min = numeric(),    # top edge
    x_max = numeric(),    # right edge
    y_max = numeric()     # bottom edge
  ),
  image_width = numeric(),  # for normalization
  image_height = numeric()
)
```

The API call itself doesn't change — we just extract more data from the existing response. Image dimensions come from the bounding box of `textAnnotations[0]` (the full-page annotation).

The existing text-based parser continues to work using `$text` as a fallback path.

### 2. Layout Detection Algorithm

**File:** `R/ocr.R` > new function `parse_standings_layout()`

The Bandai TCG+ standings screen has a consistent column layout:

| Column | Content | Approximate X range |
|--------|---------|-------------------|
| Ranking | Number in circle | 0-15% |
| User Name | Username + Member Number | 15-60% |
| Win Points | Numeric | 60-75% |
| OMW% | Percentage (ignored) | 75-90% |
| GW% etc. | Percentage (ignored) | 90-100% |

**Algorithm steps:**

1. **Normalize coordinates** — Convert all bounding box positions to percentages of image width/height. This makes the algorithm resolution-independent (handles different phones).

2. **Detect rows by Y-clustering** — Group all text blocks whose vertical centers are within ~2-3% of image height. Each cluster = one visual row. Sort rows top-to-bottom.

3. **Identify header row** — Look for a row containing keywords: "Ranking", "User Name", "Points", "OMW". Use the X-positions of these headers to define exact column boundaries.

4. **Fallback column boundaries** — If no header found (screenshot scrolled past it), use heuristic boundaries based on the known Bandai layout: ranking < 15%, username 15-60%, points 60-75%.

5. **Assign text blocks to columns** — For each non-header row, categorize each text block by which column boundary its X-center falls within.

6. **Parse structured rows** — For each row:
   - **Ranking**: Number from ranking column (validate: integer 1-64)
   - **Username**: First text line from username column that matches username pattern (letters, numbers, underscores, dots, apostrophes)
   - **Member number**: Text matching `Member Number \d{10}` or `GUEST\d{5}` pattern from username column
   - **Points**: Number from points column (validate: integer 0-99)

7. **Filter noise rows** — Skip rows that are: status bar (top of screen), navigation bar (bottom), header row, copyright text. These are identified by Y-position (top/bottom 8% of image) and content patterns.

### 3. Multi-Screenshot Merging

**File:** `server/public-submit-server.R` (deduplication section, ~lines 231-292)

**Current approach:** Combines all results, deduplicates by member number then username, sorts by fragile `placement` field, re-numbers sequentially.

**New approach:**

1. Each screenshot returns rows with **real ranking numbers** from the visual layout.

2. **Merge by member number** (primary key). When the same player appears in overlapping screenshots (e.g., Delzama at rank 9 in both screenshot 1 and 2), keep one entry. The ranking numbers agree, so it doesn't matter which.

3. **GUEST member number handling** — Multiple players share "GUEST99999". For these, dedup falls back to **username matching** (case-insensitive). Different usernames with GUEST numbers are treated as different people.

4. **Sort by ranking number** — Use the actual ranking from the Bandai app, not a sequential re-assignment. This directly fixes the jumbled ordering issue.

5. **Preserve gaps** — If ranking 4 is missing (OCR missed that player), create a blank row at position 4 instead of shifting everyone up. The user fills it in during review.

### 4. GUEST Player Database Lookup

**File:** `server/public-submit-server.R` (player pre-matching section, ~lines 297-347)

Current behavior: GUEST member numbers are cleared to NA before matching, and these players are marked as "new".

**Enhanced flow for GUEST players:**

1. Clear the GUEST member number (don't store fake IDs)
2. Query database by username: `SELECT player_id, display_name, member_number FROM players WHERE LOWER(display_name) = LOWER(?)`
3. If found **with a real member number** → Match to existing player, populate the member number field in the review UI (user sees it pre-filled)
4. If found **without a member number** → Match to existing player (they've been submitted as GUEST before too), status = "matched"
5. If not found → Truly new player, status = "new"

This handles the common case where a regular player signs up last-minute in-store and doesn't get their Bandai ID collected.

### 5. Rank-Based Validation

**File:** `server/public-submit-server.R` (after merge/dedup)

Use ranking numbers + declared player count for smarter validation:

1. **Max rank > declared count** — Auto-correct the player count upward. Notify: "Screenshots show 18 players but you entered 14. Updated to 18." Screenshots are authoritative.

2. **Max rank < declared count** — Expected (bottom of standings not captured). Pad blank rows from max_rank+1 to declared_count. Notify: "Parsed 14 of 18 players — fill in remaining manually."

3. **Rank gaps** — Specific feedback: "Player at rank 4 couldn't be read — please fill in manually." Create blank row at the correct position.

4. **All ranks present** — "All 18 players found."

### 6. Fallback Strategy

**File:** `R/ocr.R`

1. **Try layout-aware parser first** — Call `parse_standings_layout(annotations, total_rounds)`
2. **Validate result** — Did we find at least 1 player with a ranking, username, and member number?
3. **If validation fails** — Fall back to existing `parse_tournament_standings(text, total_rounds)`. Log: `[OCR] Layout parser failed, falling back to text parser`
4. **Log which parser was used** — `[OCR] Using layout parser (N players found)` for monitoring

Reasons the layout parser might fail:
- Heavily cropped or rotated screenshot
- GCV returns poor bounding box data
- Non-Bandai screenshot uploaded by mistake
- Future Bandai app layout changes

The text parser remains as permanent fallback — it's battle-tested and handles many cases well enough.

### 7. Partial Screenshot Handling

- **Player row partially visible at bottom** (username visible, member number cut off): Skip the incomplete row. The next screenshot should have it fully visible.
- **Final player cut off on last screenshot** (13players_cutoff test case): Create blank row at that ranking position. The ranking number is visible even if other data isn't, so we know where the gap is.
- **Header cut off at top of scrolled screenshot**: Fall back to heuristic column boundaries (Section 2, step 4).

---

## Test Infrastructure

### Ground Truth CSVs

For each test folder in `screenshots/standings/`, create an `expected.csv`:

```csv
rank,username,member_number,points
1,Happycat,0000172742,12
2,Lil Winr,0000015329,9
```

Values are read directly from the screenshots (we can see them visually).

### Batch Test Updates

**File:** `scripts/batch_test_ocr.R`

- Save bounding box annotation data alongside OCR text (for offline re-testing without API calls)
- Compare parsed output against `expected.csv` ground truth
- Report per-field accuracy: ranking correct, username correct, member number correct, points correct
- Summary: "8/8 test cases passing, 142/144 fields correct (98.6%)"

### Test Matrix

| Scenario | Folder | Tests |
|----------|--------|-------|
| Single screenshot, all visible | 8players_3rounds | Basic parsing |
| Single screenshot, 9 players | 9players_4rounds | Points accuracy |
| Single screenshot, cutoff | 13players_cutoff | Partial row handling |
| Multi-screenshot, same phone | 18players_01 | Overlap dedup + rank merge |
| Multi-screenshot, same phone | 18players_02 | Second same-phone test |
| Multi-screenshot, different phones | 14players_diffphones | Resolution independence, numeric usernames, GUEST dedup |
| Multi-screenshot, different phones | 17players_diffphones | Second cross-phone test |

---

## Files Changed

| File | Change |
|------|--------|
| `R/ocr.R` | New `parse_standings_layout()`, modify `gcv_detect_text()` return value |
| `server/public-submit-server.R` | Updated merge logic, GUEST lookup, rank-based validation |
| `scripts/batch_test_ocr.R` | Ground truth comparison, annotation data saving |
| `scripts/test_ocr.R` | Support for new parser, comparison mode |
| `screenshots/standings/*/expected.csv` | Ground truth files (new) |

## Out of Scope

- Match history parser (`parse_match_history()`) — different screen layout, separate effort
- OMW%/GW% extraction — not needed per requirements
- Changes to the upload UI — no UX changes, just better data behind the scenes
