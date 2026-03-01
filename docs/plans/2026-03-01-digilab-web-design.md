# DigiLab Website Design

**Date:** 2026-03-01
**Status:** Approved
**Author:** Michael Lopez

## Overview

Design for a standalone DigiLab website to serve as a landing page, blog, and public roadmap. Part of a broader multi-repo architecture separating the main Shiny app from marketing/content properties.

## Goals

1. **Brand presence** — Professional front door for DigiLab
2. **Content home** — Blog posts, technical deep-dives, meta analysis articles
3. **Transparency** — Public roadmap showing what's coming
4. **Portfolio** — Showcase data science work and methodology
5. **Future-proof** — Structure that scales to multiple games/tools

## Repository Structure

```
lopezmichael/digilab-app          → Main Shiny app (renamed from digimon-tcg-standings)
                                    Deploys to: app.digilab.cards (Posit Connect)

lopezmichael/digilab-web          → Landing page, blog, roadmap
                                    Deploys to: digilab.cards (Vercel)

lopezmichael/digilab-insights     → Meta insights Shiny app (future)
                                    Deploys to: insights.digilab.cards (Posit Connect)
```

### Domain Setup

| Subdomain | Property | Host |
|-----------|----------|------|
| `digilab.cards` | Website (landing, blog, roadmap) | Vercel |
| `app.digilab.cards` | Main tracker app | Posit Connect (iframe or direct) |
| `insights.digilab.cards` | Meta insights app (future) | Posit Connect |

### Repo Rename

The current `digimon-tcg-standings` repo will be renamed to `digilab-app` to match the new structure. This is a separate task from the website build.

## Tech Stack

| Component | Technology | Reason |
|-----------|------------|--------|
| Framework | Astro | Fast static output, MDX support, component islands |
| Hosting | Vercel | Preview deploys, zero-config, great DX |
| Styling | CSS (tokens.css) | Shared design tokens from app |
| Blog | Astro Content Collections | Built-in MDX support, frontmatter validation |
| Charts | Embedded HTML widgets | Export from R via `htmlwidgets::saveWidget()` |

## Site Structure

```
digilab-web/
├── src/
│   ├── pages/
│   │   ├── index.astro              → Landing page
│   │   ├── blog/
│   │   │   ├── index.astro          → Blog listing
│   │   │   └── [slug].astro         → Individual posts
│   │   ├── roadmap.astro            → Public roadmap
│   │   └── about.astro              → About DigiLab
│   ├── content/
│   │   └── blog/
│   │       ├── rating-redesign.mdx  → First post
│   │       └── how-ocr-works.mdx    → Future post
│   ├── components/
│   │   ├── Header.astro
│   │   ├── Footer.astro
│   │   └── ChartEmbed.astro         → For highcharter iframes
│   └── styles/
│       └── tokens.css               → Design tokens
├── public/
│   ├── charts/                      → Exported highcharter widgets
│   ├── images/
│   ├── brand/
│   │   ├── agumon.svg
│   │   └── digivice.svg
│   └── favicon.svg
├── astro.config.mjs
└── package.json
```

## Landing Page

```
┌─────────────────────────────────────────────────────────────┐
│  [Logo] DigiLab              Blog | Roadmap | About  [App →]│
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                    HERO SECTION                             │
│     "Track Your Local Digimon TCG Scene"                    │
│     Subtitle: Player ratings, deck meta, tournament         │
│     history — all in one place.                             │
│                                                             │
│     [Go to App]   [Learn More ↓]                            │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                  FEATURES (3-4 cards)                       │
│   [Player Rankings]  [Deck Meta]  [Store Directory]         │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                 LATEST FROM THE BLOG                        │
│   [Card 1]          [Card 2]          [Card 3]              │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                   ACTIVE SCENES                             │
│   "Live in 5 regions across the US and growing"             │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                      FOOTER                                 │
│   Discord | GitHub | Ko-fi | Contact                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Design notes:**
- Agumon mascot in hero or features section
- Dark/light mode toggle (match app's theme support)
- Mobile-responsive (stacks vertically)
- Use `frontend-design` skill during implementation for polished UI

## Content Types

Five blog categories:

| Category | Tag | Purpose | Examples |
|----------|-----|---------|----------|
| **Announcements** | `announcement` | Updates, new features, changes | "Rating System v2.0", "New Scene: Houston" |
| **Technical** | `technical` | How things work, methodology | "How the OCR Works", "Building Elo for TCGs" |
| **Analysis** | `analysis` | Data deep-dives, meta reports | "BT-18 Meta Shift", "Banlist Impact Report" |
| **Spotlight** | `spotlight` | Community features, profiles | "Store Spotlight: Sci-Fi Factory" |
| **Dev Log** | `devlog` | Building DigiLab, journey | "Why I Built DigiLab", "Lessons from 1 Year" |

### Blog Post Frontmatter

```mdx
---
title: "Rating System v2.0 - What Changed and Why"
description: "We redesigned how ratings work. Here's the full breakdown."
date: 2026-03-01
category: announcement
tags: [ratings, methodology]
author: Michael Lopez
image: /images/blog/rating-redesign-cover.png
---
```

### Embedding Charts

Workflow for blog posts with data visualizations:

1. Write analysis in R (script or Quarto for personal workflow)
2. Create highcharter charts
3. Export: `htmlwidgets::saveWidget(chart, "chart-name.html", selfcontained = TRUE)`
4. Copy to `public/charts/`
5. Write blog post in MDX
6. Embed: `<ChartEmbed src="/charts/chart-name.html" height="400px" />`

## Roadmap Page

Public transparency on what's coming, what's done.

```
┌─────────────────────────────────────────────────────────────┐
│                      PUBLIC ROADMAP                          │
│  "See what we're working on and what's coming next"         │
├─────────────────────────────────────────────────────────────┤
│  Filter: [All] [In Progress] [Planned] [Completed] [Ideas]  │
├─────────────────────────────────────────────────────────────┤
│  🚧 IN PROGRESS                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Rating System Redesign                              │    │
│  │ Single-pass chronological Elo calculation           │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  📋 PLANNED                                                  │
│  ...                                                        │
│                                                             │
│  ✅ COMPLETED                                                │
│  ...                                                        │
└─────────────────────────────────────────────────────────────┘
```

### Roadmap Data Source

**Approach:** GitHub Action sync from app repo

```
digilab-app (source)
└── ROADMAP.md              ← Edit here during development

     ↓ GitHub Action on push

digilab-web (destination)
└── src/content/roadmap.md  ← Auto-synced copy
```

The website build parses the markdown and renders as filterable cards. Format transformation (if needed) handled during implementation.

## Unified Branding

### Design Tokens

Source of truth: `_brand.yml` in app repo

Shared via `tokens.css`:

```css
:root {
  /* Colors */
  --color-primary: #0A3055;
  --color-accent: #F7941D;
  --color-background: #f8f9fa;
  --color-background-dark: #1a1a2e;
  --color-text: #212529;
  --color-text-dark: #e9ecef;

  /* Typography */
  --font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
  --font-size-base: 16px;

  /* Spacing */
  --space-xs: 4px;
  --space-sm: 8px;
  --space-md: 16px;
  --space-lg: 24px;
  --space-xl: 32px;
}
```

### Mascot Assets

Source: `docs/digimon-mascots.md` in app repo

Current assets:
- `agumon.svg` — Primary mascot (line art, `currentColor` strokes)
- `digivice.svg` — Logo icon

Future: Commission custom SVG set with multiple characters and moods. See mascot specs doc for full wishlist and art style guidelines.

### Asset Sharing

```
digilab-app/
└── _brand.yml                    ← Color/typography source
└── docs/digimon-mascots.md       ← Mascot specs & commission wishlist
└── www/
    ├── agumon.svg
    └── digivice.svg

digilab-web/
└── src/styles/tokens.css         ← CSS variables from _brand.yml
└── public/brand/
    ├── agumon.svg                ← Copied assets
    └── digivice.svg
```

## Cross-Property Navigation

### User Flow

```
                    digilab.cards (website)
                    ┌─────────────────────┐
                    │   Landing Page      │
                    │   Blog              │
                    │   Roadmap           │
                    └─────────┬───────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
    app.digilab.cards   insights.digilab.cards   (future)
```

### Cross-Linking

| From | To | Link Location |
|------|-----|---------------|
| Website | App | "Go to App" button (header, hero, footer) |
| Website | Insights | "Explore Meta" button (when built) |
| App | Website | Footer links: "Blog", "Roadmap" |
| Blog posts | App | Deep links to specific views |

## Analytics

### GA4 Setup

Same property across all DigiLab properties for unified analytics:

| Property | GA4 Property ID | Notes |
|----------|-----------------|-------|
| Website | `G-NJ3SMG8HGG` | Landing, blog, roadmap pageviews |
| App | `G-NJ3SMG8HGG` | Tab visits, modal opens, scene changes (existing) |
| Insights | `G-NJ3SMG8HGG` | Report views, filter usage (future) |

### Cross-Domain Tracking

```javascript
gtag('config', 'G-NJ3SMG8HGG', {
  cookie_domain: '.digilab.cards',
  linker: {
    domains: ['digilab.cards', 'app.digilab.cards', 'insights.digilab.cards']
  }
});
```

### Website Events

| Event | Trigger |
|-------|---------|
| `page_view` | All pages (automatic) |
| `blog_read` | Blog post opened |
| `roadmap_filter` | Roadmap filter changed |
| `cta_click` | "Go to App" button clicked |
| `chart_interact` | Embedded highcharter widget interaction |

## Implementation Notes

### First Blog Post

The rating system redesign report (`docs/plans/2026-03-01-rating-redesign-report.md`) will be adapted as the first blog post. Key content:
- Why we changed the rating system
- What changed (technical summary, accessible)
- How it affects players
- Visualizations (histograms from `scripts/analysis/snapshots/`)
- FAQ

### Future: Multi-Game Expansion

This structure supports future expansion to other TCGs:

```
cardtools.dev (umbrella, future)
├── digilab.cards (Digimon)
├── [onepiece-name].cards (One Piece, future)
└── [gundam-name].cards (Gundam, future)
```

Each game gets its own branded ecosystem (app, website, Discord). The umbrella site links them together under a generic brand.

## Next Steps

1. [ ] Create `digilab-web` repo
2. [ ] Set up Astro project with Vercel deployment
3. [ ] Implement landing page (use `frontend-design` skill)
4. [ ] Create blog structure with first post (rating redesign)
5. [ ] Build roadmap page with filtering
6. [ ] Configure DNS for `digilab.cards` → Vercel
7. [ ] Set up GitHub Action to sync ROADMAP.md
8. [ ] Add cross-links between website and app
9. [ ] (Separate) Rename `digimon-tcg-standings` → `digilab-app`

## References

- Rating redesign analysis: `docs/plans/2026-03-01-rating-redesign-report.md`
- Mascot specs: `docs/digimon-mascots.md`
- Current app brand: `_brand.yml`
- Deep linking design: `docs/plans/2026-02-04-deep-linking-design.md`
