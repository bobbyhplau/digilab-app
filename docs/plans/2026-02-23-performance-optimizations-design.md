# Performance Optimizations: Lazy Admin UI + Extended bindCache

**Date:** 2026-02-23
**Status:** Approved
**Context:** Load testing (docs/profiling-report.md) found the performance knee at 5 concurrent users on a single R process. Two code-level optimizations reduce per-session overhead.

## Optimization #3: Lazy Admin UI via renderUI

### Problem

All 8 admin view files (`views/admin-*.R`) are sourced at app.R:380-387 during UI construction. Every session builds the full admin tab panel DOM, even though ~99% of users are regular visitors. The admin server modules are already lazy-loaded behind `rv$is_admin` (app.R:1028-1037), but the UI side isn't.

### Solution

Replace the 8 `source("views/admin-*.R")` calls in the UI definition with a single `uiOutput("admin_tabs_ui")` placeholder. In the server, render the admin UI only after `rv$is_admin` becomes TRUE.

- Regular users: admin tab area is an empty `uiOutput` — no DOM, no R evaluation of admin view files
- Admin users: on login, server renders the full admin tabs into the placeholder
- Brief flash when admin tabs first appear is acceptable (admin logs in once per session)

### Files

- `app.R` — replace admin view sources in UI with `uiOutput()`, add `renderUI` in server

## Optimization #4: bindCache on Public Tabs

### Problem

14 `bindCache()` calls exist, all on the Dashboard tab. The other 4 public tabs (Players, Meta, Tournaments, Stores) have none. Every tab switch or scene change re-runs the full query + render pipeline.

### Solution

Add `bindCache()` to the main outputs on each public tab:

| Tab | Output | Cache Keys |
|-----|--------|------------|
| Players | `player_standings` | format, scene, community, data_refresh |
| Meta | `archetype_stats` | format, event_type, scene, community, data_refresh |
| Tournaments | `tournament_history` | format, event_type, scene, community, data_refresh |
| Stores | `store_list` | scene, community, data_refresh |
| Stores | `stores_cards_content` | scene, community, data_refresh |
| Stores | `online_stores_section` | scene, community, data_refresh |
| Stores | `stores_map` | scene, community, dark_mode, data_refresh |

Cache keys mirror the pattern from Dashboard: all the filter inputs that affect the output, plus `rv$data_refresh` to bust cache on admin data changes.

### Files

- `server/public-players-server.R`
- `server/public-meta-server.R`
- `server/public-tournaments-server.R`
- `server/public-stores-server.R`

## What This Does NOT Do

- No query optimization or async changes
- No connection pooling
- No changes to admin server modules (already lazy-loaded)
