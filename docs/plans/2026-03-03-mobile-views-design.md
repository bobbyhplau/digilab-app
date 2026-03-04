# Mobile Views Design — Separate Mobile Rendering for Public Pages

## Goal

Replace the current CSS-only mobile adaptation with server-aware device detection and dedicated mobile view modules for all 5 public pages. Mobile users get purpose-built layouts (stacked cards, compact maps, horizontal scroll sections) instead of cramped desktop layouts.

## Architecture

JS detects device type on page load and sends it to Shiny via `setInputValue`. A shared `rv$is_mobile` reactive drives conditional `uiOutput` rendering — each page sources either its desktop or mobile view file. Server logic (data reactives, click handlers, modals) is shared between both layouts. A new `www/mobile.css` file handles mobile-specific component styles while existing `custom.css` media queries serve as fallback.

## Context

- The app runs both standalone at `app.digilab.cards` and inside an iframe in the `digilab-web` repo
- Current mobile handling is CSS-only — no server-side device awareness
- Sidebar is hidden on mobile, bottom tab bar provides navigation
- The existing loading screen covers the window before detection completes, preventing layout flash

---

## 1. Device Detection

### JS Snippet (app.R, runs in existing `tags$script` block)

```javascript
var deviceInfo = {
  type: window.innerWidth <= 768 ? 'mobile' : 'desktop',
  width: window.innerWidth,
  touch: 'ontouchstart' in window,
  standalone: window.matchMedia('(display-mode: standalone)').matches
};

$(document).on('shiny:connected', function() {
  Shiny.setInputValue('device_info', deviceInfo);
});
```

- **Single detect on load** — no resize listener, no re-render on rotation
- Fires during loading screen, so `rv$is_mobile` is set before `hideLoading`
- Breakpoint: `768px` (matches existing CSS mobile threshold)

### Server Reactive (shared-server.R)

```r
rv$is_mobile <- reactive({
  info <- input$device_info
  if (is.null(info)) return(FALSE)
  info$type == "mobile"
})
```

- Defaults to `FALSE` (desktop) if JS hasn't fired yet
- Available to all server modules via `rv`

---

## 2. Conditional Rendering Pattern

### UI Wrappers (app.R)

Each `nav_panel` wraps its content in `uiOutput`:

```r
nav_panel("Overview", value = "overview", uiOutput("dashboard_page"))
nav_panel("Players", value = "players", uiOutput("players_page"))
# ... etc
```

### Server Switch (each public-*-server.R)

```r
output$dashboard_page <- renderUI({
  if (rv$is_mobile()) {
    source("views/mobile-dashboard-ui.R", local = TRUE)$value
  } else {
    source("views/dashboard-ui.R", local = TRUE)$value
  }
})
```

- Desktop view files are unchanged
- Mobile view files are new, additive
- Server logic (data reactives, observers, click handlers) is shared

---

## 3. File Structure

### New Files

```
views/
├── mobile-dashboard-ui.R
├── mobile-players-ui.R
├── mobile-meta-ui.R
├── mobile-tournaments-ui.R
├── mobile-stores-ui.R
www/
├── mobile.css
```

### Modified Files

```
app.R                          # JS detection + uiOutput wrappers
server/shared-server.R         # rv$is_mobile reactive
server/public-dashboard-server.R  # renderUI switch + mobile card renderers
server/public-players-server.R    # renderUI switch + mobile card renderers
server/public-meta-server.R       # renderUI switch + mobile card renderers
server/public-tournaments-server.R # renderUI switch + mobile card renderers
server/public-stores-server.R     # renderUI switch + mobile card renderers
```

---

## 4. Mobile Page Designs

### 4a. Dashboard (mobile-dashboard-ui.R)

Vertical scroll, single column:

1. **Value boxes** — 2x2 grid (existing breakpoints handle this already, kept as-is)
2. **Tournament Activity chart** — full width, 250px height
3. **Meta Breakdown chart** — full width, 250px height
4. **Rising Stars** — horizontal scrollable row (`overflow-x: auto; scroll-snap-type: x mandatory`), cards ~280px wide
5. **Top Decks** — same horizontal scroll pattern

Section headers between each block for visual separation.

### 4b. Players (mobile-players-ui.R)

Filter strip at top (unchanged — existing stacking behavior works).

Stacked cards replacing the reactable table:

```
┌─────────────────────────┐
│ 1  PlayerName       1502│
│    ▲ 12.3%    8-2   .800│
│    Main Deck: Imperialdramon│
└─────────────────────────┘
```

- Rank number (colored for 1st/2nd/3rd)
- Rating top-right
- Trend, record, win rate on second row
- Main deck with archetype badge on third row
- Tap → existing player modal
- Pagination: render 20 cards, "Load more" button

### 4c. Meta (mobile-meta-ui.R)

Filter strip at top (unchanged).

Stacked cards:

```
┌─────────────────────────┐
│ 🟡 Imperialdramon       │
│ 14 entries · 18.2% meta │
│ 64.3% win · 3 tops      │
└─────────────────────────┘
```

- Color dot + deck name
- Entry count + meta share
- Win rate + top placements
- Tap → deck detail modal

### 4d. Tournaments (mobile-tournaments-ui.R)

Filter strip at top (unchanged).

Stacked cards:

```
┌─────────────────────────┐
│ Mar 1, 2026             │
│ Common Ground Games      │
│ 16 players · Winner: Fox │
└─────────────────────────┘
```

- Date prominent
- Store name
- Player count + winner
- Tap → tournament detail modal

### 4e. Stores (mobile-stores-ui.R)

Filter strip at top (unchanged).

Map (200px) on top, store cards below:

```
┌─────────────────────────┐
│  ┌───────────────────┐  │
│  │   mapgl (200px)    │  │
│  └───────────────────┘  │
├─────────────────────────┤
│ ┌─────────────────────┐ │
│ │ Common Ground Games │ │
│ │ Fri · Weekly · 6pm  │ │
│ │ Dallas, TX          │ │
│ │ 12 events · ★ 1423  │ │
│ └─────────────────────┘ │
└─────────────────────────┘
```

- Tap store card → map pans to location, opens popup
- Tap map pin → scrolls to and highlights corresponding card
- Same store detail modal on tap

---

## 5. Mobile Card CSS (www/mobile.css)

### Shared Components

```css
.mobile-list-card {
  padding: 0.75rem 1rem;
  border: 1px solid rgba(0, 200, 255, 0.1);
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.03);
  margin-bottom: 0.5rem;
  cursor: pointer;
  -webkit-tap-highlight-color: rgba(0, 200, 255, 0.1);
  transition: background 0.15s ease;
}

.mobile-list-card:active {
  background: rgba(0, 200, 255, 0.08);
}

.mobile-card-list {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  padding: 0 0.25rem;
}

.mobile-horizontal-scroll {
  display: flex;
  gap: 0.75rem;
  overflow-x: auto;
  scroll-snap-type: x mandatory;
  -webkit-overflow-scrolling: touch;
  padding: 0.5rem 0.25rem;
}

.mobile-horizontal-scroll > * {
  scroll-snap-align: start;
  flex-shrink: 0;
  width: 280px;
}

.mobile-map-compact {
  height: 200px;
  border-radius: 8px;
  overflow: hidden;
  margin-bottom: 0.75rem;
}

.mobile-section-header {
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  opacity: 0.55;
  padding: 0.75rem 0 0.25rem;
}
```

### Dark Mode Variants

```css
[data-bs-theme="dark"] .mobile-list-card {
  border-color: rgba(255, 255, 255, 0.08);
  background: rgba(255, 255, 255, 0.02);
}

[data-bs-theme="dark"] .mobile-list-card:active {
  background: rgba(255, 255, 255, 0.06);
}
```

### Load More Button

```css
.mobile-load-more {
  width: 100%;
  padding: 0.75rem;
  text-align: center;
  font-size: 0.85rem;
  border: 1px dashed rgba(0, 200, 255, 0.2);
  border-radius: 8px;
  cursor: pointer;
  margin-top: 0.25rem;
}
```

### Loading via R

```r
# Loaded conditionally in the mobile renderUI
if (rv$is_mobile()) {
  tags$link(rel = "stylesheet", href = "mobile.css")
}
```

Existing `custom.css` media queries remain as fallback (before JS detection fires).

---

## 6. Pagination Pattern

All card-based pages use a "Load more" pattern:

```r
# Reactive tracking how many cards to show
rv$mobile_players_limit <- reactiveVal(20)

# Observer for load more button
observeEvent(input$mobile_players_load_more, {
  rv$mobile_players_limit(rv$mobile_players_limit() + 20)
})

# In renderUI, slice the data
output$mobile_players_cards <- renderUI({
  data <- filtered_players()
  n <- min(rv$mobile_players_limit(), nrow(data))
  show_data <- data[1:n, ]

  cards <- lapply(seq_len(nrow(show_data)), function(i) {
    # ... card HTML
  })

  tagList(
    div(class = "mobile-card-list", cards),
    if (n < nrow(data)) {
      actionButton("mobile_players_load_more",
                   sprintf("Load more (%d remaining)", nrow(data) - n),
                   class = "mobile-load-more")
    }
  )
})
```

---

## 7. Scope Boundaries

### In scope (this phase)
- Device detection system (JS + `rv$is_mobile`)
- 5 mobile view files (Dashboard, Players, Meta, Tournaments, Stores)
- `www/mobile.css`
- Conditional rendering in `app.R` and 5 server modules
- Stacked card pattern for all table pages
- Compact map on Stores page
- Horizontal scroll for Dashboard highlight sections
- Load-more pagination

### Out of scope (future phases)
1. **Modals → full-screen overlays** — planned, separate design
2. **Upload Results mobile view** — next after this phase
3. **Admin pages mobile views** — after Upload Results
4. **Tablet-specific views** — tablet gets desktop layout
5. **Resize detection** — single detect only, no rotation handling
6. **Offline / service worker** — separate PWA effort
7. **CSS cleanup** — removing redundant media queries from custom.css (future pass)
