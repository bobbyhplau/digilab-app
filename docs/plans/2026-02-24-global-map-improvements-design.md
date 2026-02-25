# Global Map Improvements Design

**Date:** 2026-02-24
**Status:** Approved

## Problem

As DigiLab onboards international scenes, the "All Scenes" stores map becomes hard to use:
1. Mapbox GL defaults to globe projection at low zoom — awkward for viewing scattered global stores
2. Regional scenes with few stores (Vancouver: 4, Wellington: 1) zoom in too tight, losing geographic context

## Changes

### 1. "All Scenes" → Flat World Map with Combined Markers

When `rv$current_scene == "all"`, render a flat mercator world map showing **both** physical stores and online organizers.

- **Projection:** `"mercator"` (same as existing online map)
- **Center:** `c(-40, 20)` / **Zoom:** `1.5` (same as online map)
- **Physical stores:** Orange (`#F7941D`), bubble-sized by avg event size
- **Online organizers:** Green (`#10B981`), bubble-sized by tournament count
- Two separate circle layers on the same map
- Each marker type keeps its existing popup format

### 2. Regional Scene Maps — Max Zoom Cap

Add `maxZoom = 9` to `fit_bounds()` so regional maps never zoom tighter than region level.

- DFW (many stores): No change — already zooms out past 9
- Vancouver (4 stores): Zooms to ~9 instead of tight framing
- Wellington (1 store): Shows wider region instead of a single block

## Implementation

All changes in `server/public-stores-server.R`:
- Add branch for `scene == "all"` in `output$stores_map` that renders combined world map
- Reuse existing online organizer query + `stores_data()` for physical stores
- Add `maxZoom = 9` to `fit_bounds()` call for regional scenes
- No new files, schema changes, or reactive values
