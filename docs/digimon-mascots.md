# Digimon Mascot SVGs - Asset Tracking

This document tracks all Digimon SVG mascot assets used throughout DigiLab, their locations, states/moods, and plans for future commissioned artwork.

## Current Assets

| Asset | Source | File | License |
|-------|--------|------|---------|
| Digivice | [copyicon.com](https://copyicon.com/icons?keyword=digimon) | `www/digivice.svg` | copyicon.com free icons |
| Agumon | [copyicon.com](https://copyicon.com/icons?keyword=digimon) | `www/agumon.svg` | copyicon.com free icons |

Both are line-art style SVGs (stroke only, no fill). They use `currentColor` for stroke in the reference files; inline usages may override the color.

## Current Placements

| Location | Asset | Mood/State | Color | File | Notes |
|----------|-------|-----------|-------|------|-------|
| Header navbar icon | Digivice | Static | `currentColor` (white) | `app.R` ~line 494 | 26x26, glows with header animation |
| Loading screen | Agumon | Jumping (bounce) | `#F7941D` (orange) | `app.R` ~line 371 | 64x64, squash-and-stretch keyframe |
| Onboarding modal (step 1) | Agumon | Hero unit | `#F7941D` (orange) | `views/onboarding-modal-ui.R` | 72x72, side-by-side with app name, via `agumon_svg()` |
| About page hero | Agumon | Walking (animated) | `#F7941D` (orange) | `views/about-ui.R` | 64x64, 8s walk cycle R→L→R with dust, via `agumon_svg()` |
| Empty states (7 sites) | Agumon | Waiting | `#F7941D` (orange) | Various `server/public-*-server.R` | 56x56, via `digital_empty_state(mascot="agumon")` |

### `agumon_svg()` Helper (v0.27+)

Defined in `app.R`. Returns inline SVG HTML with `currentColor` support:
```r
agumon_svg(size = "48px", color = "#F7941D")
```

### `digital_empty_state()` Mascot Parameter (v0.27+)

The `digital_empty_state()` helper now accepts an optional `mascot` parameter:
```r
digital_empty_state("No data", "// waiting", "inbox", mascot = "agumon")
```
When `mascot = "agumon"`, the bsicons icon is replaced with the Agumon SVG.

## Planned Placements

| Location | Asset | Mood/State | Priority | Roadmap ID |
|----------|-------|-----------|----------|------------|
| Error/offline state | Agumon | Sweat drop / worried | Low | DM3 |
| Footer watermark | Digivice | Static (subtle) | Low | DM6 |
| 404 / not found | Agumon | Lost/searching | Low | DM7 |
| Achievement unlocked | Agumon | Celebrating | Future | DM8 |

## Future: Commissioned Custom SVGs

When commissioning a custom artist, here's the full wishlist of Digimon characters and states:

### Characters to Commission

| Character | Where | Mood/Pose | Notes |
|-----------|-------|-----------|-------|
| **Agumon** | Throughout (see above) | Multiple moods: happy, confused, celebrating, worried, waving, sitting, sleeping | Primary mascot - needs ~6 mood variants |
| **Gabumon** | Player vs Player / head-to-head | Friendly rival | Pair with Agumon for versus screens |
| **Koromon** | New user / onboarding | Cute/welcoming | Baby stage = new users |
| **Greymon** | Top-ranked player badge | Powerful/confident | Evolution = achievement |
| **MetalGreymon** | Leaderboard champion | Dominant | Higher evolution = higher rank |
| **WarGreymon** | #1 player / season winner | Ultimate form | Reserved for the best |
| **Tentomon** | Loading states (alternate) | Busy/working | Tech-themed Digimon for data processing |
| **Palmon** | Store/community pages | Friendly/community | Nature = growth, community |
| **Patamon** | Help/FAQ pages | Helpful/guiding | Angel theme = guiding light |
| **Gatomon** | Error states (alternate) | Sassy/unimpressed | Cat attitude for errors |

### Art Style Guidelines

- **Style:** Clean line art (stroke-based, no fill) to match current Digivice/Agumon aesthetic
- **Format:** SVG with `currentColor` strokes for easy theming
- **Sizes:** Design at 24x24 viewBox, should look good from 16px to 128px
- **Moods:** Each character needs 2-4 mood variants minimum
- **Colors:** Should work on both light and dark backgrounds (use `currentColor` or provide both variants)
- **Consistency:** All characters should feel like they belong to the same set

### Integration Pattern

SVGs are stored in `www/` as reference files and inlined in R code where needed:
- **Header/navbar:** Inline in `app.R` with `HTML('...')`, uses `currentColor` for theme integration
- **Loading screen:** Inline in JS string in `app.R`, uses explicit hex color (e.g., `#F7941D`)
- **Dynamic UI:** Inline in `renderUI()` server functions, can use `currentColor` or explicit colors
- **Static pages:** Can reference `www/asset.svg` directly via `<img>` tags (but loses `currentColor`)

For `currentColor` to work, the SVG must be inlined (not referenced as `<img src>`). This is the preferred approach for interactive/themed elements.
