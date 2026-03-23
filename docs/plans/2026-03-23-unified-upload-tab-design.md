# Unified Upload Tab & Results Redesign

**Date:** 2026-03-23
**Version Target:** v1.9.0
**Roadmap IDs:** `results-upload-redesign`, `grid-ux-improvements`, `edit-grid-record-format-switch`
**Status:** Design

## Summary

Consolidate the public **Submit Results** tab and admin **Enter Results** tab into a single **Submit Results** tab with a card-picker landing page. All result entry methods live under one roof. Public users see evidence-based methods; admin login unlocks manual/bulk entry. The tab appears in the public sidebar when logged out and moves to the Admin sidebar section when logged in — same content, same tab ID.

## Goals

- Eliminate the split between public Submit and admin Enter Results
- Reduce duplicated code (tournament creation, decklist saving, duplicate detection, player matching UI)
- Unified Step 1 (tournament details) and Step 3 (decklists) with method-specific Step 2
- Card-picker landing page makes entry methods discoverable
- Permission-gated cards (admin-only methods hidden for public users)
- Grid UX improvements: explicit Add Player button, editable placement (replaces drag-to-reorder), tied placements
- W-L-T override toggle for points-mode tournaments (admin-only)

## Non-Goals (deferred)

- Mobile-optimized admin grids (separate roadmap item `mobile-admin-tabs`)
- Drag-to-reorder via SortableJS (editable placement solves this more simply; can revisit if organizers request tactile reordering)

---

## Card Picker Landing Page

When the user navigates to Submit Results, they see a grid of entry-method cards:

| Card | Access | Description |
|------|--------|-------------|
| **Bandai TCG+ Upload** | Everyone | Upload standings screenshots (OCR) or CSV export from the Bandai TCG+ app. CSV export is available to Tournament Organizers (TOs) in the Bandai TCG+ platform after the tournament ends. |
| **Paste from Spreadsheet** | Admin | Paste tab-separated data in flexible formats (name, points, W/L/T, deck) |
| **Manual Entry** | Admin | Empty grid — type everything manually |
| **Match-by-Match** | Everyone | Upload personal match history screenshot (OCR) |
| **Add Decklists** | Everyone | Submit decklist URLs for an existing tournament via Bandai ID lookup |
| **Match Results CSV** | Admin (Coming Soon) | Upload CSV of full match-by-match results. CSV export available to TOs in the Bandai TCG+ platform. Placeholder card — not yet implemented. |

Admin-only cards are hidden (not greyed out) for public users. The "Coming Soon" card is visible but disabled for its audience (admins).

### Card Layout

```
Row 1: [Bandai TCG+ Upload]     [Paste from Spreadsheet 🔒]
Row 2: [Manual Entry 🔒]         [Match-by-Match]
Row 3: [Add Decklists]           [Match Results CSV 🔒 Coming Soon]
```

On mobile, cards stack single-column.

### Card UI Details

Each card should include:
- **Icon** (top)
- **Title** (bold)
- **Description** (1-2 lines explaining what it does)
- **Helper text** (small muted text with context where useful)

Helper text examples:
- Bandai TCG+ Upload: "TOs can export standings CSV from the Bandai TCG+ platform after the event"
- Match Results CSV: "TOs can export match data from the Bandai TCG+ platform after the event"
- Add Decklists: "Look up your tournaments by Bandai Member ID"

---

## Shared Wizard Flow (Option A)

All entry methods (except Add Decklists and Match-by-Match) follow a shared 3-step wizard:

```
Card Picker → Step 1: Tournament Details (shared) → Step 2: Results Entry (method-specific) → Step 3: Confirm & Decklists (shared)
```

### Step 1: Tournament Details (Shared)

One unified form replacing the two current implementations. Fields:

| Field | Required | Notes |
|-------|----------|-------|
| Scene | Yes | Dropdown, scoped to admin's scenes if logged in |
| Store | Yes | Filtered by scene. Includes "Store not listed? Request it" link |
| Date | Yes | Date picker |
| Event Type | Yes | Dropdown (Weekly, Regional, etc.) |
| Format | Yes | Dropdown from formats table |
| Total Players | Yes | Numeric input |
| Total Rounds | Yes | Numeric input |
| Record Format | Yes (admin only) | Radio: Points (default) or W-L-T. Hidden for public (locked to Points) |

All required fields show asterisk indicators (matching current admin styling). Visual styling follows the current public Submit tab layout (cleaner card-based form).

#### Duplicate Tournament Detection (Unified)

On "Continue" / "Create Tournament", check for existing tournament with same `store_id + event_date + event_type`:

```sql
SELECT t.tournament_id, t.player_count, t.event_type,
       (SELECT COUNT(*) FROM results WHERE tournament_id = t.tournament_id) as result_count,
       s.name as store_name
FROM tournaments t
JOIN stores s ON t.store_id = s.store_id
WHERE t.store_id = $1 AND t.event_date = $2 AND t.event_type = $3
```

**If duplicate found, show modal:**

- Info: store name, date, player count, results entered count, event type
- **Public users**: "View Results" (navigates to tournament in Tournaments tab) + "Cancel"
- **Admin users**: "View/Edit Existing" (opens edit grid for that tournament) + "Create Anyway" + "Cancel"

### Step 2: Results Entry (Method-Specific)

Each method renders its own Step 2 UI:

**Bandai TCG+ Upload:**
- File upload accepting PNG/JPG/WEBP (screenshots) and CSV
- Multiple file support for screenshots
- Auto-detects file type and routes to OCR pipeline or CSV parser
- After processing: review grid with player matching badges (Matched/Similar/New)
- Enhancement: Parse `Deck URLs` column from Bandai CSV and pre-fill Step 3

**Paste from Spreadsheet (admin):**
- Modal with textarea and format examples
- Supported formats: Name, Name+Points, Name+Points+Deck, Name+W/L/T, Name+W/L/T+Deck
- Enhancement: Add Name+MemberID+Points and Name+MemberID+W/L/T formats
- Enhancement: Auto-detect and skip header rows
- "Fill Grid" populates the review/edit grid
- Player matching runs on fill

**Manual Entry (admin):**
- Empty editable grid (128 rows)
- Inline deck dropdown, player name, member number, points/W-L-T
- Player matching on blur (real-time)

All methods converge on the same review grid component (`render_grid_ui` from `R/admin_grid.R`) before submission.

### Grid UX Improvements (applies to all methods)

These improvements apply to the shared `render_grid_ui` component used across all entry methods.

#### Explicit "Add Player" Button (everyone)

Replace the current fixed-size grid (pre-allocated blank rows) with a dynamic grid:
- OCR/paste methods: start with only filled rows
- Manual entry: start with a small default (e.g., 8 rows)
- "Add Player" button at the bottom appends a blank row and re-renders
- Delete button (already exists) removes a row and re-renders
- `init_grid_data(player_count)` becomes the starting size, not the fixed size

#### Editable Placement (everyone)

Currently placement is a static ordinal badge (`grid_ordinal(row$placement)`). Change to:
- `numericInput` for placement, pre-filled with current position
- On submit/save: re-sort grid by placement values
- Allows fixing OCR misplacements by typing the correct number
- Replaces the need for drag-to-reorder — simpler and works on all devices

#### Tied Placements (everyone)

With editable placement, users can assign the same placement to multiple players:
- Allow non-sequential placement values in validation (e.g., 1, 2, 2, 4)
- Auto-adjust downstream placements: if two players tie for 3rd, next is 5th
- Visual indicator: shared placement badge styling for tied rows
- Rating system already handles draws (0.5 score), so backend is ready

#### W-L-T Override Toggle (admin only)

For tournaments entered in points mode, admins need to correct auto-derived W/L/T:
- Add a toggle in the grid header area: "Show W/L/T columns"
- Hidden for public users (points mode is definitive from Bandai export)
- When toggled on: show W, L, T columns alongside Points
- W/L/T values override the auto-calculated derivation (wins = pts/3, ties = pts%3)
- Points column remains visible and auto-updates from W/L/T when override is active
- Solves the ambiguous derivation problem (e.g., 3 points could be 1W-0L-0T or 0W-0L-3T)

### Step 3: Confirm & Decklists (Shared)

Identical to current Step 3 in both flows (already uses shared `render_decklist_entry()` and `save_decklist_urls()`):

- Read-only results table showing submitted data
- Optional decklist URL inputs per player (validated against domain allowlist)
- "Skip" or "Save & Done" buttons
- Doubles as a confirmation screen for the submission

### Deck Request Queue

Available to all methods. When a user's deck isn't in the dropdown, they can request a new archetype. Request goes to admin queue for approval. This is already implemented — just ensure it's wired into the unified grid component for all methods.

---

## Match-by-Match Flow (Separate Wizard)

Not part of the shared 3-step wizard — has its own flow:

1. Select tournament (store → tournament dropdown)
2. Enter player info (username + member number)
3. Upload match history screenshot
4. OCR processing → review table (editable opponent names, games W-L-T, match points)
5. Submit → saves to `matches` table

Unchanged from current implementation, just relocated under the unified tab.

---

## Add Decklists Flow (New)

Standalone flow for retroactive decklist URL submission:

1. User clicks "Add Decklists" card
2. Prompt: "Enter your Bandai Member ID" (10-digit input field)
3. Look up player by member number → show their tournament history (tournament date, store, format, placement)
4. User selects a tournament → shows results table for that tournament
5. User enters their decklist URL for their row
6. Submit → saves via existing `save_decklist_urls()` infrastructure

**Design notes:**
- Bandai ID as lightweight identity gate — no login required, but prevents random edits
- Only the submitter's own row is editable (matched by player_id from Bandai ID lookup)
- Could allow editing URLs for other players in the same tournament if they have the URL (stretch goal)
- Does not expose other players' Bandai IDs anywhere in the UI

---

## Navigation Architecture

### Tab Placement

Single `nav_panel_hidden(value = "submit_results")` in the main content navset.

Two sidebar links pointing to the same content panel:

```r
# Public section — visible when NOT admin
conditionalPanel(
  condition = "!output.is_admin",
  actionLink("nav_submit_results", icon("upload"), "Submit Results",
             class = "nav-link-sidebar")
)

# Admin section — visible when admin
conditionalPanel(
  condition = "output.is_admin",
  actionLink("nav_admin_submit_results", icon("upload"), "Submit Results",
             class = "nav-link-sidebar")
)
```

Both `observeEvent` handlers navigate to `"submit_results"` and sync the appropriate sidebar highlight.

### Tab ID Migration

Old IDs → New ID:

| Old | New |
|-----|-----|
| `submit` (public) | `submit_results` |
| `admin_results` (admin) | `submit_results` |
| `nav_submit` | `nav_submit_results` / `nav_admin_submit_results` |
| `nav_admin_results` | `nav_admin_submit_results` |

Update all cross-tab navigation references, sidebar sync calls, and any JS that references these IDs.

---

## Server Architecture

### File Structure

```
server/
├── submit-shared-server.R      # Tournament creation, duplicate detection,
│                                # decklist saving, wizard navigation, card picker,
│                                # Step 1 form logic, Step 3 logic
├── submit-upload-server.R       # Bandai TCG+ screenshot OCR + CSV parsing
│                                # (extracted from public-submit-server.R)
├── submit-grid-server.R         # Paste from spreadsheet + manual grid entry
│                                # (extracted from admin-results-server.R)
├── submit-match-server.R        # Match-by-match personal history
│                                # (extracted from public-submit-server.R)
└── submit-decklist-server.R     # Add Decklists standalone flow (new)
```

### Removed Files

```
server/public-submit-server.R    → split into submit-upload-server.R + submit-match-server.R
server/admin-results-server.R    → split into submit-grid-server.R
views/submit-ui.R                → replaced by views/submit-results-ui.R
views/admin-results-ui.R         → replaced by views/submit-results-ui.R
```

### UI File

```
views/
└── submit-results-ui.R          # Card picker + shared Step 1/3 + method-specific Step 2 layouts
```

### Shared Utilities

`R/admin_grid.R` (consider renaming to `R/results_grid.R`):
- `render_grid_ui()` — shared grid component
- `sync_grid_inputs()` — grid state sync
- `match_player()` — player identity matching
- `parse_paste_data()` — paste parser (enhanced with member ID support, header detection)
- `build_deck_choices()` — deck dropdown builder
- `render_decklist_entry()` — decklist URL input UI
- `save_decklist_urls()` — decklist URL persistence
- `load_decklist_results()` — load results for decklist entry

### Loading Strategy

- `submit-shared-server.R` and `submit-upload-server.R` are always loaded (public methods)
- `submit-match-server.R` is always loaded (public method)
- `submit-decklist-server.R` is always loaded (public method)
- `submit-grid-server.R` is lazy-loaded on admin login (admin-only methods), following the existing `admin_modules_loaded` pattern

---

## Paste from Spreadsheet Enhancements

Current 5 formats + 2 new:

| Columns | Format |
|---------|--------|
| 1 | Name |
| 2 | Name + Points |
| 3 | Name + Points + Deck |
| 4 | Name + W/L/T |
| 5+ | Name + W/L/T + Deck |
| **New: 3** | **Name + MemberID + Points** (detect: col 2 is 10-digit number) |
| **New: 5+** | **Name + MemberID + W/L/T** |

Header row detection: skip first row if it matches known headers (Name, Player, Points, Wins, Losses, etc.).

---

## Bandai CSV Enhancement

The Bandai TCG+ CSV export includes a `Deck URLs` column that is currently not parsed. Enhancement: extract URLs during CSV parsing and pre-fill Step 3 decklist inputs. This gives users decklists "for free" when uploading via CSV.

---

## Migration Checklist

- [ ] Create `views/submit-results-ui.R` with card picker + shared wizard
- [ ] Create `server/submit-shared-server.R` with unified Step 1/3 logic
- [ ] Extract `server/submit-upload-server.R` from `public-submit-server.R`
- [ ] Extract `server/submit-grid-server.R` from `admin-results-server.R`
- [ ] Extract `server/submit-match-server.R` from `public-submit-server.R`
- [ ] Create `server/submit-decklist-server.R` (new Bandai ID lookup flow)
- [ ] Update `app.R` sidebar navigation (dual links, conditionalPanel)
- [ ] Update `app.R` navset_hidden (remove old panels, add new)
- [ ] Update `app.R` lazy-loading block for admin modules
- [ ] Update all cross-tab navigation references (`"submit"` → `"submit_results"`, `"admin_results"` → `"submit_results"`)
- [ ] Update `ARCHITECTURE.md` tab reference table
- [ ] Unify duplicate tournament detection (shared query, auth-scoped modal)
- [ ] Add required field indicators to shared Step 1
- [ ] Enhance `parse_paste_data()` with member ID formats + header detection
- [ ] Parse Bandai CSV `Deck URLs` column and pre-fill Step 3
- [ ] Grid: Replace fixed-size grid with dynamic rows + "Add Player" button
- [ ] Grid: Make placement column editable (`numericInput` replacing static badge)
- [ ] Grid: Support tied placements (non-sequential values, auto-adjust downstream)
- [ ] Grid: W/L/T override toggle in grid header (admin only, hidden for public)
- [ ] Grid: Re-sort grid by placement on submit/save
- [ ] Remove old files (`views/submit-ui.R`, `views/admin-results-ui.R`, `server/public-submit-server.R`, `server/admin-results-server.R`)
- [ ] Test: public user sees 4 cards, admin sees 6
- [ ] Test: tab appears in public sidebar when logged out, admin sidebar when logged in
- [ ] Test: all 5 entry methods work end-to-end
- [ ] Test: duplicate detection modal behavior differs by auth
- [ ] Test: editable placement with ties produces correct final ordering
- [ ] Test: W/L/T override toggle only visible for admin
- [ ] Test: Add Player button appends row and re-renders correctly
- [ ] Update `CHANGELOG.md` on release
