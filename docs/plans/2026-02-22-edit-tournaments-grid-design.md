# Edit Tournaments Grid Entry — Design Doc

**Date:** 2026-02-22
**ID:** ADM1
**Status:** Approved

## Goal

Replace the one-at-a-time modal-based results editor in Edit Tournaments with the same grid-based entry flow used by Enter Results. Full feature parity: editable grid, paste from spreadsheet, player matching badges, deck requests, and inline player creation.

## Primary Use Case

Fixing a few results after initial entry — correcting player names, placements, records, or deck assignments. Also supports full re-entry and adding new results to an existing tournament.

## Architecture: Shared Grid Module

Create `R/admin_grid.R` with shared functions used by both Enter Results and Edit Tournaments:

| Function | Purpose |
|----------|---------|
| `render_admin_grid(grid_data, record_format, is_release, deck_choices, player_matches, prefix)` | Generates grid UI (layout_columns rows with inputs). `prefix` parameter avoids input ID collisions between pages. |
| `sync_grid_inputs(input, grid_data, record_format, prefix)` | Reads current form input values into the grid data frame. Returns updated data frame. |
| `init_grid_data(n)` | Creates blank n-row grid data frame. |
| `load_grid_from_results(tournament_id, con)` | Queries existing results, returns pre-filled grid data frame with player names, records, deck IDs, and `result_id` for tracking existing vs new rows. |
| `parse_paste_data(text, record_format, deck_archetypes)` | Parses clipboard text into grid rows. Returns data frame. |

Input IDs use a configurable prefix (`admin_` for Enter Results, `edit_` for Edit Tournaments) so both grids can coexist without collisions.

## UX Flow

### Triggering the Grid

1. Admin selects a tournament in the Edit Tournaments list
2. Clicks "View/Edit Results" button
3. Grid section appears **below** the existing two-column layout (form + list) as a full-width section
4. Grid pre-fills with existing results: player names, placements, records, deck selections
5. Player matching runs on load — existing players show green "Matched" badges

### Grid Section Layout

- Tournament summary bar at top (store, date, format, players)
- Same controls as Enter Results: Paste from Spreadsheet button, filled count indicator, record format badge
- Edit-specific controls: "Cancel" button (closes grid without saving), "Save Changes" button (instead of "Submit Results")
- Grid wrapped in `shinyjs::hidden()`, toggled on View/Edit Results click

### Record Format Inference

Inferred from existing data on load:
- If any result has `ties > 0` or wins/losses don't cleanly convert to points → W-L-T mode
- Otherwise → points mode
- Admin can toggle if needed

## Submit Logic (Edit Mode)

The key difference from Enter Results — edit mode must handle updates, inserts, and deletes:

| Row State | Action |
|-----------|--------|
| Existing row (has `result_id`) with changes | UPDATE the database row |
| New row (no `result_id`) with player name filled | INSERT new result + create player if needed |
| Original row now empty/deleted | DELETE from database |

**Delete handling:** The grid's per-row delete button (X) marks rows for deletion. Rows with an existing `result_id` are tracked in a "to delete" list so the save handler knows what to remove.

**Post-save:**
- Recalculate ratings cache
- Refresh admin and public tables
- Collapse the grid view
- Show success notification

## UI Layout

No navigation changes — everything stays within the Edit Tournaments tab:

```
+------------------------------------------+
| Edit Tournaments (existing two-column)   |
| [Form (left)]    [Tournament List (right)]|
+------------------------------------------+
| Grid Section (full-width, shown/hidden)  |
| [Summary Bar]                            |
| [Paste btn] [Filled count] [Format badge]|
| [Grid rows with inputs...]              |
| [Cancel]              [Save Changes]     |
+------------------------------------------+
```

## Refactoring Scope

### Enter Results (`admin-results-server.R`)
- Extract grid rendering into `render_admin_grid()` in `R/admin_grid.R`
- Extract input sync into `sync_grid_inputs()`
- Extract paste parsing into `parse_paste_data()`
- Replace inline code with calls to shared functions
- Update input ID references to use `admin_` prefix explicitly

### Edit Tournaments (`admin-tournaments-server.R`)
- Remove modal-based results editor (View/Edit Results modal, Edit Result modal, Add Result form)
- Add grid section toggle (show/hide on View/Edit Results click)
- Add grid load logic using `load_grid_from_results()`
- Add edit-mode submit handler (update/insert/delete diff)
- Add player matching on grid load
- Reuse paste from spreadsheet with `edit_` prefix

### Edit Tournaments UI (`admin-tournaments-ui.R`)
- Add hidden grid section below existing layout
- Tournament summary bar, grid container, bottom navigation (Cancel + Save Changes)
- Paste from Spreadsheet button in grid header

## What's NOT Changing

- Enter Results wizard flow (Step 1 → Step 2) — unchanged
- Tournament metadata editing in Edit Tournaments (store, date, format, etc.) — unchanged
- Tournament deletion flow — unchanged
- Deck request modal — shared as-is
