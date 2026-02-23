# UX Polish Round 2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add inline form validation, debounced search inputs, and value box count-up animations.

**Architecture:** CSS-only field highlighting via shinyjs (no new packages). R-level reactive debouncing (300ms). JavaScript count-up handler integrated into existing `shiny:value` event listener.

**Tech Stack:** R Shiny, shinyjs, CSS, vanilla JavaScript

---

## Task 1: Inline Form Validation — CSS + Helpers

Add a CSS class for invalid fields and R helper functions to show/clear field errors.

**Files:**
- Modify: `www/custom.css` (add FORM VALIDATION section after existing SKELETON LOADERS section)
- Modify: `app.R` (add helper functions near existing `notify()` helper, ~line 205)

**Step 1: Add CSS for invalid field highlighting**

In `www/custom.css`, add a new section after the SKELETON LOADERS section:

```css
/* =========================================================================
   FORM VALIDATION
   ========================================================================= */

/* Invalid field highlighting - applied to .shiny-input-container */
.input-invalid .form-control,
.input-invalid .shiny-input-select,
.input-invalid .selectized .selectize-input {
  border-color: #dc3545 !important;
  box-shadow: 0 0 0 0.2rem rgba(220, 53, 69, 0.15) !important;
}

/* Also target native select elements */
.input-invalid select {
  border-color: #dc3545 !important;
  box-shadow: 0 0 0 0.2rem rgba(220, 53, 69, 0.15) !important;
}

/* Dark mode adjustment */
[data-bs-theme="dark"] .input-invalid .form-control,
[data-bs-theme="dark"] .input-invalid .shiny-input-select,
[data-bs-theme="dark"] .input-invalid select,
[data-bs-theme="dark"] .input-invalid .selectized .selectize-input {
  box-shadow: 0 0 0 0.2rem rgba(220, 53, 69, 0.25) !important;
}

/* Smooth transition for validation state */
.form-control,
select,
.selectize-input {
  transition: border-color 0.2s ease, box-shadow 0.2s ease;
}
```

**Step 2: Add R helper functions in app.R**

After the `notify()` function (after line 205), add:

```r
# =============================================================================
# Helper: Inline Form Validation
# =============================================================================

# Highlight a field as invalid (red border)
show_field_error <- function(session, inputId) {
  shinyjs::runjs(sprintf(
    "var el = document.getElementById('%s');
     if (el) el.closest('.shiny-input-container').classList.add('input-invalid');",
    inputId
  ))
}

# Clear invalid highlighting from a field
clear_field_error <- function(session, inputId) {
  shinyjs::runjs(sprintf(
    "var el = document.getElementById('%s');
     if (el) el.closest('.shiny-input-container').classList.remove('input-invalid');",
    inputId
  ))
}

# Clear all invalid fields in a container
clear_all_field_errors <- function(session) {
  shinyjs::runjs(
    "document.querySelectorAll('.input-invalid').forEach(function(el) {
       el.classList.remove('input-invalid');
     });"
  )
}
```

**Step 3: Add auto-clear JS handler in app.R**

In the existing `tags$script(HTML(...))` block (around line 540), add before the closing of the script:

```javascript
// Auto-clear validation styling when user interacts with invalid fields
$(document).on('change input focus', '.input-invalid .form-control, .input-invalid select, .input-invalid .selectize-input input', function() {
  $(this).closest('.input-invalid').removeClass('input-invalid');
});
```

**Step 4: Commit**

```bash
git add www/custom.css app.R
git commit -m "feat: add inline form validation CSS and helper functions"
```

---

## Task 2: Apply Validation to Tournament Create Form

Add field highlighting to the tournament creation wizard (Step 1).

**Files:**
- Modify: `server/admin-results-server.R` (lines 73-150, `create_tournament` handler)

**Step 1: Add `clear_all_field_errors` at the top of the handler**

At the beginning of the `observeEvent(input$create_tournament, {...})` handler (after line 73), add:

```r
clear_all_field_errors(session)
```

**Step 2: Add `show_field_error` before each existing `notify()` + `return()`**

For each validation block, add the field highlight call before the notify:

- **Store validation** (~line 84-93): Add `show_field_error(session, "tournament_store")` before the `notify("Please select a store", ...)`
- **Date validation** (~line 96-99): Add `show_field_error(session, "tournament_date")` before the `notify("Please select a tournament date", ...)`
- **Player count** (~line 101-104): Add `show_field_error(session, "tournament_players")` before the `notify("Player count must be at least 2", ...)`
- **Rounds** (~line 106-109): Add `show_field_error(session, "tournament_rounds")` before the `notify("Rounds must be at least 1", ...)`

Pattern for each block:
```r
if (validation_fails) {
  show_field_error(session, "input_id")
  notify("Error message", type = "error")
  return()
}
```

**Step 3: Commit**

```bash
git add server/admin-results-server.R
git commit -m "feat: add inline validation to tournament create form"
```

---

## Task 3: Apply Validation to Store Forms

Add field highlighting to store add and edit forms.

**Files:**
- Modify: `server/admin-stores-server.R` (lines 56-227 add handler, lines 422-547 update handler)

**Step 1: Add Store (lines 56-227)**

At the top of `observeEvent(input$add_store, {...})`, add `clear_all_field_errors(session)`.

Then add `show_field_error()` calls before each existing `notify()`:

- **Store name** (~line 85-88): `show_field_error(session, "store_name")`
- **City** (~line 91-94): `show_field_error(session, "store_city")`
- **ZIP code** (~line 97-100): `show_field_error(session, "store_zip")`
- **Website URL** (~line 132-134): `show_field_error(session, "store_website")`

**Step 2: Update Store (lines 422-547)**

Same pattern for the update handler. Add `clear_all_field_errors(session)` at top, then `show_field_error()` for each validation in the edit modal's fields.

Note: Edit modal fields may have different input IDs (e.g., `edit_store_name`). Check the actual input IDs used in the edit modal's `showModal()` call and use those.

**Step 3: Commit**

```bash
git add server/admin-stores-server.R
git commit -m "feat: add inline validation to store forms"
```

---

## Task 4: Apply Validation to Remaining Admin Forms

Add field highlighting to decks, players, formats, and tournament edit forms.

**Files:**
- Modify: `server/admin-decks-server.R` (add archetype handler ~line 169, update handler ~line 353)
- Modify: `server/admin-players-server.R` (update player handler ~line 175, merge handler ~line 390)
- Modify: `server/admin-formats-server.R` (add format ~line 81, update format ~line 125)
- Modify: `server/admin-tournaments-server.R` (update tournament ~line 232)

**Step 1: Decks**

`observeEvent(input$add_archetype, {...})` (~line 169):
- Add `clear_all_field_errors(session)` at top
- **Name empty** (~line 178): `show_field_error(session, "new_archetype_name")`
- **Name too short** (~line 183): `show_field_error(session, "new_archetype_name")`
- **Card ID format** (~line 203): `show_field_error(session, "selected_card_id")`

`observeEvent(input$update_archetype, {...})` (~line 353):
- Add `clear_all_field_errors(session)` at top
- **Name empty** (~line 363): `show_field_error(session, "edit_archetype_name")` (check actual ID)

**Step 2: Players**

`observeEvent(input$update_player, {...})` (~line 175):
- Add `clear_all_field_errors(session)` at top
- **Name empty** (~line 181): `show_field_error(session, "edit_player_name")` (check actual ID)
- **Name too short** (~line 186): `show_field_error(session, "edit_player_name")`

`observeEvent(input$confirm_merge_players, {...})` (~line 390):
- **Invalid IDs** (~line 396): `show_field_error(session, "merge_source_player")` and `show_field_error(session, "merge_target_player")`

**Step 3: Formats**

`observeEvent(input$add_format, {...})` (~line 81):
- Add `clear_all_field_errors(session)` at top
- **Required fields** (~line 89): `show_field_error(session, "new_format_id")` and `show_field_error(session, "new_set_name")`

`observeEvent(input$update_format, {...})` (~line 125):
- Same pattern for edit modal fields

**Step 4: Tournaments**

`observeEvent(input$update_tournament, {...})` (~line 232):
- Add `clear_all_field_errors(session)` at top
- **Store** (~line 244): `show_field_error(session, "edit_tournament_store")` (check actual ID)
- **Event type** (~line 249): `show_field_error(session, "edit_tournament_type")` (check actual ID)

**Step 5: Commit**

```bash
git add server/admin-decks-server.R server/admin-players-server.R server/admin-formats-server.R server/admin-tournaments-server.R
git commit -m "feat: add inline validation to deck, player, format, and tournament forms"
```

---

## Task 5: Debounce Search Inputs

Add 300ms debounce to all reactive search inputs to reduce unnecessary DB queries.

**Files:**
- Modify: `server/public-players-server.R` (add debounced reactive, update references at lines 95, 155)
- Modify: `server/public-meta-server.R` (add debounced reactive, update references at lines 20, 57)
- Modify: `server/public-tournaments-server.R` (add debounced reactive, update references at lines 21, 58)
- Modify: `server/admin-tournaments-server.R` (add debounced reactive, update reference at line 65)
- Modify: `server/admin-players-server.R` (add debounced reactive, update reference at line 15)

**Step 1: Public Players**

At the top of `server/public-players-server.R` (after the `historical_snapshot_data` reactive, ~line 27), add:

```r
# Debounce search input (300ms)
players_search_debounced <- reactive(input$players_search) |> debounce(300)
```

Then replace references:
- Line 95: `search = input$players_search` → `search = players_search_debounced()`
- Line 155: `nchar(trimws(input$players_search %||% "")) > 0` → `nchar(trimws(players_search_debounced() %||% "")) > 0`

Note: Keep the `updateTextInput` reset call at line 71 using `input$players_search` — that's a write, not a read.

**Step 2: Public Meta**

At the top of `server/public-meta-server.R` (after the reset handler, ~line 11), add:

```r
# Debounce search input (300ms)
meta_search_debounced <- reactive(input$meta_search) |> debounce(300)
```

Then replace references:
- Line 20: `search = input$meta_search` → `search = meta_search_debounced()`
- Line 57: `nchar(trimws(input$meta_search %||% "")) > 0` → `nchar(trimws(meta_search_debounced() %||% "")) > 0`

**Step 3: Public Tournaments**

At the top of `server/public-tournaments-server.R` (after the reset handler, ~line 13), add:

```r
# Debounce search input (300ms)
tournaments_search_debounced <- reactive(input$tournaments_search) |> debounce(300)
```

Then replace references:
- Line 21: `search = input$tournaments_search` → `search = tournaments_search_debounced()`
- Line 58: `nchar(trimws(input$tournaments_search %||% "")) > 0` → `nchar(trimws(tournaments_search_debounced() %||% "")) > 0`

**Step 4: Admin Tournaments**

At the top of the admin tournament list rendering section in `server/admin-tournaments-server.R` (before `output$admin_tournament_list`, ~line 55), add:

```r
# Debounce admin search input (300ms)
admin_tournament_search_debounced <- reactive(input$admin_tournament_search) |> debounce(300)
```

Then replace:
- Line 65: `search <- input$admin_tournament_search %||% ""` → `search <- admin_tournament_search_debounced() %||% ""`

**Step 5: Admin Players**

At the top of the admin player list rendering section in `server/admin-players-server.R` (before `output$admin_player_list`, ~line 5), add:

```r
# Debounce admin search input (300ms)
player_search_debounced <- reactive(input$player_search) |> debounce(300)
```

Then replace:
- Line 15: `search_term <- input$player_search %||% ""` → `search_term <- player_search_debounced() %||% ""`

**Step 6: Commit**

```bash
git add server/public-players-server.R server/public-meta-server.R server/public-tournaments-server.R server/admin-tournaments-server.R server/admin-players-server.R
git commit -m "feat: add 300ms debounce to all search inputs"
```

---

## Task 6: Value Box Count-Up Animation

Add a count-up animation for numeric value boxes (Tournaments, Players) and a fade-in for deck value boxes (Hot Deck, Top Deck).

**Files:**
- Modify: `app.R` (add JS count-up handler in existing script block, ~line 561)
- Modify: `www/custom.css` (add animation CSS in value box section)

**Step 1: Add CSS for value box transitions**

In `www/custom.css`, add to the existing value box section (after `.vb-tracking` styles, ~line 1345):

```css
/* Value box update animation */
.vb-value-updating {
  animation: vb-fade-in 0.4s ease-out;
}

@keyframes vb-fade-in {
  0% { opacity: 0.3; transform: translateY(4px); }
  100% { opacity: 1; transform: translateY(0); }
}
```

**Step 2: Add count-up + fade JS in app.R**

In the existing `$(document).on('shiny:value', function(e) {...})` handler (line 561 in app.R), add a block for value box animations. The handler already fires for every Shiny output update. Add before the skeleton loader logic:

```javascript
// Count-up animation for numeric value boxes
var numericBoxes = ['total_tournaments_val', 'total_players_val'];
if (numericBoxes.indexOf(e.name) !== -1) {
  setTimeout(function() {
    var el = document.getElementById(e.name);
    if (!el) return;
    var newVal = parseInt(el.textContent, 10);
    if (isNaN(newVal)) return;
    var oldVal = parseInt(el.getAttribute('data-prev') || '0', 10);
    el.setAttribute('data-prev', newVal);
    if (oldVal === newVal || oldVal === 0) {
      el.classList.add('vb-value-updating');
      setTimeout(function() { el.classList.remove('vb-value-updating'); }, 400);
      return;
    }
    var duration = 600;
    var start = performance.now();
    function step(now) {
      var progress = Math.min((now - start) / duration, 1);
      var eased = 1 - Math.pow(1 - progress, 3);
      el.textContent = Math.round(oldVal + (newVal - oldVal) * eased);
      if (progress < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  }, 50);
}

// Fade-in animation for deck value boxes
var deckBoxes = ['hot_deck_name', 'most_popular_deck_val', 'hot_deck_trend', 'top_deck_meta_share'];
if (deckBoxes.indexOf(e.name) !== -1) {
  setTimeout(function() {
    var el = document.getElementById(e.name);
    if (!el) return;
    el.classList.add('vb-value-updating');
    setTimeout(function() { el.classList.remove('vb-value-updating'); }, 400);
  }, 50);
}
```

**Step 3: Commit**

```bash
git add app.R www/custom.css
git commit -m "feat: add count-up animation for numeric value boxes and fade-in for deck boxes"
```

---

## Task 7: Verification

**Files:** None (verification only)

**Step 1: Run R syntax check**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "tryCatch(source('app.R'), error = function(e) cat('ERROR:', e[['message']], '\n'))"
```

Expected: No errors (renv warning is OK).

**Step 2: Verify no regressions**

Manual checks:
1. Admin forms: Submit with empty fields → fields highlight red + toast notification
2. Admin forms: Fill in a highlighted field → red border clears on interaction
3. Search inputs: Type in Players search → 300ms delay before table updates
4. Dashboard: Load app → value box numbers count up from 0
5. Dashboard: Switch filters → numbers animate to new values

**Step 3: Commit any fixes if needed**

If verification reveals issues, fix and commit.
