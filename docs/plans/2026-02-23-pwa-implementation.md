# PWA1: Progressive Web App — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make DigiLab installable ("Add to Home Screen") with Agumon offline fallback screen.

**Architecture:** Offline-only service worker that precaches a static offline page. No app shell caching — Shiny apps require a live WebSocket connection. PWA manifest enables installability on mobile/desktop. Icons generated from existing Digivice SVG.

**Tech Stack:** HTML, JavaScript (service worker API), Python (cairosvg + Pillow for icon generation), R Shiny (head tag injection)

---

### Task 1: Generate App Icons from Digivice SVG

**Files:**
- Create: `scripts/generate_pwa_icons.py`
- Create: `www/icons/icon-192.png`
- Create: `www/icons/icon-512.png`
- Create: `www/icons/icon-maskable-192.png`
- Create: `www/icons/icon-maskable-512.png`
- Create: `www/favicon.ico`
- Reference: `www/digivice.svg` (source SVG, 24x24 viewBox)

**Context:** The Digivice SVG at `www/digivice.svg` is a 24x24 viewBox line-art icon using `currentColor` for strokes. For PWA icons we need it rasterized in white on transparent (standard) and white on dark background (maskable). The maskable icons need the content in the inner 80% "safe zone" so Android adaptive icons don't clip it.

**Step 1: Create the icon generation script**

Create `scripts/generate_pwa_icons.py`:

```python
"""Generate PWA icons and favicon from Digivice SVG.

Usage: python scripts/generate_pwa_icons.py

Requires: pip install cairosvg Pillow
"""
import os
import io
import cairosvg
from PIL import Image

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
SVG_PATH = os.path.join(PROJECT_ROOT, "www", "digivice.svg")
ICONS_DIR = os.path.join(PROJECT_ROOT, "www", "icons")
FAVICON_PATH = os.path.join(PROJECT_ROOT, "www", "favicon.ico")

# Dark background matching app theme
BG_COLOR = "#1a1a2e"
# White stroke for visibility on dark/transparent backgrounds
STROKE_COLOR = "#ffffff"

SIZES = [192, 512]
FAVICON_SIZE = 32


def read_svg_with_color(color):
    """Read SVG and replace currentColor with specified color."""
    with open(SVG_PATH, "r") as f:
        svg = f.read()
    return svg.replace("currentColor", color)


def svg_to_png(svg_string, output_size):
    """Render SVG string to PNG at given size, return PIL Image."""
    png_data = cairosvg.svg2png(
        bytestring=svg_string.encode("utf-8"),
        output_width=output_size,
        output_height=output_size,
    )
    return Image.open(io.BytesIO(png_data)).convert("RGBA")


def generate_standard_icon(size):
    """Generate standard icon: white Digivice on transparent, padded to 85% of canvas."""
    svg = read_svg_with_color(STROKE_COLOR)
    # Render at full size, then paste onto padded canvas
    icon_size = int(size * 0.85)
    icon = svg_to_png(svg, icon_size)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = (size - icon_size) // 2
    canvas.paste(icon, (offset, offset), icon)
    return canvas


def generate_maskable_icon(size):
    """Generate maskable icon: white Digivice on dark bg, content in inner 80% safe zone."""
    svg = read_svg_with_color(STROKE_COLOR)
    # Maskable safe zone is inner 80% (40/2=20% padding each side)
    safe_size = int(size * 0.60)  # Content smaller within safe zone for breathing room
    icon = svg_to_png(svg, safe_size)
    # Parse bg color
    r, g, b = int(BG_COLOR[1:3], 16), int(BG_COLOR[3:5], 16), int(BG_COLOR[5:7], 16)
    canvas = Image.new("RGBA", (size, size), (r, g, b, 255))
    offset = (size - safe_size) // 2
    canvas.paste(icon, (offset, offset), icon)
    return canvas


def main():
    os.makedirs(ICONS_DIR, exist_ok=True)

    for size in SIZES:
        # Standard icons
        standard = generate_standard_icon(size)
        path = os.path.join(ICONS_DIR, f"icon-{size}.png")
        standard.save(path, "PNG")
        print(f"Created {path}")

        # Maskable icons
        maskable = generate_maskable_icon(size)
        path = os.path.join(ICONS_DIR, f"icon-maskable-{size}.png")
        maskable.save(path, "PNG")
        print(f"Created {path}")

    # Favicon (32x32 ICO from standard icon)
    favicon = generate_standard_icon(FAVICON_SIZE)
    favicon.save(FAVICON_PATH, "ICO", sizes=[(FAVICON_SIZE, FAVICON_SIZE)])
    print(f"Created {FAVICON_PATH}")

    print("\nDone! Generated 4 PNG icons + 1 favicon.")


if __name__ == "__main__":
    main()
```

**Step 2: Install dependencies and run the script**

```bash
pip install cairosvg Pillow
python scripts/generate_pwa_icons.py
```

Expected output:
```
Created .../www/icons/icon-192.png
Created .../www/icons/icon-maskable-192.png
Created .../www/icons/icon-512.png
Created .../www/icons/icon-maskable-512.png
Created .../www/favicon.ico

Done! Generated 4 PNG icons + 1 favicon.
```

**Step 3: Verify the generated files exist and have reasonable sizes**

```bash
ls -la www/icons/
ls -la www/favicon.ico
```

Expected: 4 PNG files in `www/icons/`, 1 ICO file in `www/`. All should be >0 bytes. The 512px PNGs should be a few KB, the 192px ones smaller.

**Step 4: Commit**

```bash
git add scripts/generate_pwa_icons.py www/icons/ www/favicon.ico
git commit -m "feat(pwa): generate app icons and favicon from Digivice SVG"
```

---

### Task 2: Create the Web App Manifest

**Files:**
- Create: `www/manifest.json`

**Context:** This file makes the app installable. Shiny serves everything in `www/` as static files, so `www/manifest.json` will be accessible at `https://digilab.cards/manifest.json`. The Posit Connect deployment manifest at the repo root (`manifest.json`) is never served to browsers — no conflict.

**Step 1: Create the manifest file**

Create `www/manifest.json`:

```json
{
  "name": "DigiLab - Digimon TCG Locals Tracker",
  "short_name": "DigiLab",
  "description": "Track player performance, deck meta, and tournament results for your local Digimon TCG community",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#1a1a2e",
  "theme_color": "#1a1a2e",
  "icons": [
    {
      "src": "icons/icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "icons/icon-512.png",
      "sizes": "512x512",
      "type": "image/png"
    },
    {
      "src": "icons/icon-maskable-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "maskable"
    },
    {
      "src": "icons/icon-maskable-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "maskable"
    }
  ]
}
```

**Step 2: Verify JSON is valid**

```bash
python -c "import json; json.load(open('www/manifest.json')); print('Valid JSON')"
```

Expected: `Valid JSON`

**Step 3: Commit**

```bash
git add www/manifest.json
git commit -m "feat(pwa): add web app manifest"
```

---

### Task 3: Create the Offline Page

**Files:**
- Create: `www/offline.html`
- Reference: `www/custom.css:4393-4512` (disconnect overlay styles to match)
- Reference: `www/agumon.svg` (inline the SVG content)

**Context:** This is a fully self-contained HTML page served by the service worker when the user is offline. It must work with ZERO external dependencies — all CSS and SVG are inlined. The visual design matches the existing disconnect overlay in `www/custom.css` (dark gradient background, Agumon with pulsing rings, styled button).

**Step 1: Create the offline page**

Create `www/offline.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="theme-color" content="#1a1a2e">
  <title>DigiLab - Offline</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }

    body {
      min-height: 100vh;
      background: linear-gradient(135deg, rgba(10, 48, 85, 0.98) 0%, rgba(15, 76, 129, 0.98) 100%);
      background-image:
        repeating-linear-gradient(0deg, rgba(255,255,255,0.02) 0px, transparent 1px, transparent 40px),
        repeating-linear-gradient(90deg, rgba(255,255,255,0.02) 0px, transparent 1px, transparent 40px),
        linear-gradient(135deg, rgba(10, 48, 85, 0.98) 0%, rgba(15, 76, 129, 0.98) 100%);
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }

    .offline-icon {
      width: 80px;
      height: 80px;
      margin-bottom: 1.5rem;
      position: relative;
      display: flex;
      align-items: center;
      justify-content: center;
    }

    .offline-icon svg {
      width: 48px;
      height: 48px;
      filter: drop-shadow(0 0 6px rgba(247, 148, 29, 0.4));
      opacity: 0.7;
      animation: agumon-pulse 3s ease-in-out infinite;
    }

    @keyframes agumon-pulse {
      0%, 100% { opacity: 0.5; transform: scale(0.95); }
      50% { opacity: 0.8; transform: scale(1); }
    }

    .offline-icon::before,
    .offline-icon::after {
      content: '';
      position: absolute;
      border: 3px solid;
      border-radius: 50%;
    }

    .offline-icon::before {
      top: 0; left: 0; right: 0; bottom: 0;
      border-color: rgba(247, 148, 29, 0.4);
      border-top-color: transparent;
      border-right-color: transparent;
      animation: ring-pulse 2s ease-in-out infinite;
    }

    .offline-icon::after {
      top: 12px; left: 12px; right: 12px; bottom: 12px;
      border-color: rgba(0, 200, 255, 0.4);
      border-bottom-color: transparent;
      border-left-color: transparent;
      animation: ring-pulse 2s ease-in-out infinite 0.5s;
    }

    @keyframes ring-pulse {
      0%, 100% { opacity: 0.4; transform: scale(1); }
      50% { opacity: 1; transform: scale(1.05); }
    }

    .offline-title {
      color: rgba(255, 255, 255, 0.95);
      font-size: 1.3rem;
      font-weight: 600;
      margin-bottom: 0.5rem;
      text-align: center;
    }

    .offline-message {
      color: rgba(0, 200, 255, 0.9);
      font-size: 0.95rem;
      margin-bottom: 1.5rem;
      text-align: center;
      max-width: 280px;
      line-height: 1.4;
    }

    .offline-btn {
      background: linear-gradient(135deg, rgba(0, 200, 255, 0.2) 0%, rgba(15, 76, 129, 0.3) 100%);
      border: 1px solid rgba(0, 200, 255, 0.5);
      color: rgba(255, 255, 255, 0.95);
      padding: 0.75rem 2rem;
      font-size: 0.95rem;
      font-weight: 500;
      border-radius: 6px;
      cursor: pointer;
      transition: all 0.2s ease;
    }

    .offline-btn:hover {
      background: linear-gradient(135deg, rgba(0, 200, 255, 0.3) 0%, rgba(15, 76, 129, 0.4) 100%);
      border-color: rgba(0, 200, 255, 0.7);
      transform: translateY(-1px);
    }

    .offline-btn:active {
      transform: translateY(0);
    }
  </style>
</head>
<body>
  <div class="offline-icon">
    <!-- Agumon SVG inlined for offline availability -->
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" stroke="#F7941D" fill="none" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
      <g transform="matrix(0.83 0 0 0.83 12 12)">
        <g>
          <g transform="matrix(1 0 0 1 -1.37 -5.11)">
            <path d="M 11.7644 9.4961 L 9.18799 10.7838 C 8.91075 10.9225 8.60501 10.9948 8.29501 10.9948 L 4.24725 10.9948 C 3.80632 10.9948 3.37002 10.905 2.96493 10.7308 C 2.55985 10.5567 2.19447 10.3018 1.89107 9.98189 C 1.58767 9.66195 1.3526 9.28356 1.20018 8.86981 C 1.04777 8.45606 0.981209 8.01561 1.00456 7.57529 C 1.07944 6.7239 1.47496 5.93274 2.11109 5.36191 C 2.74721 4.79109 3.57642 4.48324 4.43093 4.50064 L 7.99897 4.50064 C 8.45142 3.62999 9.09522 2.87314 9.88204 2.28691 C 10.6689 1.70068 11.5783 1.3003 12.542 1.11583 C 13.5057 0.931367 14.4986 0.967605 15.4463 1.22183 C 16.394 1.47605 17.2718 1.94164 18.0138 2.58367 C 18.7558 3.22569 19.3427 4.02746 19.7305 4.92877 C 20.1183 5.83009 20.2969 6.80755 20.2528 7.78776 C 20.2088 8.76797 19.9433 9.72547 19.4762 10.5884 C 19.0091 11.4513 18.3527 12.1972 17.5561 12.7701"/>
          </g>
          <g transform="matrix(1 0 0 1 1.54 -6.6)">
            <path d="M 13.7203 5.76587 C 13.518 5.76587 13.3539 5.60184 13.3539 5.39949 C 13.3539 5.19714 13.518 5.03311 13.7203 5.03311"/>
          </g>
          <g transform="matrix(1 0 0 1 1.9 -6.6)">
            <path d="M 13.7203 5.76587 C 13.9227 5.76587 14.0867 5.60184 14.0867 5.39949 C 14.0867 5.19714 13.9227 5.03311 13.7203 5.03311"/>
          </g>
          <g transform="matrix(1 0 0 1 -5.73 -1.75)">
            <path d="M 6.26871 10.9948 L 6.26871 9.49609"/>
          </g>
          <g transform="matrix(1 0 0 1 -2.96 -0.54)">
            <path d="M 8.80695 10.9284 L 9.26614 11.9943"/>
          </g>
          <g transform="matrix(1 0 0 1 -4.31 8.75)">
            <path d="M 9.72048 18.51 C 8.13265 18.9942 6.76427 20.0187 5.8525 21.4058 C 5.74594 21.5552 5.68258 21.7311 5.66935 21.9141 C 5.65612 22.0972 5.69353 22.2803 5.77749 22.4435 C 5.86145 22.6066 5.98871 22.7436 6.14533 22.8392 C 6.30194 22.9348 6.48186 22.9855 6.66537 22.9857 L 9.65502 22.9857"/>
          </g>
          <g transform="matrix(1 0 0 1 -5.23 0.49)">
            <path d="M 10.2657 13.9923 L 5.26923 13.9923 C 5.00681 13.9924 4.74694 13.9408 4.50448 13.8405 C 4.26201 13.7401 4.04171 13.5929 3.85615 13.4074 C 3.6706 13.2218 3.52343 13.0015 3.42307 12.7591 C 3.3227 12.5166 3.27111 12.2567 3.27124 11.9943 L 3.27124 11.9943 C 3.27111 11.8631 3.29684 11.7332 3.34697 11.6119 C 3.39709 11.4906 3.47062 11.3805 3.56335 11.2876 C 3.65608 11.1948 3.7662 11.1212 3.88741 11.0709 C 4.00862 11.0207 4.13854 10.9948 4.26974 10.9948"/>
          </g>
          <g transform="matrix(1 0 0 1 3.78 5.88)">
            <path d="M 17.5561 12.7701 L 18.2918 14.1799 C 18.4788 14.5382 18.7379 14.854 19.0528 15.1073 C 19.3677 15.3607 19.7316 15.5462 20.1217 15.6522 C 20.5117 15.7582 20.9195 15.7823 21.3193 15.7231 C 21.7192 15.664 22.1024 15.5227 22.4451 15.3083 L 23 14.9615 C 23 18.51 21.7299 20.335 19.7583 20.4875 L 19.7583 21.9862 C 19.7583 22.2513 19.653 22.5055 19.4655 22.6929 C 19.2781 22.8804 19.0239 22.9857 18.7588 22.9857 L 13.2191 22.9857 C 13.0356 22.9855 12.8557 22.9348 12.6991 22.8392 C 12.5425 22.7436 12.4152 22.6066 12.3313 22.4435 C 12.2473 22.2803 12.2099 22.0972 12.2231 21.9141 C 12.2364 21.7311 12.2997 21.5552 12.4063 21.4058 L 12.758 20.9173 C 12.9076 20.7108 13.0768 20.519 13.2631 20.3448 C 11.5494 19.8944 8.57346 18.3488 8.57346 16.4934 L 8.56076 13.9952"/>
          </g>
          <g transform="matrix(1 0 0 1 3.05 3.98)">
            <path d="M 16.8282 16.4641 L 15.5581 17.2614 C 15.3913 17.3659 15.2056 17.4366 15.0115 17.4694 C 14.8173 17.5022 14.6187 17.4964 14.4268 17.4524 C 14.2349 17.4084 14.0536 17.327 13.8931 17.213 C 13.7327 17.0989 13.5963 16.9543 13.4917 16.7875 C 13.3872 16.6207 13.3165 16.435 13.2837 16.2409 C 13.2509 16.0467 13.2567 15.8481 13.3007 15.6562 C 13.3447 15.4643 13.4261 15.283 13.5402 15.1225 C 13.6542 14.9621 13.7988 14.8257 13.9656 14.7211 L 14.3564 14.4779"/>
          </g>
        </g>
      </g>
    </svg>
  </div>
  <div class="offline-title">You're Offline</div>
  <div class="offline-message">The Digital Gate can't be reached. Check your connection and try again.</div>
  <button class="offline-btn" onclick="location.reload()">Retry</button>
</body>
</html>
```

**Step 2: Open the file in a browser to visually verify**

Open `www/offline.html` directly in a browser. Expected: dark gradient background with grid lines, Agumon icon with pulsing rings, "You're Offline" title in white, cyan message text, styled "Retry" button. Should match the disconnect overlay aesthetic.

**Step 3: Commit**

```bash
git add www/offline.html
git commit -m "feat(pwa): add offline fallback page with Agumon"
```

---

### Task 4: Create the Service Worker

**Files:**
- Create: `www/sw.js`

**Context:** The service worker ONLY handles offline fallback for navigation requests. It does NOT cache CSS, JS, images, or interfere with Shiny's WebSocket connection. When a navigation request fails (user is offline), it serves the cached `offline.html`. All other requests (WebSocket, XHR, asset loads) pass through untouched.

**Step 1: Create the service worker**

Create `www/sw.js`:

```javascript
// DigiLab PWA Service Worker
// Purpose: Serve offline fallback page when network is unavailable.
// Does NOT cache app resources — Shiny requires a live WebSocket connection.

const CACHE_NAME = 'digilab-offline-v1';
const OFFLINE_URL = 'offline.html';

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll([OFFLINE_URL, 'agumon.svg']))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request).catch(() => caches.match(OFFLINE_URL))
    );
  }
});
```

**Step 2: Commit**

```bash
git add www/sw.js
git commit -m "feat(pwa): add offline-only service worker"
```

---

### Task 5: Add PWA Head Tags to app.R

**Files:**
- Modify: `app.R:407-423` (inside `tags$head()`)

**Context:** The `tags$head()` block starts at line 407 in `app.R`. We need to add the PWA manifest link, theme color, favicon, Apple touch icon, iOS standalone mode meta tags, and service worker registration script. Insert these AFTER the existing meta description tag (line 423) and BEFORE the Google Analytics script (line 424).

**Step 1: Add PWA tags to `tags$head()`**

In `app.R`, find this block (lines 422-424):

```r
    # Standard meta description
    tags$meta(name = "description", content = "Track your local Digimon TCG tournament results, player standings, deck meta, and store events."),
    # Google Analytics
```

Insert the following between the meta description and Google Analytics comment:

```r
    # Standard meta description
    tags$meta(name = "description", content = "Track your local Digimon TCG tournament results, player standings, deck meta, and store events."),
    # PWA manifest and theme
    tags$link(rel = "manifest", href = "manifest.json"),
    tags$meta(name = "theme-color", content = "#1a1a2e"),
    # Favicon and app icons
    tags$link(rel = "icon", type = "image/x-icon", href = "favicon.ico"),
    tags$link(rel = "apple-touch-icon", href = "icons/icon-192.png"),
    # iOS standalone mode
    tags$meta(name = "apple-mobile-web-app-capable", content = "yes"),
    tags$meta(name = "apple-mobile-web-app-status-bar-style", content = "black-translucent"),
    # Google Analytics
```

**Step 2: Add service worker registration script**

In `app.R`, find the `tags$script(src = "pill-toggle.js"),` line (line 445). Add the service worker registration AFTER the pill-toggle script and BEFORE the inline JavaScript:

```r
    # Pill toggle segmented controls
    tags$script(src = "pill-toggle.js"),
    # PWA service worker registration
    tags$script(HTML("if('serviceWorker' in navigator){navigator.serviceWorker.register('sw.js');}")),
    # JavaScript to handle active nav state and loading screen
```

**Step 3: Verify syntax**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse(file='app.R'); cat('OK\n')"
```

Expected: `OK`

**Step 4: Commit**

```bash
git add app.R
git commit -m "feat(pwa): add manifest, icons, and service worker registration to head"
```

---

### Task 6: Test and Verify PWA

**Files:**
- No file changes — verification only

**Step 1: Verify all PWA files exist**

```bash
ls www/manifest.json www/sw.js www/offline.html www/favicon.ico www/icons/
```

Expected: all files present. `www/icons/` should contain 4 PNG files.

**Step 2: Validate manifest JSON**

```bash
python -c "import json; m=json.load(open('www/manifest.json')); print(f'Name: {m[\"name\"]}'); print(f'Icons: {len(m[\"icons\"])}')"
```

Expected: `Name: DigiLab - Digimon TCG Locals Tracker` and `Icons: 4`

**Step 3: Verify app.R syntax**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse(file='app.R'); cat('OK\n')"
```

Expected: `OK`

**Step 4: Manual testing checklist**

Run `shiny::runApp()` and verify:
- [ ] No console errors on page load
- [ ] Favicon appears in browser tab
- [ ] DevTools → Application → Manifest shows parsed manifest with icons
- [ ] DevTools → Application → Service Workers shows `sw.js` registered
- [ ] Open `www/offline.html` directly — Agumon offline page renders correctly
- [ ] (Optional) DevTools → Network → Offline checkbox → Reload → Should show offline page

**Step 5: Final commit if any adjustments needed**

```bash
git add -A
git commit -m "fix(pwa): adjustments from manual testing"
```

Only commit this if Step 4 surfaced issues that required fixes.
