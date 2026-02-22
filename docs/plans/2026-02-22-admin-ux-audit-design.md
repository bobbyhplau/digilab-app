# REV1: Admin Pages & Submission Flow UX Audit

**Date:** 2026-02-22
**Scope:** All admin pages (Enter Results, Edit Tournaments/Players/Decks/Stores/Formats) and public Upload Results flow
**Target Version:** v0.28

---

## Goals

1. Fix blockers that prevent multi-region expansion
2. Improve error messages for public-facing flows
3. Standardize help text and UX patterns across admin pages
4. Clean up debug code and stale patterns

---

## Blocker: Texas-Only State Selection (Edit Stores)

### Problem

Physical store form has state hardcoded to Texas only:

```r
# admin-stores-ui.R, line 47
selectInput("store_state", "State", choices = c("TX" = "TX"), selected = "TX")
```

Server also defaults to "TX" in geocoding fallback:

```r
# admin-stores-server.R, ~line 152-174
address_parts <- c(address_parts, if (nchar(input$store_state) > 0) input$store_state else "TX")
```

### Fix

Replace the single-value dropdown with a full US states list. Add "Other" option for international stores.

**Files:** `views/admin-stores-ui.R`, `server/admin-stores-server.R`

---

## Blocker: OCR Error Messages Too Technical (Upload Results)

### Problem

Public users see developer-facing error messages:

- `"Could not extract player data from screenshots. No text was extracted. Check that GOOGLE_CLOUD_VISION_API_KEY is set in .env"`
- `"Could not extract player data from screenshots. OCR extracted text but parsing failed. Check R console for debug output."`

### Fix

Replace with user-friendly messages:

- No text extracted: `"Could not read the screenshots. Make sure the image is clear and shows the Bandai TCG+ standings screen. If this keeps happening, try a different screenshot or contact us."`
- Parsing failed: `"We extracted text from the image but couldn't identify player data. Make sure the screenshot shows the final standings with placements and usernames visible."`

Keep the technical details in `message()` console logs for debugging.

**Files:** `server/public-submit-server.R`

---

## High Priority

### H1: Record Format Not Explained (Enter Results)

**Problem:** Radio button "Points" vs "W-L-T" with no explanation. Users don't know which to choose.

**Fix:** Add helper text below the radio buttons:
- `"Points: Total match points (e.g., from Bandai TCG+ standings)"`
- `"W-L-T: Individual wins, losses, and ties"`

**Files:** `views/admin-results-ui.R`

---

### H2: Release Event Special Behavior Undocumented (Enter Results)

**Problem:** When event type is "Release Event", deck selector is hidden and all results get "UNKNOWN" archetype. This happens silently.

**Fix:** Add an info callout that appears conditionally when "Release Event" is selected:
`"Release events use sealed product, so deck archetypes are set to Unknown automatically."`

**Files:** `views/admin-results-ui.R` or `server/admin-results-server.R` (conditional UI)

---

### H3: Player Matching Not Explained (Upload Results)

**Problem:** Step 2 shows "Matched" / "New" badges next to players with no explanation of how matching works.

**Fix:** Add a brief explanation above the results table in Step 2:
`"Players are matched by member number first, then by username. Matched = existing player in database. New = will be created on submit. Click the X on a matched player to create them as new instead."`

**Files:** `server/public-submit-server.R` (Step 2 UI output)

---

## Medium Priority

### M1: Inconsistent Help Text Across Admin Pages

**Current state:**

| Page | Has info hint box? |
|------|--------------------|
| Enter Results | No |
| Edit Tournaments | No |
| Edit Decks | Yes |
| Edit Stores | Yes |
| Edit Formats | Yes |
| Edit Players | No |

**Fix:** Add info hint boxes to the 3 pages missing them:

- **Enter Results:** `"Create a new tournament and enter player results. Use the grid to add placements, player names, records, and deck archetypes."`
- **Edit Tournaments:** `"Select a tournament from the list to edit details or manage results. Use 'View/Edit Results' to modify individual placements."`
- **Edit Players:** `"Select a player to edit their display name. Players are created automatically when tournament results are submitted."`

**Files:** `views/admin-results-ui.R`, `views/admin-tournaments-ui.R`, `views/admin-players-ui.R` (if exists, otherwise the relevant view file)

---

### M2: Debug Message Cleanup

**Problem:** Production-grade `message()` calls left in admin code that aren't behind a debug flag.

**Locations:**

- `server/admin-decks-server.R:376` — `message(sprintf("UPDATE archetype: id=%d, name=%s, color=%s", ...))`
- `server/admin-decks-server.R:474` — `message(sprintf("DELETE archetype triggered: id=%d", ...))`
- `server/admin-decks-server.R:488` — `message(sprintf("Executing DELETE for archetype_id=%d", ...))`
- `server/public-submit-server.R:174-176` — File processing debug messages
- `server/public-submit-server.R:188` — Parsed results debug message

**Fix:** Remove or wrap in a `DEBUG` flag. These aren't harmful but add console noise in production.

**Files:** `server/admin-decks-server.R`, `server/public-submit-server.R`

---

### M3: Multi-Color Checkbox Lacks Explanation (Edit Decks)

**Problem:** "Multi-color deck" checkbox has no inline help. Users don't know what it means vs. primary/secondary colors.

**Fix:** Add a small help text: `"Check for decks with 3+ colors. For dual-color decks, use Primary and Secondary color instead."`

**Files:** `views/admin-decks-ui.R`

---

## Low Priority

### L1: Terminology Inconsistencies

Across pages, the same concepts use different labels:

| Concept | Variants Used |
|---------|---------------|
| Deck Archetype | "Deck", "Archetype", "deck archetype" |
| Format | "Format", "Format/Set", "Card Set" |

**Fix:** Standardize user-facing labels to "Deck" (short) and "Format" (short). Keep "deck archetype" only in admin contexts where precision matters.

---

### L2: Geocoding Help Text (Edit Stores)

**Problem:** `"Location will be automatically geocoded from address"` — users may not know what geocoding means.

**Fix:** Change to: `"Map coordinates will be set automatically from the address"`

**Files:** `views/admin-stores-ui.R`

---

### L3: Scene Filtering Visibility for Regular Admins

**Problem:** Regular admins see filtered data but may not understand why. The "Show all scenes" toggle is only for superadmins.

**Fix:** Add a small badge or label showing which scene is currently filtering the admin view: `"Showing data for: [Scene Name]"`. Already partially implemented — verify it's consistently shown.

**Files:** `server/admin-tournaments-server.R`, `server/admin-players-server.R`

---

## Out of Scope (Deferred)

These items came up in the audit but are better addressed post-v0.28:

- **Fragile `tags$script()` field hiding** — Replace with `shinyjs::hidden()` or `conditionalPanel()` throughout admin pages (refactoring task, not content/UX)
- **Player merge tool for admin** — Edit Players only supports rename, not merge (feature request)
- **Match History tab completion** — Upload Results > Match History has incomplete server-side implementation
- **Deck request workflow feedback** — No status feedback to users who request new deck archetypes (requires notification system)

---

## Implementation Order

1. **Blockers first:** TX state fix + OCR error messages
2. **High priority:** Record format help, release event callout, player matching explanation
3. **Medium:** Help text standardization, debug cleanup, multi-color explanation
4. **Low:** Terminology, geocoding help, scene filtering visibility
