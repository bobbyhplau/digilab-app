# PWA1: Progressive Web App — Design Document

**Date:** 2026-02-23
**Status:** Approved
**Goal:** Make DigiLab installable ("Add to Home Screen") with a polished offline fallback screen.

## Approach

**Offline-only service worker.** Shiny apps are fully server-rendered via WebSocket — there's no meaningful offline experience beyond a static fallback page. The service worker's only job is to serve the offline page when the network is unavailable. It does NOT cache any Shiny app resources (CSS, JS, HTML) because cached shells can't function without a live server connection.

This gives us installability and a polished offline UX with near-zero risk of caching bugs.

## Components

### 1. Web App Manifest (`www/manifest.json`)

Standard PWA manifest with:
- `name`: "DigiLab - Digimon TCG Locals Tracker"
- `short_name`: "DigiLab"
- `display`: "standalone"
- `background_color` / `theme_color`: "#1a1a2e" (dark digital aesthetic)
- `start_url`: "/"
- Icons: 192px and 512px in both standard (transparent) and maskable (dark bg, 80% safe zone) variants

No conflict with Posit Connect's deployment `manifest.json` at repo root — Shiny serves `www/` contents as static files, so the PWA manifest is served from the `www/` directory path.

### 2. Service Worker (`www/sw.js`)

~30 lines. Three event handlers:

- **install**: Precaches `offline.html` and `agumon.svg`
- **activate**: Deletes old caches on version bump
- **fetch**: Only intercepts `navigate` mode requests. On network failure, serves the offline page. All other requests (WebSocket, XHR, assets) pass through untouched.

Key constraint: the service worker never touches Shiny's WebSocket traffic or asset loads.

### 3. Offline Page (`www/offline.html`)

Self-contained static HTML matching the existing disconnect overlay aesthetic:

- Dark background (#1a1a2e)
- Agumon SVG with pulsing animation (inlined — no external dependencies)
- "You're Offline" title
- "The Digital Gate can't be reached. Check your connection and try again." message
- "Retry" button (`location.reload()`)
- All styles inline (works without CSS or JS files)

### 4. App Icons (`www/icons/`)

Generated from `www/digivice.svg` using Python (`cairosvg` + `Pillow`):

| File | Size | Purpose |
|------|------|---------|
| `icon-192.png` | 192x192 | Standard icon, also `apple-touch-icon` |
| `icon-512.png` | 512x512 | Standard icon, splash screen |
| `icon-maskable-192.png` | 192x192 | Android adaptive icons (dark bg, 80% safe zone) |
| `icon-maskable-512.png` | 512x512 | Android adaptive icons (dark bg, 80% safe zone) |
| `favicon.ico` | 32x32 | Browser tab favicon |

### 5. Head Tags (`app.R`)

Added to `tags$head()`:

```r
# PWA manifest and theme
tags$link(rel = "manifest", href = "manifest.json"),
tags$meta(name = "theme-color", content = "#1a1a2e"),

# Icons
tags$link(rel = "icon", type = "image/x-icon", href = "favicon.ico"),
tags$link(rel = "apple-touch-icon", href = "icons/icon-192.png"),

# iOS standalone mode
tags$meta(name = "apple-mobile-web-app-capable", content = "yes"),
tags$meta(name = "apple-mobile-web-app-status-bar-style", content = "black-translucent"),

# Service worker registration
tags$script(HTML("if('serviceWorker' in navigator){navigator.serviceWorker.register('sw.js');}"))
```

## What This Does NOT Do

- No caching of app shell, CSS, JS, or images
- No background sync or push notifications
- No Workbox or build dependencies
- No interference with Shiny WebSocket or keepalive

## Files Changed/Created

| Action | File |
|--------|------|
| Create | `www/manifest.json` |
| Create | `www/sw.js` |
| Create | `www/offline.html` |
| Create | `www/icons/icon-192.png` |
| Create | `www/icons/icon-512.png` |
| Create | `www/icons/icon-maskable-192.png` |
| Create | `www/icons/icon-maskable-512.png` |
| Create | `www/favicon.ico` |
| Create | `scripts/generate_icons.py` (one-time icon generation) |
| Modify | `app.R` (head tags) |
