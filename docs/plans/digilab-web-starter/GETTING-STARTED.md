# Getting Started - DigiLab Web Setup

Step-by-step guide to set up the digilab-web repository.

## Prerequisites

- Node.js 18+ installed
- Vercel account (free tier works)
- GitHub account
- Access to digilab.cards DNS (for domain setup)

## Step 1: Create the Repository

```bash
# On GitHub: Create new repo "digilab-web" (empty, no README)

# Locally:
mkdir digilab-web
cd digilab-web
git init
git remote add origin https://github.com/lopezmichael/digilab-web.git
```

## Step 2: Initialize Astro Project

```bash
# Create Astro project
npm create astro@latest . -- --template basics --typescript strict

# Install additional dependencies
npm install @astrojs/mdx @astrojs/sitemap
```

## Step 3: Configure Astro

Update `astro.config.mjs`:

```javascript
import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://digilab.cards',
  integrations: [mdx(), sitemap()],
  output: 'static',
});
```

## Step 4: Set Up Project Structure

```bash
# Create directories
mkdir -p src/content/blog
mkdir -p src/components
mkdir -p src/layouts
mkdir -p src/styles
mkdir -p public/charts
mkdir -p public/images
mkdir -p public/brand
```

## Step 5: Copy Starter Files

From `digilab-app/docs/plans/digilab-web-starter/`:

```bash
# Copy CLAUDE.md to repo root
cp CLAUDE.md ../digilab-web/

# Copy README.md to repo root
cp README.md ../digilab-web/
```

## Step 6: Copy Brand Assets

From the app repo:

```bash
# Copy SVG assets
cp digilab-app/www/agumon.svg digilab-web/public/brand/
cp digilab-app/www/digivice.svg digilab-web/public/brand/

# Copy favicon (or create new one)
cp digilab-app/www/favicon.svg digilab-web/public/
```

## Step 7: Create Design Tokens

Create `src/styles/tokens.css`:

```css
:root {
  /* Colors - from _brand.yml */
  --color-primary: #0A3055;
  --color-accent: #F7941D;
  --color-background: #f8f9fa;
  --color-background-dark: #1a1a2e;
  --color-text: #212529;
  --color-text-dark: #e9ecef;
  --color-text-muted: #6c757d;

  /* Typography */
  --font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  --font-size-base: 16px;
  --font-size-sm: 14px;
  --font-size-lg: 18px;
  --font-size-xl: 24px;
  --font-size-2xl: 32px;
  --font-size-3xl: 48px;

  /* Spacing */
  --space-xs: 4px;
  --space-sm: 8px;
  --space-md: 16px;
  --space-lg: 24px;
  --space-xl: 32px;
  --space-2xl: 48px;
  --space-3xl: 64px;

  /* Border radius */
  --radius-sm: 4px;
  --radius-md: 8px;
  --radius-lg: 16px;
  --radius-full: 9999px;

  /* Shadows */
  --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.05);
  --shadow-md: 0 4px 6px rgba(0, 0, 0, 0.1);
  --shadow-lg: 0 10px 15px rgba(0, 0, 0, 0.1);
}

/* Dark mode */
@media (prefers-color-scheme: dark) {
  :root {
    --color-background: var(--color-background-dark);
    --color-text: var(--color-text-dark);
  }
}
```

## Step 8: Create Base Layout

Create `src/layouts/BaseLayout.astro`:

```astro
---
import '../styles/tokens.css';

interface Props {
  title: string;
  description?: string;
  image?: string;
}

const { title, description = "Track local Digimon TCG tournament results, player standings, and deck meta.", image = "/images/og-image.png" } = Astro.props;
---

<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{title} | DigiLab</title>
  <meta name="description" content={description}>

  <!-- Open Graph -->
  <meta property="og:type" content="website">
  <meta property="og:url" content={Astro.url}>
  <meta property="og:title" content={title}>
  <meta property="og:description" content={description}>
  <meta property="og:image" content={image}>

  <!-- Twitter -->
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content={title}>
  <meta name="twitter:description" content={description}>
  <meta name="twitter:image" content={image}>

  <!-- Favicon -->
  <link rel="icon" type="image/svg+xml" href="/favicon.svg">

  <!-- Google Analytics -->
  <script async src="https://www.googletagmanager.com/gtag/js?id=G-NJ3SMG8HGG"></script>
  <script>
    window.dataLayer = window.dataLayer || [];
    function gtag(){dataLayer.push(arguments);}
    gtag('js', new Date());
    gtag('config', 'G-NJ3SMG8HGG', {
      cookie_domain: '.digilab.cards',
      linker: {
        domains: ['digilab.cards', 'app.digilab.cards', 'insights.digilab.cards']
      }
    });
  </script>
</head>
<body>
  <slot />
</body>
</html>
```

## Step 9: Set Up Content Collections

Create `src/content/config.ts`:

```typescript
import { defineCollection, z } from 'astro:content';

const blog = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    description: z.string(),
    date: z.coerce.date(),
    category: z.enum(['announcement', 'technical', 'analysis', 'spotlight', 'devlog']),
    tags: z.array(z.string()).optional(),
    author: z.string().default('Michael Lopez'),
    image: z.string().optional(),
    draft: z.boolean().default(false),
  }),
});

export const collections = { blog };
```

## Step 10: Deploy to Vercel

```bash
# Install Vercel CLI (optional, can use web UI)
npm i -g vercel

# Deploy
vercel

# Or connect via Vercel dashboard:
# 1. Go to vercel.com/new
# 2. Import digilab-web repo
# 3. Framework preset: Astro
# 4. Deploy
```

## Step 11: Configure Domain

In Vercel dashboard:
1. Go to project settings → Domains
2. Add `digilab.cards`
3. Follow DNS instructions to point domain to Vercel

For subdomain setup:
- `digilab.cards` → Vercel (this project)
- `app.digilab.cards` → Posit Connect (existing app)

## Step 12: Set Up GitHub Action for Roadmap Sync

Create `.github/workflows/sync-roadmap.yml` in **digilab-app** repo:

```yaml
name: Sync Roadmap to Website

on:
  push:
    paths:
      - 'ROADMAP.md'
    branches:
      - main

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout app repo
        uses: actions/checkout@v4

      - name: Checkout website repo
        uses: actions/checkout@v4
        with:
          repository: lopezmichael/digilab-web
          path: digilab-web
          token: ${{ secrets.DIGILAB_WEB_TOKEN }}

      - name: Copy roadmap
        run: |
          cp ROADMAP.md digilab-web/src/content/roadmap.md

      - name: Commit and push
        run: |
          cd digilab-web
          git config user.name "GitHub Action"
          git config user.email "action@github.com"
          git add src/content/roadmap.md
          git diff --staged --quiet || git commit -m "Sync ROADMAP.md from digilab-app"
          git push
```

**Note:** Create a Personal Access Token with repo access and add as `DIGILAB_WEB_TOKEN` secret in digilab-app repo settings.

## Step 13: Create First Blog Post

Create `src/content/blog/rating-redesign.mdx`:

```mdx
---
title: "Rating System v2.0 - What Changed and Why"
description: "We redesigned how DigiLab calculates player ratings. Here's the full breakdown of what changed and why."
date: 2026-03-01
category: announcement
tags: [ratings, methodology]
author: Michael Lopez
image: /images/blog/rating-redesign-cover.png
---

Your content here...

(Adapt from docs/plans/2026-03-01-rating-redesign-report.md)
```

## Verification Checklist

- [ ] `npm run dev` starts without errors
- [ ] `npm run build` completes successfully
- [ ] Landing page renders at localhost:4321
- [ ] Blog listing shows posts
- [ ] Individual blog post renders
- [ ] Roadmap page renders
- [ ] Vercel deployment succeeds
- [ ] Custom domain resolves to site
- [ ] GA4 tracking fires (check real-time in Analytics)
- [ ] "Go to App" links work
- [ ] Dark mode toggle works (if implemented)
- [ ] Mobile responsive layout works

## Next Steps After Setup

1. Build out landing page sections (use `frontend-design` skill)
2. Style blog listing and post pages
3. Create roadmap page with filtering
4. Add Header and Footer components
5. Create ChartEmbed component for highcharter widgets
6. Write and publish first blog post
7. Add cross-links from app back to website
