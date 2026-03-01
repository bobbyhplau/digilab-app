# DigiLab Web - Claude Code Context

This document provides context for Claude Code to quickly understand and contribute to this project.

## Project Overview

Marketing website and content hub for DigiLab — a Digimon TCG tournament tracking platform. Includes landing page, blog, and public roadmap.

**Live Site:** https://digilab.cards/
**Main App:** https://app.digilab.cards/

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Astro |
| Hosting | Vercel |
| Styling | CSS with design tokens |
| Blog | Astro Content Collections (MDX) |
| Charts | Embedded HTML widgets (from R/highcharter) |

## Project Structure

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
│   │   └── blog/                    → MDX blog posts
│   ├── components/
│   │   ├── Header.astro
│   │   ├── Footer.astro
│   │   └── ChartEmbed.astro         → For highcharter iframes
│   ├── layouts/
│   │   └── BaseLayout.astro         → Shared page wrapper
│   └── styles/
│       └── tokens.css               → Design tokens from brand
├── public/
│   ├── charts/                      → Exported highcharter widgets
│   ├── images/
│   ├── brand/
│   │   ├── agumon.svg
│   │   └── digivice.svg
│   └── favicon.svg
├── astro.config.mjs
├── package.json
└── vercel.json
```

## Related Repositories

| Repo | Purpose | URL |
|------|---------|-----|
| digilab-app | Main Shiny tracker app | https://github.com/lopezmichael/digilab-app |
| digilab-insights | Meta insights app (future) | TBD |

## Design System

### Colors

```css
--color-primary: #0A3055;      /* Deep blue */
--color-accent: #F7941D;       /* DigiLab orange */
--color-background: #f8f9fa;   /* Light mode bg */
--color-background-dark: #1a1a2e; /* Dark mode bg */
```

### Typography

- Font: Inter (with system fallbacks)
- Base size: 16px

### Mascot

- Primary: Agumon (line art SVG, uses `currentColor`)
- Logo: Digivice icon
- Future: Custom commissioned art (see digilab-app/docs/digimon-mascots.md)

## Content Types

Blog posts use these categories:

| Category | Tag | Purpose |
|----------|-----|---------|
| Announcements | `announcement` | Updates, new features |
| Technical | `technical` | How things work |
| Analysis | `analysis` | Data deep-dives |
| Spotlight | `spotlight` | Community features |
| Dev Log | `devlog` | Building DigiLab |

### Blog Post Frontmatter

```mdx
---
title: "Post Title"
description: "Brief description for cards and SEO"
date: 2026-03-01
category: announcement
tags: [ratings, methodology]
author: Michael Lopez
image: /images/blog/cover.png
---
```

## Embedding Charts

For blog posts with R/highcharter visualizations:

1. Create chart in R
2. Export: `htmlwidgets::saveWidget(chart, "name.html", selfcontained = TRUE)`
3. Copy to `public/charts/`
4. In MDX: `<ChartEmbed src="/charts/name.html" height="400px" />`

## Roadmap Sync

The roadmap page pulls from `digilab-app/ROADMAP.md` via GitHub Action:
- Source: `digilab-app/ROADMAP.md`
- Destination: `src/content/roadmap.md`
- Trigger: Push to ROADMAP.md in app repo

## Development

### Local Development

```bash
npm install
npm run dev
```

### Build

```bash
npm run build
npm run preview
```

### Deploy

Push to `main` branch → Vercel auto-deploys

## Analytics

GA4 Property: `G-NJ3SMG8HGG` (shared with app)

Cross-domain tracking enabled for:
- digilab.cards
- app.digilab.cards
- insights.digilab.cards

## Required Workflows

### Superpowers

| Superpower | When to Use |
|------------|-------------|
| `frontend-design` | Building new pages/components |
| `verification-before-completion` | Before claiming work is complete |

### Git Workflow

- Feature branches for new pages/major changes
- Direct to main OK for content updates (blog posts)
- Vercel preview deploys on PRs

## Links

- Design doc: See `digilab-app/docs/plans/2026-03-01-digilab-web-design.md`
- Brand assets: `digilab-app/_brand.yml`, `digilab-app/docs/digimon-mascots.md`
- Main app repo: https://github.com/lopezmichael/digilab-app
