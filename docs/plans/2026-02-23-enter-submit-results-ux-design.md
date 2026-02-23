# ADM2: Enter Results & Submit Results UX Polish

## Goal

Bring visual and functional parity between the admin Enter Results and public Submit Results tabs, improve feedback and validation, and make deck selection searchable.

## Current State

| Feature | Enter Results (admin) | Submit Results (public) |
|---------|----------------------|------------------------|
| Grid component | Shared `render_grid_ui()` | Custom inline `layout_columns` |
| Deck dropdown | `build_deck_choices()` shared, native select | Inline query, native select |
| Paste from Spreadsheet | Yes | No |
| Player matching | On blur via `match_player()` | OCR-time only |
| Record format | Points or W-L-T toggle | Points only (hardcoded) |
| Filled count badge | Yes | No |
| Member # column | No | Yes |
| Summary bar format | Missing format/set | Missing format/set |
| Event types | `EVENT_TYPES` constant | Hardcoded subset |
| OCR validation | N/A | No minimum quality check |

## Design

### 1. Shared Grid with Mode Parameter

Extend `render_grid_ui()` and related functions in `R/admin_grid.R` to support a `mode` parameter:

- **`"entry"` mode** (admin Enter Results): All fields fully editable, standard input styling. This is the current behavior.
- **`"review"` mode** (public Submit Results): All fields editable but OCR-populated rows get a subtle visual distinction (CSS class `ocr-populated` on the row). Blank rows (unfilled by OCR) appear as normal inputs for manual entry.

Both modes share the same column layout, placement badges, player matching indicators, delete button, and deck dropdown.

**Files:** `R/admin_grid.R`, `server/public-submit-server.R`

### 2. Member Number Column (Both Tabs)

Add a Member # column to the shared grid. It appears in both admin and public grids.

- **Admin (entry mode):** Blank by default. Optional field — admins usually don't have member numbers when entering manually.
- **Public (review mode):** Pre-filled from OCR. Editable for corrections.

The column uses the same prefix pattern: `{prefix}member_{i}`.

**Files:** `R/admin_grid.R` (add column to `render_grid_ui` and `init_grid_data`, `sync_grid_inputs`, `load_grid_from_results`)

### 3. Searchable Deck Dropdown (Both Tabs)

Replace the native `selectInput(..., selectize = FALSE)` for deck selection with `selectizeInput()` in both grids.

- Typing filters the existing archetype list
- "Request new deck..." stays as a special option at the top
- Pending deck requests still shown with "Pending:" prefix
- Keeps the same `build_deck_choices()` helper

This is a change in `render_grid_ui()` so both tabs get it automatically.

**Files:** `R/admin_grid.R` (change `selectInput` to `selectizeInput` in `render_grid_ui`)

### 4. Migrate Submit Results Step 2 to Shared Grid

Replace the custom `submit_results_table` renderUI with calls to the shared grid module.

- Use prefix `"submit_"` (matches current input IDs: `submit_player_`, `submit_points_`, `submit_deck_`)
- Populate grid from OCR results via `load_grid_from_results()` or a new `load_grid_from_ocr()` helper
- Add filled count badge and paste-from-spreadsheet button to the card header (matching admin layout)
- Add blur-based player matching (currently only runs at OCR time)

The OCR-specific elements stay in `public-submit-server.R`:
- Summary banner
- Match summary badges (Matched/Possible/New counts)
- Instructions callout
- Confirmation checkbox

**Files:** `server/public-submit-server.R`, `views/submit-ui.R`

### 5. Paste from Spreadsheet (Public)

Once using the shared grid, add the paste button to the Submit Results card header. Uses the same `parse_paste_data()` helper.

Useful for organizers who have standings in a spreadsheet or when OCR fails.

**Files:** `server/public-submit-server.R`, `views/submit-ui.R`

### 6. Player Matching on Blur (Public)

Add delegated blur handlers for `submit_player_` inputs, same pattern as admin's `blur.adminGrid`. When a user manually types or corrects a name in the public grid, it triggers `match_player()` lookup.

Currently matching only runs once at OCR parse time. This enables matching for manually-entered names in blank rows (rows OCR couldn't fill).

**Files:** `server/public-submit-server.R`

### 7. OCR Output Validation

After OCR processing, validate the parsed results before proceeding to Step 2:

- **0 players found:** Block progression. Show error: "We couldn't find standings data in this screenshot. Make sure you're uploading a Bandai TCG+ standings screen."
- **< 50% of expected players found AND 0 valid member numbers:** Show warning with choice to proceed or re-upload: "Only X of Y players could be read. Are you sure this is the right screenshot?"
- **≥ 50% found or any valid member numbers:** Proceed normally with existing "Parsed X of Y" notification.

**Files:** `server/public-submit-server.R` (modify OCR processing handler)

### 8. Keep Confirmation Checkbox (Public Only)

The "I confirm this data is accurate" checkbox stays on Submit Results as a visual review gate. Not added to admin Enter Results.

### 9. Sync Event Types

Replace the hardcoded event type list in `views/submit-ui.R` with the shared `EVENT_TYPES` constant. Currently missing "release_event" from the public form.

**Files:** `views/submit-ui.R`

### 10. Add Format to Summary Bars

Both the admin and public summary bars currently show store/date/type/players but omit the format. Add it.

**Files:** `server/admin-results-server.R` (tournament_summary_bar), `server/public-submit-server.R` (submit_summary_banner)

### 11. Enter Results Validation Fixes

- Validate event type is selected (not blank "Select event type...") before creating tournament
- Validate format is selected before creating tournament
- Clear all Step 1 form fields after successful submit (store, date, type, format, players, rounds reset)

**Files:** `server/admin-results-server.R`

## Visual Distinction for Review Mode

CSS for the OCR-populated visual treatment:

```css
/* Review mode: OCR-populated rows have subtle background */
.grid-row.ocr-populated input,
.grid-row.ocr-populated select {
  background-color: rgba(var(--bs-info-rgb), 0.05);
  border-color: rgba(var(--bs-info-rgb), 0.2);
}

/* Blank rows in review mode look like standard entry */
.grid-row:not(.ocr-populated) input,
.grid-row:not(.ocr-populated) select {
  /* default input styling */
}
```

## Out of Scope

- Match History tab changes (separate audit if needed)
- OCR parser improvements (handled in v0.28)
- Record format toggle for public submit (stays points-only since OCR extracts points)
- Image classification / pre-OCR validation (output validation is sufficient)

## Task Summary

| # | Description | Scope |
|---|------------|-------|
| 1 | Add member # column to shared grid | `R/admin_grid.R` |
| 2 | Add mode parameter (entry/review) to shared grid | `R/admin_grid.R`, `www/custom.css` |
| 3 | Switch deck dropdown to selectizeInput | `R/admin_grid.R` |
| 4 | Migrate Submit Results Step 2 to shared grid | `server/public-submit-server.R`, `views/submit-ui.R` |
| 5 | Add paste-from-spreadsheet to Submit Results | `server/public-submit-server.R`, `views/submit-ui.R` |
| 6 | Add blur-based player matching to Submit Results | `server/public-submit-server.R` |
| 7 | Add OCR output validation | `server/public-submit-server.R` |
| 8 | Sync event types to constant | `views/submit-ui.R` |
| 9 | Add format to both summary bars | `server/admin-results-server.R`, `server/public-submit-server.R` |
| 10 | Enter Results validation + form reset | `server/admin-results-server.R` |
