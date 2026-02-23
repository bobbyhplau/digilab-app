# UX Polish Items 1-5 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve the five highest-impact UX areas: loading indicators, standardized empty states, extended digital aesthetic on content cards, persistent error notifications, and consolidated modal systems.

**Architecture:** CSS-first approach for visual changes (loading skeletons, card styling, modal body treatment). Server-side R changes for notification behavior and empty state standardization. No new packages — uses existing Shiny, bslib, shinyjs, and CSS capabilities.

**Tech Stack:** R Shiny, bslib, shinyjs, CSS (www/custom.css), JavaScript (inline in app.R)

---

## Item 1: Loading Indicators for Data Operations

**Problem:** When filters change, charts re-render, or modals load complex data, there is zero visual feedback. Users cannot distinguish "loading" from "broken."

**Approach:** Add CSS skeleton loaders that display inside card bodies while reactable/highcharter outputs are recalculating. Use Shiny's `recalculating` CSS class (automatically added by Shiny when outputs are re-rendering) to show/hide skeleton states. Also add a subtle fade effect to outputs while recalculating.

---

### Task 1.1: Add CSS skeleton loader styles

**Files:**
- Modify: `www/custom.css` (append after line ~4548, after DIGITAL EMPTY STATES section)

**Step 1: Add skeleton loader CSS**

Add a new section after the Digital Empty States section (after line 4548):

```css
/* =============================================================================
   SKELETON LOADERS - Digital Loading States
   ============================================================================= */

/* Fade recalculating outputs */
.recalculating {
  opacity: 0.4 !important;
  transition: opacity 0.3s ease !important;
  pointer-events: none;
}

/* Skeleton shimmer animation */
@keyframes skeleton-shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}

/* Base skeleton element */
.skeleton-line {
  height: 14px;
  border-radius: 4px;
  background: linear-gradient(90deg,
    rgba(15, 76, 129, 0.06) 25%,
    rgba(15, 76, 129, 0.12) 50%,
    rgba(15, 76, 129, 0.06) 75%);
  background-size: 200% 100%;
  animation: skeleton-shimmer 1.8s ease-in-out infinite;
  margin-bottom: 0.5rem;
}

/* Width variants */
.skeleton-line.w-75 { width: 75%; }
.skeleton-line.w-50 { width: 50%; }
.skeleton-line.w-60 { width: 60%; }
.skeleton-line.w-90 { width: 90%; }
.skeleton-line.w-40 { width: 40%; }

/* Table skeleton row */
.skeleton-table-row {
  display: flex;
  gap: 1rem;
  padding: 0.6rem 0;
  border-bottom: 1px solid rgba(0, 0, 0, 0.04);
}

.skeleton-table-row .skeleton-line {
  margin-bottom: 0;
  flex: 1;
}

.skeleton-table-row .skeleton-line:first-child {
  flex: 0.5;
}

/* Chart skeleton */
.skeleton-chart {
  display: flex;
  align-items: flex-end;
  gap: 0.5rem;
  padding: 1rem 0;
  height: 180px;
}

.skeleton-bar {
  flex: 1;
  border-radius: 4px 4px 0 0;
  background: linear-gradient(90deg,
    rgba(15, 76, 129, 0.06) 25%,
    rgba(15, 76, 129, 0.12) 50%,
    rgba(15, 76, 129, 0.06) 75%);
  background-size: 200% 100%;
  animation: skeleton-shimmer 1.8s ease-in-out infinite;
}

/* Digital grid overlay on skeleton container */
.skeleton-container {
  position: relative;
  padding: 1rem;
  background-image:
    repeating-linear-gradient(0deg, rgba(15, 76, 129, 0.02) 0px, transparent 1px, transparent 25px),
    repeating-linear-gradient(90deg, rgba(15, 76, 129, 0.02) 0px, transparent 1px, transparent 25px);
  border-radius: 8px;
  min-height: 100px;
}

/* Dark mode skeletons */
[data-bs-theme="dark"] .skeleton-line,
[data-bs-theme="dark"] .skeleton-bar {
  background: linear-gradient(90deg,
    rgba(0, 200, 255, 0.05) 25%,
    rgba(0, 200, 255, 0.1) 50%,
    rgba(0, 200, 255, 0.05) 75%);
  background-size: 200% 100%;
  animation: skeleton-shimmer 1.8s ease-in-out infinite;
}

[data-bs-theme="dark"] .skeleton-table-row {
  border-bottom-color: rgba(255, 255, 255, 0.06);
}

[data-bs-theme="dark"] .skeleton-container {
  background-image:
    repeating-linear-gradient(0deg, rgba(0, 200, 255, 0.02) 0px, transparent 1px, transparent 25px),
    repeating-linear-gradient(90deg, rgba(0, 200, 255, 0.02) 0px, transparent 1px, transparent 25px);
}
```

**Step 2: Commit**

```bash
git add www/custom.css
git commit -m "style: add CSS skeleton loader and recalculating fade styles"
```

---

### Task 1.2: Add skeleton loader R helper function

**Files:**
- Modify: `app.R` (add after `digital_empty_state()` function, after line ~233)

**Step 1: Add the skeleton helper functions**

Add after the `digital_empty_state()` function closing brace (line 233):

```r
# Skeleton loader for table cards
skeleton_table <- function(rows = 6) {
  div(
    class = "skeleton-container",
    lapply(seq_len(rows), function(i) {
      widths <- c("w-40", "w-75", "w-60", "w-50", "w-90")
      div(
        class = "skeleton-table-row",
        div(class = paste("skeleton-line", widths[((i - 1) %% 5) + 1])),
        div(class = paste("skeleton-line", widths[((i + 1) %% 5) + 1])),
        div(class = paste("skeleton-line", widths[((i + 2) %% 5) + 1]))
      )
    })
  )
}

# Skeleton loader for chart cards
skeleton_chart <- function(bars = 8, height = "180px") {
  div(
    class = "skeleton-container",
    div(
      class = "skeleton-chart",
      style = paste0("height:", height),
      lapply(seq_len(bars), function(i) {
        bar_height <- paste0(sample(30:95, 1), "%")
        div(class = "skeleton-bar", style = paste0("height:", bar_height))
      })
    )
  )
}
```

**Step 2: Commit**

```bash
git add app.R
git commit -m "feat: add skeleton_table and skeleton_chart helper functions"
```

---

### Task 1.3: Add skeleton loaders to public data tables

**Files:**
- Modify: `views/players-ui.R` (line 68-70)
- Modify: `views/meta-ui.R` (line 61-63)
- Modify: `views/tournaments-ui.R` (line 64-66)

**Step 1: Wrap each reactableOutput with a conditional skeleton**

In each file, replace the bare `reactableOutput()` inside `card_body()` with a wrapper that shows a skeleton by default and the table once loaded.

For **`views/players-ui.R`** lines 68-70, replace:
```r
    card_body(
      reactableOutput("player_standings")
    )
```
with:
```r
    card_body(
      div(
        id = "player_standings_skeleton",
        skeleton_table(rows = 8)
      ),
      reactableOutput("player_standings")
    )
```

For **`views/meta-ui.R`** lines 61-63, replace:
```r
    card_body(
      reactableOutput("archetype_stats")
    )
```
with:
```r
    card_body(
      div(
        id = "archetype_stats_skeleton",
        skeleton_table(rows = 8)
      ),
      reactableOutput("archetype_stats")
    )
```

For **`views/tournaments-ui.R`** lines 64-66, replace:
```r
    card_body(
      reactableOutput("tournament_history")
    )
```
with:
```r
    card_body(
      div(
        id = "tournament_history_skeleton",
        skeleton_table(rows = 8)
      ),
      reactableOutput("tournament_history")
    )
```

**Step 2: Add JavaScript to hide skeletons once outputs render**

In `app.R`, in the JavaScript section (inside `tags$script(HTML(...))` block), add:

```javascript
// Hide skeleton loaders once Shiny outputs render
$(document).on('shiny:value', function(event) {
  var skeletonId = event.name + '_skeleton';
  var skeleton = document.getElementById(skeletonId);
  if (skeleton) {
    skeleton.style.display = 'none';
  }
});
```

**Step 3: Commit**

```bash
git add views/players-ui.R views/meta-ui.R views/tournaments-ui.R app.R
git commit -m "feat: add skeleton loaders to players, meta, and tournaments tables"
```

---

### Task 1.4: Add skeleton loaders to dashboard charts

**Files:**
- Modify: `views/dashboard-ui.R` (6 highchartOutput locations)

**Step 1: Add skeleton wrappers to each chart output**

For each `highchartOutput()` in `dashboard-ui.R`, add a skeleton sibling. The 6 charts are:

1. `meta_diversity_gauge` (line ~189) — wrap with `skeleton_chart(bars = 1, height = "180px")`
2. `conversion_rate_chart` (line ~229) — wrap with `skeleton_chart(bars = 5, height = "240px")`
3. `color_dist_chart` (line ~240) — wrap with `skeleton_chart(bars = 7, height = "240px")`
4. `meta_share_timeline` (line ~257) — wrap with `skeleton_chart(bars = 10, height = "310px")`
5. `tournaments_trend_chart` (line ~273) — wrap with `skeleton_chart(bars = 8, height = "240px")`
6. `player_growth_chart` (line ~289) — wrap with `skeleton_chart(bars = 6, height = "160px")`

For each, the pattern is to add a skeleton div before the highchartOutput:

```r
div(id = "meta_diversity_gauge_skeleton", skeleton_chart(bars = 1, height = "180px")),
highchartOutput("meta_diversity_gauge", height = "220px")
```

The JavaScript handler from Task 1.3 will automatically hide these when the chart renders.

**Step 2: Add skeleton for recent_tournaments table on dashboard**

For `recent_tournaments` (line ~210):
```r
div(id = "recent_tournaments_skeleton", skeleton_table(rows = 5)),
reactableOutput("recent_tournaments")
```

**Step 3: Commit**

```bash
git add views/dashboard-ui.R
git commit -m "feat: add skeleton loaders to dashboard charts and tables"
```

---

## Item 2: Standardize Empty States

**Problem:** Empty data is handled inconsistently — public pages use `digital_empty_state()` with Agumon mascot, admin pages show plain "No data" text in a one-row reactable, and some pages show blank tables.

**Approach:** Create context-aware empty states. Public pages should always use `digital_empty_state()`. Admin pages get a lighter variant. Replace bare reactable empty rows with the standard empty state helper.

---

### Task 2.1: Add lightweight admin empty state helper

**Files:**
- Modify: `app.R` (add after `skeleton_chart()` helper)

**Step 1: Add admin_empty_state helper**

```r
# Lightweight empty state for admin tables
admin_empty_state <- function(title = "No records found",
                               subtitle = NULL,
                               icon = "inbox") {
  div(
    class = "empty-state-digital",
    style = "padding: 1.5rem 1rem; min-height: 80px;",
    div(class = "empty-state-icon", style = "font-size: 1.8rem;",
        bsicons::bs_icon(icon)),
    div(class = "empty-state-title", title),
    if (!is.null(subtitle)) div(class = "empty-state-subtitle", subtitle)
  )
}
```

**Step 2: Commit**

```bash
git add app.R
git commit -m "feat: add admin_empty_state helper for consistent admin empty states"
```

---

### Task 2.2: Replace admin reactable empty rows with empty states

**Files:**
- Modify: `server/admin-formats-server.R` (line ~24)
- Modify: `server/admin-players-server.R` (line ~67)

**Step 1: Update admin-formats-server.R**

Find the early return that creates a one-row reactable with "No formats added yet" and replace it with:

```r
if (nrow(formats) == 0) {
  return(admin_empty_state("No formats added yet", "// add one using the form", "calendar3"))
}
```

**Step 2: Update admin-players-server.R**

Find the early return that creates a one-row reactable with "No players found" and replace it with:

```r
if (nrow(players_data) == 0) {
  return(admin_empty_state("No players found", "// add players via tournament entry", "people"))
}
```

**Step 3: Commit**

```bash
git add server/admin-formats-server.R server/admin-players-server.R
git commit -m "feat: replace plain text empty states with digital_empty_state in admin pages"
```

---

### Task 2.3: Add contextual messaging to public empty states

**Files:**
- Modify: `server/public-players-server.R`
- Modify: `server/public-meta-server.R`
- Modify: `server/public-tournaments-server.R`

**Step 1: Make empty states filter-aware**

In each public server file, where `digital_empty_state()` is returned for empty table data, check if filters are active and show a filter-specific message. The pattern:

```r
# Example pattern for players (adapt for each page)
if (nrow(filtered_data) == 0) {
  has_filters <- nchar(trimws(input$players_search %||% "")) > 0 ||
                 nchar(trimws(input$players_format %||% "")) > 0
  if (has_filters) {
    return(digital_empty_state(
      title = "No players match your filters",
      subtitle = "// try adjusting search or format",
      icon = "funnel",
      mascot = NULL
    ))
  } else {
    return(digital_empty_state(
      title = "No players recorded",
      subtitle = "// player data pending",
      icon = "people",
      mascot = "agumon"
    ))
  }
}
```

Apply this pattern to:
- **public-players-server.R**: Check `players_search`, `players_format`
- **public-meta-server.R**: Check `meta_search`, `meta_format`
- **public-tournaments-server.R**: Check `tournaments_search`, `tournaments_format`, `tournaments_event_type`

The key change is adding the filter-aware branch. Keep existing `digital_empty_state()` calls as the no-filter fallback.

**Step 2: Commit**

```bash
git add server/public-players-server.R server/public-meta-server.R server/public-tournaments-server.R
git commit -m "feat: add filter-aware empty state messages on public pages"
```

---

## Item 3: Extend Digital Aesthetic to Content Cards

**Problem:** Chart cards (Tier 1) get the grid pattern + circuit node treatment via `.card-feature` / `:has(.highchartOutput)` selectors. But data table cards (Players, Meta, Tournaments, Stores, Dashboard Recent/Rising Stars) have plain headers — creating a visual disconnect between themed chrome and plain content.

**Approach:** Add a new Tier 2 card treatment: apply a subtler version of the grid pattern to ALL `.card-header` elements. This makes every card feel "digital" without being as prominent as feature cards. Also add a subtle grid overlay to modal bodies.

---

### Task 3.1: Add grid pattern to all card headers (Tier 2 base)

**Files:**
- Modify: `www/custom.css` (lines 1627-1634 — base `.card-header`)

**Step 1: Update base card-header to include subtle grid**

Replace the existing `.card-header` rule (lines 1627-1634):

```css
.card-header {
  background: linear-gradient(135deg, #f8f9fa 0%, #ffffff 100%) !important;
  border-bottom: 1px solid rgba(0, 0, 0, 0.06) !important;
  font-weight: 600 !important;
  font-size: 0.95rem !important;
  padding: 0.75rem 1rem !important;
  border-radius: 10px 10px 0 0 !important;
}
```

With:

```css
.card-header {
  position: relative;
  background-image:
    repeating-linear-gradient(0deg, rgba(15, 76, 129, 0.025) 0px, transparent 1px, transparent 20px),
    repeating-linear-gradient(90deg, rgba(15, 76, 129, 0.025) 0px, transparent 1px, transparent 20px),
    linear-gradient(135deg, #f8f9fa 0%, #ffffff 100%) !important;
  border-bottom: 1px solid rgba(0, 0, 0, 0.06) !important;
  font-weight: 600 !important;
  font-size: 0.95rem !important;
  padding: 0.75rem 1rem !important;
  border-radius: 10px 10px 0 0 !important;
}
```

The difference from Tier 1 (feature) cards: opacity is 0.025 (vs 0.04) — noticeably subtler but still present.

**Step 2: Update dark mode card-header (line ~1684)**

Replace the existing dark mode `.card-header` rule:

```css
[data-bs-theme="dark"] .card-header {
  background: linear-gradient(135deg, #2a2a2a 0%, #1e1e1e 100%) !important;
  border-bottom: 1px solid rgba(255, 255, 255, 0.1) !important;
}
```

With:

```css
[data-bs-theme="dark"] .card-header {
  background-image:
    repeating-linear-gradient(0deg, rgba(0, 200, 255, 0.02) 0px, transparent 1px, transparent 20px),
    repeating-linear-gradient(90deg, rgba(0, 200, 255, 0.02) 0px, transparent 1px, transparent 20px),
    linear-gradient(135deg, #2a2a2a 0%, #1e1e1e 100%) !important;
  border-bottom: 1px solid rgba(255, 255, 255, 0.1) !important;
}
```

**Step 3: Commit**

```bash
git add www/custom.css
git commit -m "style: add subtle grid pattern to all card headers (Tier 2 digital aesthetic)"
```

---

### Task 3.2: Add circuit node to all card headers

**Files:**
- Modify: `www/custom.css`

**Step 1: Move circuit node from feature-only to all card headers**

The existing circuit node is on `.card-feature .card-header::after` and `.card:has(.highchartOutput) .card-header::after` (lines 1651-1664).

Add a new rule for ALL card headers using a subtler circuit node. Insert **before** the feature card rules (before line 1640):

```css
/* Tier 2: Subtle circuit node on all card headers */
.card-header::after {
  content: '';
  position: absolute;
  top: 50%;
  right: 12px;
  transform: translateY(-50%);
  width: 4px;
  height: 4px;
  background: rgba(0, 200, 255, 0.25);
  border-radius: 50%;
  box-shadow: 0 0 4px rgba(0, 200, 255, 0.3);
}
```

Then update the feature card `::after` rules (lines 1651-1664) to use stronger values (they already do — 5px, 0.4 opacity, 6px glow — so these override the base automatically via higher specificity).

**Step 2: Commit**

```bash
git add www/custom.css
git commit -m "style: add subtle circuit node accent to all card headers"
```

---

### Task 3.3: Add digital grid treatment to modal bodies

**Files:**
- Modify: `www/custom.css` (after line ~2035, after `.modal-body` text selection rule)

**Step 1: Add subtle grid to modal body backgrounds**

Insert after the `.modal-body` user-select rules (after line 2035):

```css
/* Subtle digital grid on modal body */
.modal-body {
  background-image:
    repeating-linear-gradient(0deg, rgba(15, 76, 129, 0.015) 0px, transparent 1px, transparent 24px),
    repeating-linear-gradient(90deg, rgba(15, 76, 129, 0.015) 0px, transparent 1px, transparent 24px);
}

[data-bs-theme="dark"] .modal-body {
  background-image:
    repeating-linear-gradient(0deg, rgba(0, 200, 255, 0.015) 0px, transparent 1px, transparent 24px),
    repeating-linear-gradient(90deg, rgba(0, 200, 255, 0.015) 0px, transparent 1px, transparent 24px);
}
```

This is intentionally very subtle (1.5% opacity) — just enough to give the modal body digital texture without affecting readability.

**Step 2: Commit**

```bash
git add www/custom.css
git commit -m "style: add subtle digital grid texture to modal bodies"
```

---

## Item 4: Persistent Error Notifications

**Problem:** Error notifications auto-dismiss in ~5 seconds (Shiny default). If a user looks away, they miss the error. Success notifications don't need to be persistent, but errors and warnings should stick until dismissed.

**Approach:** Create a wrapper function `notify()` that standardizes duration behavior: errors are sticky (duration = NULL), warnings last 8 seconds, success messages last 4 seconds. Migrate all `showNotification()` calls to use `notify()`.

---

### Task 4.1: Create the notify() wrapper function

**Files:**
- Modify: `app.R` (add after the empty state helpers, before Configuration section)

**Step 1: Add the notify helper**

```r
# Standardized notification with smart duration
# - Errors: sticky until dismissed (duration = NULL)
# - Warnings: 8 seconds
# - Messages: 4 seconds
# Custom durations can still be passed to override
notify <- function(message, type = "message", duration = NULL, ...) {
  if (is.null(duration)) {
    duration <- switch(type,
      "error" = NULL,    # Sticky — user must dismiss
      "warning" = 8,     # Longer visibility
      "message" = 4,     # Brief confirmation
      5                   # Default fallback
    )
  }
  showNotification(message, type = type, duration = duration, ...)
}
```

**Step 2: Commit**

```bash
git add app.R
git commit -m "feat: add notify() wrapper with smart duration defaults"
```

---

### Task 4.2: Migrate admin server files to use notify()

**Files:**
- Modify: `server/admin-decks-server.R` (25 showNotification calls)
- Modify: `server/admin-formats-server.R` (14 calls)
- Modify: `server/admin-players-server.R` (15 calls)
- Modify: `server/admin-results-server.R` (30 calls)
- Modify: `server/admin-stores-server.R` (30 calls)
- Modify: `server/admin-tournaments-server.R` (18 calls)

**Step 1: Find-and-replace `showNotification` with `notify`**

In each server file, replace all occurrences of `showNotification(` with `notify(`.

**Important exceptions** — keep the existing explicit `duration` parameter where it's already set (these 11 calls already have intentional durations):
- `admin-decks-server.R`: lines 138, 349 (duration = 2), line 798 (duration = 8), line 992 (duration = 5)
- `admin-formats-server.R`: line 77 (duration = 2)
- `admin-players-server.R`: line 116 (duration = 2)
- `admin-results-server.R`: line 626 (duration = 3), line 1014 (duration = 5)
- `admin-stores-server.R`: lines 154, 418, 711 (duration = 2)
- `admin-tournaments-server.R`: line 51 (duration = 3)

For these, keep the explicit `duration = N` parameter. The `notify()` wrapper respects explicit durations.

**Step 2: Commit**

```bash
git add server/admin-decks-server.R server/admin-formats-server.R server/admin-players-server.R server/admin-results-server.R server/admin-stores-server.R server/admin-tournaments-server.R
git commit -m "refactor: migrate admin server files to notify() wrapper"
```

---

### Task 4.3: Migrate public and shared server files to use notify()

**Files:**
- Modify: `server/shared-server.R` (6 calls)
- Modify: `server/scene-server.R` (4 calls)
- Modify: `server/url-routing-server.R` (2 calls)
- Modify: `server/public-submit-server.R` (46 calls)
- Modify: `server/public-stores-server.R` (1 call)

**Step 1: Replace showNotification with notify in each file**

Same approach as Task 4.2 — find-and-replace `showNotification(` → `notify(`, keeping explicit `duration` parameters where they already exist:
- `shared-server.R`: line 614 (duration = 2)
- `url-routing-server.R`: line 201 (duration = 2)

**Step 2: Commit**

```bash
git add server/shared-server.R server/scene-server.R server/url-routing-server.R server/public-submit-server.R server/public-stores-server.R
git commit -m "refactor: migrate public/shared server files to notify() wrapper"
```

---

### Task 4.4: Add visual distinction for sticky notifications

**Files:**
- Modify: `www/custom.css` (after notification section, line ~3966)

**Step 1: Add CSS for sticky error notifications**

Sticky notifications (no auto-dismiss) should have a slightly more prominent close button to signal they need manual dismissal:

```css
/* Sticky notification emphasis - slightly larger close target */
.shiny-notification-error .close,
.shiny-notification-error .btn-close {
  opacity: 0.8;
  font-size: 1.1rem;
}

.shiny-notification-error .close:hover,
.shiny-notification-error .btn-close:hover {
  opacity: 1;
}
```

**Step 2: Commit**

```bash
git add www/custom.css
git commit -m "style: emphasize close button on sticky error notifications"
```

---

## Item 5: Consolidate Modal Systems

**Problem:** The app uses two incompatible modal systems: (1) Shiny's `showModal(modalDialog())` for dynamic content modals, and (2) static Bootstrap modals in HTML with `$('#id').modal('show')` for admin confirmations. The two systems behave differently (stacking, close behavior, accessibility) and the inconsistency makes maintenance harder.

**Approach:** Migrate all 8 static Bootstrap modals to use Shiny's `showModal()` pattern. This means:
1. Remove the static `tags$div(class = "modal fade", ...)` HTML from view files
2. Move modal content into server-side `showModal(modalDialog(...))` calls
3. Replace `$('#id').modal('show/hide')` JS calls with `showModal()` / `removeModal()`

This is a larger refactor, so we break it into per-page tasks.

---

### Task 5.1: Migrate admin-decks delete confirmation modal

**Files:**
- Modify: `views/admin-decks-ui.R` (remove lines 123-148, the delete_archetype_modal div)
- Modify: `server/admin-decks-server.R` (replace JS modal triggers with showModal/removeModal)

**Step 1: Remove static modal HTML from views/admin-decks-ui.R**

Delete the `tags$div(id = "delete_archetype_modal", ...)` block (lines 123-148).

**Step 2: Update server to use showModal for delete confirmation**

In `server/admin-decks-server.R`, find where `$('#delete_archetype_modal').modal('show')` is called (line ~446). Replace the block with:

```r
# Instead of: shinyjs::runjs("$('#delete_archetype_modal').modal('show');")
showModal(modalDialog(
  title = "Confirm Delete",
  uiOutput("delete_archetype_message"),
  footer = tagList(
    actionButton("confirm_delete_archetype", "Delete", class = "btn-danger"),
    modalButton("Cancel")
  ),
  easyClose = TRUE
))
```

Replace `$('#delete_archetype_modal').modal('hide')` calls (lines ~469, ~481) with `removeModal()`.

**Step 3: Commit**

```bash
git add views/admin-decks-ui.R server/admin-decks-server.R
git commit -m "refactor: migrate deck delete confirmation to Shiny modal system"
```

---

### Task 5.2: Migrate admin-decks merge modal

**Files:**
- Modify: `views/admin-decks-ui.R` (remove lines ~150-180, the merge_deck_modal div)
- Modify: `server/admin-decks-server.R` (replace JS triggers with showModal/removeModal)

**Step 1: Remove static modal HTML from views/admin-decks-ui.R**

Delete the `tags$div(id = "merge_deck_modal", ...)` block.

**Step 2: Update server to use showModal for merge**

Replace `$('#merge_deck_modal').modal('show')` (line ~880) with:

```r
showModal(modalDialog(
  title = tagList(bsicons::bs_icon("arrow-left-right"), " Merge Deck Archetypes"),
  p("Merge two deck archetypes into one. The source deck will be deleted and all its results will be reassigned to the target deck."),
  selectizeInput("merge_source_deck", "Source Deck (will be deleted)",
                 choices = deck_choices, options = list(placeholder = "Select deck to merge away...")),
  selectizeInput("merge_target_deck", "Target Deck (will keep)",
                 choices = deck_choices, options = list(placeholder = "Select deck to keep...")),
  hr(),
  uiOutput("merge_deck_preview"),
  footer = tagList(
    actionButton("confirm_merge_decks", "Merge Decks", class = "btn-warning"),
    modalButton("Cancel")
  ),
  size = "m",
  easyClose = TRUE
))
```

Note: The `deck_choices` variable needs to be computed before showing the modal — check the existing server code to see how choices are populated and replicate that logic.

Replace `$('#merge_deck_modal').modal('hide')` (line ~981) with `removeModal()`.

**Step 3: Commit**

```bash
git add views/admin-decks-ui.R server/admin-decks-server.R
git commit -m "refactor: migrate deck merge modal to Shiny modal system"
```

---

### Task 5.3: Migrate admin-players delete and merge modals

**Files:**
- Modify: `views/admin-players-ui.R` (remove lines 80-141, both modal divs)
- Modify: `server/admin-players-server.R` (replace JS triggers)

**Step 1: Remove both static modals from views/admin-players-ui.R**

Delete:
1. `tags$div(id = "delete_player_modal", ...)` (lines 80-105)
2. `tags$div(id = "merge_player_modal", ...)` (lines 107-141)

**Step 2: Update server for delete player**

Replace `$('#delete_player_modal').modal('show')` (line ~254) with:

```r
showModal(modalDialog(
  title = "Confirm Delete",
  uiOutput("delete_player_message"),
  footer = tagList(
    actionButton("confirm_delete_player", "Delete", class = "btn-danger"),
    modalButton("Cancel")
  ),
  easyClose = TRUE
))
```

Replace `$('#delete_player_modal').modal('hide')` (lines ~276, ~286) with `removeModal()`.

**Step 3: Update server for merge players**

Replace `$('#merge_player_modal').modal('show')` (line ~309) with:

```r
showModal(modalDialog(
  title = tagList(bsicons::bs_icon("arrow-left-right"), " Merge Players"),
  p("Merge two player records (e.g., fix a typo by combining duplicate entries)."),
  p(class = "text-muted small", "All results from the source player will be moved to the target player, then the source player will be deleted."),
  hr(),
  selectizeInput("merge_source_player", "Source Player (will be deleted)",
                 choices = player_choices,
                 options = list(placeholder = "Select player to merge FROM...")),
  selectizeInput("merge_target_player", "Target Player (will keep)",
                 choices = player_choices,
                 options = list(placeholder = "Select player to merge INTO...")),
  uiOutput("merge_preview"),
  footer = tagList(
    actionButton("confirm_merge_players", "Merge Players", class = "btn-warning"),
    modalButton("Cancel")
  ),
  size = "m",
  easyClose = TRUE
))
```

Replace `$('#merge_player_modal').modal('hide')` (line ~436) with `removeModal()`.

**Step 4: Commit**

```bash
git add views/admin-players-ui.R server/admin-players-server.R
git commit -m "refactor: migrate player delete and merge modals to Shiny modal system"
```

---

### Task 5.4: Migrate admin-formats delete confirmation modal

**Files:**
- Modify: `views/admin-formats-ui.R` (remove lines 59-82, the delete_format_modal div)
- Modify: `server/admin-formats-server.R` (replace JS triggers)

**Step 1: Remove static modal HTML**

Delete the `tags$div(id = "delete_format_modal", ...)` block.

**Step 2: Update server**

Replace `$('#delete_format_modal').modal('show')` (line ~225) with:

```r
showModal(modalDialog(
  title = "Confirm Delete",
  uiOutput("delete_format_message"),
  footer = tagList(
    actionButton("confirm_delete_format", "Delete", class = "btn-danger"),
    modalButton("Cancel")
  ),
  easyClose = TRUE
))
```

Replace `$('#delete_format_modal').modal('hide')` (line ~244) with `removeModal()`.

**Step 3: Commit**

```bash
git add views/admin-formats-ui.R server/admin-formats-server.R
git commit -m "refactor: migrate format delete confirmation to Shiny modal system"
```

---

### Task 5.5: Migrate admin-stores delete confirmation modal

**Files:**
- Modify: `views/admin-stores-ui.R` (remove lines ~174-199, the delete_store_modal div)
- Modify: `server/admin-stores-server.R` (replace JS triggers)

**Step 1: Remove static modal HTML**

Delete the `tags$div(id = "delete_store_modal", ...)` block.

**Step 2: Update server**

Replace `$('#delete_store_modal').modal('show')` (line ~597) with:

```r
showModal(modalDialog(
  title = "Confirm Delete",
  uiOutput("delete_store_message"),
  footer = tagList(
    actionButton("confirm_delete_store", "Delete", class = "btn-danger"),
    modalButton("Cancel")
  ),
  easyClose = TRUE
))
```

Replace `$('#delete_store_modal').modal('hide')` (line ~621) with `removeModal()`.

**Step 3: Commit**

```bash
git add views/admin-stores-ui.R server/admin-stores-server.R
git commit -m "refactor: migrate store delete confirmation to Shiny modal system"
```

---

### Task 5.6: Migrate admin-tournaments delete modal

**Files:**
- Modify: `views/admin-tournaments-ui.R` (remove lines ~106-129, the delete_tournament_modal div)
- Modify: `server/admin-tournaments-server.R` (replace JS triggers)

**Step 1: Remove static modal HTML**

Delete the `tags$div(id = "delete_tournament_modal", ...)` block.

**Step 2: Update server**

Replace `$('#delete_tournament_modal').modal('show')` (line ~324) with:

```r
showModal(modalDialog(
  title = "Confirm Delete",
  uiOutput("delete_tournament_message"),
  footer = tagList(
    actionButton("confirm_delete_tournament", "Delete", class = "btn-danger"),
    modalButton("Cancel")
  ),
  easyClose = TRUE
))
```

Replace `$('#delete_tournament_modal').modal('hide')` (line ~345) with `removeModal()`.

**Step 3: Commit**

```bash
git add views/admin-tournaments-ui.R server/admin-tournaments-server.R
git commit -m "refactor: migrate tournament delete confirmation to Shiny modal system"
```

---

### Task 5.7: Migrate admin-results static modals (3 modals)

**Files:**
- Modify: `views/admin-results-ui.R` (remove 3 modal divs: duplicate_tournament_modal, start_over_modal, paste_spreadsheet_modal)
- Modify: `server/admin-results-server.R` (replace JS triggers)

This task is larger since it covers 3 modals. Each follows the same pattern.

**Step 1: Remove all 3 static modal HTMLs from views/admin-results-ui.R**

Delete:
1. `tags$div(id = "duplicate_tournament_modal", ...)` (lines ~124-149)
2. `tags$div(id = "start_over_modal", ...)` (lines ~152-182)
3. `tags$div(id = "paste_spreadsheet_modal", ...)` (lines ~187-227)

**Step 2: Migrate duplicate_tournament_modal in server**

Replace `$('#duplicate_tournament_modal').modal('show')` (line ~139) with `showModal()` containing the duplicate tournament warning content (dynamic `uiOutput("duplicate_tournament_info")`).

Replace both hide calls (lines ~289, ~302) with `removeModal()`.

**Step 3: Migrate start_over_modal in server**

Replace `$('#start_over_modal').modal('show')` (line ~197) with `showModal()` containing the start-over options.

Replace hide calls (lines ~221, ~251) with `removeModal()`.

**Step 4: Migrate paste_spreadsheet_modal in server**

Replace `$('#paste_spreadsheet_modal').modal('show')` (line ~697) with:

```r
showModal(modalDialog(
  title = "Paste from Spreadsheet",
  p(class = "text-muted", "Paste tab-separated data: Player Name [TAB] Deck Name (one per line)"),
  tags$textarea(id = "paste_data", rows = 10, class = "form-control",
                placeholder = "PlayerName\tDeckName\nPlayerName\tDeckName"),
  footer = tagList(
    actionButton("submit_paste", "Import", class = "btn-primary"),
    modalButton("Cancel")
  ),
  size = "l",
  easyClose = TRUE
))
```

Replace `$('#paste_spreadsheet_modal').modal('hide')` (line ~793) with `removeModal()`.

**Step 5: Commit**

```bash
git add views/admin-results-ui.R server/admin-results-server.R
git commit -m "refactor: migrate all admin-results static modals to Shiny modal system"
```

---

### Task 5.8: Migrate admin-tournaments results editor and nested modals

**Files:**
- Modify: `views/admin-tournaments-ui.R` (remove lines ~133-288: tournament_results_modal, modal_edit_result, modal_delete_result_confirm)
- Modify: `server/admin-tournaments-server.R` (replace JS triggers)

**Note:** This is the most complex migration because the tournament results editor is a large modal (`modal-lg`) that contains nested modals (edit result, delete confirmation). With Shiny's modal system, only one modal can be shown at a time — `showModal()` replaces the current modal.

**Approach:** Convert the results editor to a `showModal()` with `size = "l"`. For the nested edit/delete modals, use `showModal()` which will replace the results editor modal. After the edit/delete completes, re-show the results editor modal.

**Step 1: Remove all 3 static modal HTMLs from views/admin-tournaments-ui.R**

Delete:
1. `tags$div(id = "tournament_results_modal", ...)` (lines ~133-211)
2. `tags$div(id = "modal_edit_result", ...)` (lines ~215-264)
3. `tags$div(id = "modal_delete_result_confirm", ...)` (lines ~268-288)

**Step 2: Convert results editor to showModal()**

Replace `$('#tournament_results_modal').modal('show')` (line ~393) with a `showModal(modalDialog(..., size = "l"))` containing the same content.

**Step 3: Convert edit result and delete confirmation to showModal()**

Replace `$('#modal_edit_result').modal('show')` (line ~516) with `showModal(modalDialog(...))`.

After edit/delete completes, re-open the results editor modal by calling the results editor showModal again. Add a helper function `show_results_modal()` to avoid code duplication.

Replace all corresponding hide calls with `removeModal()`.

**Step 4: Commit**

```bash
git add views/admin-tournaments-ui.R server/admin-tournaments-server.R
git commit -m "refactor: migrate tournament results editor and nested modals to Shiny modal system"
```

---

### Task 5.9: Standardize modal sizes across all detail modals

**Files:**
- Modify: `server/public-meta-server.R` (verify size = "l")
- Modify: `server/public-players-server.R` (verify size = "l")
- Modify: `server/public-stores-server.R` (verify size = "l")
- Modify: `server/public-tournaments-server.R` (verify size = "l")
- Modify: `server/shared-server.R` (login modal — keep small/default)

**Step 1: Audit and standardize**

Verify all detail modals (player, deck, store, tournament) use `size = "l"`. Verify all confirmation modals (delete, merge) use default size (small). Document the convention:

| Modal Type | Size |
|------------|------|
| Detail/Profile | `size = "l"` |
| Confirmation | Default (no size param) |
| Forms/Editors | `size = "l"` |
| Processing | `size = "s"` |

No code changes needed if already consistent — just verify. Fix any that deviate.

**Step 2: Commit (if changes needed)**

```bash
git commit -m "refactor: standardize modal sizes across all modals"
```

---

## Final Verification

### Task 6.1: Full app verification

**Step 1: Run syntax check**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "tryCatch(source('app.R'), error = function(e) cat('ERROR:', e$message, '\n'))"
```

**Step 2: Manual testing checklist**

Ask user to verify:
- [ ] App loads with skeleton loaders visible briefly
- [ ] Skeletons disappear when data renders
- [ ] Changing filters shows fade (recalculating) effect on tables/charts
- [ ] Empty states show Agumon mascot when no filters active
- [ ] Empty states show filter-aware message when filters produce no results
- [ ] Admin empty states show consistent styling
- [ ] All card headers have subtle grid pattern (visible in both light/dark mode)
- [ ] Modal bodies have subtle grid texture
- [ ] Error notifications persist until manually dismissed
- [ ] Warning notifications last ~8 seconds
- [ ] Success notifications last ~4 seconds
- [ ] All admin delete confirmations work (deck, player, format, store, tournament)
- [ ] All admin merge operations work (deck, player)
- [ ] Tournament results editor opens and nested edit/delete flows work
- [ ] Paste from spreadsheet modal works
- [ ] All modal close buttons work correctly
- [ ] Dark mode looks correct for all changes

**Step 3: Final commit**

```bash
git add -A
git commit -m "docs: update plan with completion status"
```

---

## Summary

| Item | Tasks | Scope |
|------|-------|-------|
| 1. Loading indicators | 1.1-1.4 | CSS + R helpers + view wrappers + JS |
| 2. Empty states | 2.1-2.3 | R helper + admin pages + filter-aware public pages |
| 3. Digital aesthetic | 3.1-3.3 | CSS only (card headers + modal bodies) |
| 4. Notifications | 4.1-4.4 | R wrapper + find/replace across all server files + CSS |
| 5. Modal consolidation | 5.1-5.9 | Remove static HTML + rewrite server modal triggers |

**Estimated commits:** ~20 small, logical commits
**Files touched:** ~22 files (app.R, www/custom.css, 6 view files, 12 server files, 1 doc)
