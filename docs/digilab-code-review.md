# DigiLab Code Review: Mobile Navigation, Admin Pages & CSS

## Overall Verdict

Your mobile implementation is **significantly better than most Shiny apps I've seen**. You've done a lot of things right — the hidden sidebar / bottom tab bar pattern, per-table column hiding via `data-col-id`, responsive `breakpoints()` on admin layouts, and a clean PWA setup with offline page and service worker. This is not a "start over" situation. What follows are refinements, not rewrites.

---

## 1. Mobile Tab Bar — What's Working & What to Improve

### What you nailed
- Hiding the sidebar entirely on mobile (`display: none !important`) rather than leaving the hamburger is the right call for a consumer app
- Bottom tab bar with `actionLink` → `observeEvent` → `nav_select` is clean Shiny architecture
- The `updateSidebarNav` custom message handler keeps sidebar and tab bar in sync — smart
- 44px min touch targets on `.tab-bar-item` ✓
- Active state highlighting with the amber `#FBBF24` ✓
- Footer gets `padding-bottom: 70px` to avoid being hidden ✓

### Issues to address

**1.1 — Active state JS bug on `#mob_dashboard`**

In your JS (app.R ~line 541):
```javascript
$('#mob_dashboard .tab-bar-item').addClass('active');
```
This targets `#mob_dashboard .tab-bar-item` — but `#mob_dashboard` is the `actionLink` wrapper, and `.tab-bar-item` is its child `div`. The click handler at line 471 does:
```javascript
$('.tab-bar-item').removeClass('active');
$(this).addClass('active');
```
`$(this)` here is the `.tab-bar-item` div, not the `actionLink`. But in the `updateSidebarNav` handler (line 492–495):
```javascript
$('#' + tabId + ' .tab-bar-item').addClass('active');
```
This correctly traverses from the link to the div. So the initial set works, but clicking directly on the tab bar item might have `$(this)` be the inner div vs the link depending on event bubbling. This seems to work in practice, but it's fragile — if Bootstrap or Shiny changes the event delegation, it could break.

**Suggestion:** Add a data attribute to simplify targeting:
```javascript
$(document).on('click', '.tab-bar-item', function() {
  $('.tab-bar-item').removeClass('active');
  $(this).closest('.tab-bar-item').addClass('active');
});
```

**1.2 — No `safe-area-inset-bottom` on the tab bar**

Your CSS at line 6525 doesn't include safe area padding. On iPhone X+ in standalone PWA mode, the bottom tab bar will overlap the home indicator bar:

```css
.mobile-tab-bar {
  /* add this */
  padding-bottom: env(safe-area-inset-bottom);
  height: calc(auto + env(safe-area-inset-bottom));
}
```

And your content padding at line 4144 should account for it too:
```css
.bslib-sidebar-layout > :not(.sidebar):not(.collapse-toggle) {
  padding-bottom: calc(70px + env(safe-area-inset-bottom)) !important;
}
```

**1.3 — No admin tabs on mobile bar**

When an admin is logged in, they can't reach admin pages from mobile at all — the sidebar is hidden and the bottom bar only has public tabs. This is probably fine for now (admins likely use desktop), but worth considering adding an "Admin" overflow menu item on the tab bar when `output.is_admin` is true. Even a simple "More" tab that shows a modal with admin nav links would work.

**1.4 — Missing `viewport-fit=cover` meta tag**

You have `apple-mobile-web-app-status-bar-style: black-translucent` but no `viewport-fit=cover` in a viewport meta tag. Shiny/bslib injects a default viewport tag, but without `viewport-fit=cover`, the safe area insets won't work properly. Add:

```r
tags$meta(name = "viewport", 
          content = "width=device-width, initial-scale=1, viewport-fit=cover")
```

**1.5 — Missing `apple-mobile-web-app-title`**

You have `apple-mobile-web-app-capable` and the status bar style, but not the title. Without this, iOS will use the `<title>` tag which may be longer. Add:

```r
tags$meta(name = "apple-mobile-web-app-title", content = "DigiLab")
```

---

## 2. Admin Pages Review

### What's working well
- Consistent `layout_columns(col_widths = breakpoints(sm = c(12, 12), md = c(5, 7)))` pattern across all admin UIs — this is textbook responsive layout
- The wizard step pattern on Enter Results is clean
- Hidden ID fields with `tags$script` to hide the parent is a pragmatic Shiny workaround
- `conditionalPanel` for admin/superadmin sections is the right approach
- The stores schedule form uses appropriate `breakpoints(sm = c(6, 6, 6, 6), md = c(4, 3, 3, 2))` — four items stacking to 2x2 on mobile is correct

### Issues to address

**2.1 — Upload Results page has non-responsive `col_widths`**

In `submit-ui.R`, four `layout_columns` calls use fixed widths instead of breakpoints:
```r
# Line 67 - will stay side-by-side even on tiny screens
col_widths = c(6, 6)

# Line 78 - 4-column layout will be cramped on mobile
col_widths = c(4, 4, 2, 2)
```

The `c(4, 4, 2, 2)` layout (Event Type, Format, Players, Rounds) will be especially problematic — those numeric inputs will be ~80px wide on a 375px phone. Fix:

```r
# Line 67
col_widths = breakpoints(sm = c(12, 12), md = c(6, 6))

# Line 78 - stack to 2x2 on mobile
col_widths = breakpoints(sm = c(6, 6, 6, 6), md = c(4, 4, 2, 2))
```

This is your most important mobile admin fix since Upload Results is a **public-facing** page (not admin-only) and the most likely page to be used on mobile at a tournament.

**2.2 — Admin grid table on mobile**

The Enter Results grid (admin_grid.R) is likely the hardest mobile challenge. A data-entry grid with Player, Points/W-L-T, Deck Archetype columns needs horizontal scrolling or a different mobile layout entirely. Your CSS at line 4243 handles some of this, but the grid itself — because it uses `textInput`/`selectInput` inside each row — generates very wide content.

Consider: for mobile admin use, is the "Paste from Spreadsheet" flow a better path? You could detect mobile via `session$clientData$output_width` or JS and nudge mobile admins toward the paste workflow instead of the interactive grid.

**2.3 — Store schedule form `padding-top: 32px` hardcode**

In `admin-stores-ui.R` line 134:
```r
div(
  style = "padding-top: 32px;",
  actionButton("add_schedule", "Add", ...)
)
```
This hardcoded top padding aligns the "Add" button with the input labels, but it breaks when inputs stack on mobile (the label isn't beside it anymore). Use a Bootstrap utility class instead:
```r
div(
  class = "d-flex align-items-end h-100",
  actionButton("add_schedule", "Add", ...)
)
```

---

## 3. CSS Review

### Organization — Good

Your 7,058-line CSS file is well-organized with clear section headers. The section structure is logical (header → sidebar → content → components → mobile → loading → empty states). This is significantly better than most Shiny apps where CSS accumulates randomly.

### Critical Issues

**3.1 — 369 `!important` declarations**

This is the biggest CSS hygiene concern. Many are necessary because Shiny/bslib generates high-specificity selectors and you need to override them — that's just the reality of Shiny CSS. But some are fighting your own rules rather than framework rules. A few to audit:

```css
/* These fight each other — line 632 vs line 654 */
.bslib-sidebar-layout > :not(.sidebar) {
  padding-top: 0.5rem !important;
  padding-right: 1rem !important;
}

@media (max-width: 576px) {
  .bslib-sidebar-layout > :not(.sidebar) {
    padding: 0.25rem 0.5rem !important;
    padding-top: 0 !important;  /* overrides the !important above */
  }
}
```

When you have `!important` overriding `!important`, it means you're relying on source order for cascade resolution. This works but is fragile. Consider consolidating these into a single rule with the media query:

```css
.bslib-sidebar-layout > :not(.sidebar) {
  padding-top: 0.5rem !important;
  padding-right: 1rem !important;
}

@media (max-width: 576px) {
  .bslib-sidebar-layout > :not(.sidebar):not(.collapse-toggle) {
    padding: 0 0.5rem !important; /* single rule, no double-override */
  }
}
```

**3.2 — Scattered media queries**

You have 39 `@media` blocks spread throughout the file. Many target the same breakpoint (`max-width: 768px`) but are in different sections. This means if you need to change how something works on mobile, you're editing in 15+ places.

This isn't necessarily wrong — it keeps related component styles together — but it does make it harder to understand the total mobile behavior. Consider adding a comment at the top of the file listing which lines contain mobile overrides, e.g.:

```css
/* MOBILE OVERRIDE INDEX:
 * 319: Header mobile
 * 638: Content padding mobile
 * 952: Dashboard charts mobile
 * 4126-4297: Main mobile UI section
 * 6523: Mobile tab bar
 */
```

**3.3 — iOS form zoom bug**

You do NOT have `font-size: 16px` set on `form-control`, `form-select`, or `selectize-input` for mobile. This is your highest-priority CSS fix. iOS Safari auto-zooms the viewport when users tap any input with font-size below 16px, and it doesn't zoom back. Every selectize dropdown tap will trigger this.

```css
@media (max-width: 768px) {
  .form-control,
  .form-select,
  select,
  .selectize-input,
  .selectize-input input {
    font-size: 16px !important;
  }
}
```

This single rule will fix the most annoying mobile Shiny behavior.

**3.4 — `scrollbar-color` on `*` selector**

Lines 51-53:
```css
* {
  scrollbar-width: thin;
  scrollbar-color: rgba(0, 200, 255, 0.5) rgba(15, 76, 129, 0.1);
}
```

The `*` selector applies to every single element. This is a very broad stroke for a cosmetic feature. Consider scoping to `body` or `.main-content`:

```css
body {
  scrollbar-width: thin;
  scrollbar-color: rgba(0, 200, 255, 0.5) rgba(15, 76, 129, 0.1);
}
```

Firefox inherits `scrollbar-color` from parent elements, so setting it on `body` works for all scrollable children.

**3.5 — Dark mode mobile tab bar**

Your mobile tab bar at line 6532 uses:
```css
background: linear-gradient(135deg, #0A3055 0%, #0F4C81 100%);
```

But there's no `[data-bs-theme="dark"]` variant. When a user switches to dark mode, the tab bar stays the same light-mode blue while the rest of the app changes. Add:

```css
[data-bs-theme="dark"] .mobile-tab-bar {
  background: linear-gradient(135deg, #1A202C 0%, #2D3748 100%);
  border-top-color: rgba(255, 255, 255, 0.1);
}
```

### Minor CSS notes

- **Line 378**: `.bslib-sidebar-layout > :not(.sidebar)` inside a media query at 768px — the `:not(.sidebar)` selector also matches `.collapse-toggle`. You handle this elsewhere, but it's worth adding `:not(.collapse-toggle)` for clarity.

- **Value box titles at 0.65rem** (line 4155): This is 10.4px at default root font size. That's quite small and may fail WCAG contrast/readability on some devices. Consider `0.7rem` minimum.

- **Table font at 0.8rem** (line 4206): Similarly, 12.8px is tight. On a 375px screen with dense table data, this is borderline. Test on actual devices.

---

## 4. PWA / Manifest

Your manifest and service worker are solid. A few additions that would improve the PWA audit score:

**4.1 — Add more icon sizes**

You only have 192 and 512. For broader device support, add 48, 72, 96, 128, 144, 152, 384. Your `scripts/generate_pwa_icons.py` can handle this — you already have the tooling.

**4.2 — Add `categories` and `orientation` to manifest**

```json
{
  "categories": ["games", "entertainment"],
  "orientation": "portrait"
}
```

**4.3 — The root manifest.json (425KB!)**

You have TWO manifest files: `manifest.json` at root (425KB — that's suspiciously large, likely a different kind of manifest) and `www/manifest.json` (the actual PWA manifest at 1KB). Make sure the `<link rel="manifest">` points to the right one. Your app.R links to `manifest.json` which in a Shiny app served from `www/` should resolve correctly, but verify this in the deployed version.

---

## 5. Priority Fix List

Ranked by impact and effort:

| Priority | Fix | Effort | Impact |
|----------|-----|--------|--------|
| 1 | iOS form zoom: add `font-size: 16px` to mobile inputs | 5 min | High — fixes the #1 mobile Shiny annoyance |
| 2 | Upload Results responsive columns (`submit-ui.R`) | 10 min | High — public page used at tournaments |
| 3 | Safe area insets on tab bar + viewport-fit | 15 min | Medium — fixes iPhone X+ PWA appearance |
| 4 | Dark mode tab bar variant | 5 min | Low — cosmetic but noticeable |
| 5 | `apple-mobile-web-app-title` meta tag | 2 min | Low — polish |
| 6 | Store form `padding-top: 32px` → flexbox alignment | 5 min | Low — admin-only |
| 7 | Additional PWA icon sizes | 15 min | Low — broader device coverage |
| 8 | Mobile admin access (More tab or modal) | 1 hr | Medium — only if admins use mobile |
| 9 | CSS `*` scrollbar selector → `body` | 2 min | Low — minor perf |
| 10 | CSS media query index comment | 10 min | Low — maintainability |
