# Content Updates & Error Tracking Design

**Date:** 2026-02-22
**Scope:** CP1 (FAQ), CP2 (About), CP3 (For Organizers), CP4 (External Presence), ERR1 (Sentry)
**Target Version:** v0.28

---

## Goals

1. Rewrite all three content pages for a multi-region audience (not DFW-specific)
2. Cover all features added in v0.24-v0.27 (Limitless, scenes, community links, onboarding, deck requests, online play)
3. Normalize external links (Discord, Ko-fi, GitHub, contact form) into constants
4. Integrate Sentry error tracking for production error visibility

---

## CP4: Link Constants & External Presence

### Problem

Links are scattered and inconsistent across the codebase:
- Ko-fi: `/atomshell` in header vs `/digilab` in content pages
- Discord: only in onboarding modal, missing from content pages
- Google Form: uses placeholder URL `https://forms.google.com/digilab-contact`
- No single source of truth for link updates

### Solution

Define link constants in `app.R`:

```r
LINKS <- list(
  discord  = "https://discord.gg/ABcjha7bHk",
  kofi     = "https://ko-fi.com/digilab",
  github   = "https://github.com/lopezmichael/digimon-tcg-standings",
  contact  = "https://forms.gle/shc6cGjBFNjqvkSw9"
)
```

Replace all hardcoded URLs across:
- `app.R` (header Ko-fi link)
- `views/faq-ui.R`
- `views/about-ui.R`
- `views/for-tos-ui.R`
- `views/onboarding-modal-ui.R`

Add Discord link to all three content pages' contact sections.

---

## CP1: FAQ Rewrite

### Current State

4 categories, 14 questions. Missing scenes, Limitless, community links, online play, deck requests, upload instructions.

### New Structure — 5 Categories

#### Getting Started (new)
- What is DigiLab?
- How do I find my scene? (scene selector, geolocation, manual selection)
- How do I find tournaments near me? (updated for multi-region + online)
- How do I see my tournament history?
- What are community links? (`?community=slug` feature)

#### Ratings & Scores (updated)
- How is Competitive Rating calculated? (keep existing, well-written)
- What is Achievement Score? (keep existing)
- How does Store Rating work? (keep existing)
- Why did my rating go down? (keep existing)
- Are online and in-person ratings the same? (new — yes, same Elo pool)

#### Scenes & Regions (new category)
- What is a scene? (metro area, Global/Country/State/Metro hierarchy)
- What scenes are currently active?
- How do I request a new scene? (link to For Organizers)
- What is the Online scene? (Limitless/webcam tournaments)

#### Data & Coverage (updated)
- Where does the data come from? (updated — OCR uploads + Limitless sync + admin entry)
- How do I upload tournament results? (new — Bandai TCG+ screenshots, Upload Results tab, OCR extraction, review and submit)
- How often is data updated? (updated — uploads immediate, Limitless weekly)
- Why isn't my tournament listed?
- Can I request a new deck archetype? (new — deck request flow)
- Can I get my data corrected or removed?

#### General (updated)
- Is this an official Bandai tool?
- How can I support DigiLab? (updated — add Discord)
- I found a bug! (updated — real form link)
- What do the columns in the tables mean? (moved from "Using the App")

---

## CP2: About Page Rewrite

### Current State

DFW-focused, "created by a North Texas player", coverage section says "Dallas-Fort Worth community."

### New Structure

#### Hero (updated)
- Keep Agumon walking animation
- Tagline: "Track. Compete. Connect." (keep)
- Description rewritten: general community platform, not DFW-specific

#### What is DigiLab? (updated)
- Rewrite from "regional communities" angle — works for any scene
- Mention: tournament tracking, player ratings, deck meta, store discovery
- Emphasize scene-based approach — data relevant to the people you actually play against

#### Who is it For? (updated)
- **Players** — track results, see your rating, follow your local meta
- **Tournament Organizers** — upload results via screenshots or get contributor access
- **Online Competitors** — Limitless/webcam tournament data synced automatically
- **Community Builders** — community links, store pages, scene dashboards

#### Active Scenes (replaces "Current Coverage")
- Dynamic stats grid (keep existing `textOutput` pattern)
- Remove "Dallas-Fort Worth" hardcoding — show aggregate stats
- Add "Scenes" count to the stats grid
- Link to For Organizers for adding new scenes

#### Built By (updated)
- Rewrite from "North Texas player" to "Digimon TCG community member"
- Open source, community-driven
- Contact links using `LINKS$` constants + add Discord

#### Disclaimer (keep as-is)

---

## CP3: For Organizers Rewrite

### Current State

5 sections. Missing Limitless integration, community links, online organizers. Still says "currently focuses on Dallas-Fort Worth." Store requirements say "Online tournament platforms may be added in the future" (already implemented).

### New Structure — 6 Sections

#### Upload Tournament Results (updated)
- Keep the 5-step OCR upload guide (well-written)
- Update "What you'll need" with current info
- Keep match history upload section
- Minor copy refresh

#### Limitless Integration (new section)
- Online tournaments from Limitless TCG synced automatically
- Currently syncing from Tier 1 organizers (Eagle's Nest, PHOENIX REBORN, DMV Drakes, MasterRukasu)
- Deck archetypes auto-classified during sync
- How to get your Limitless organizer page added (contact us)

#### Community Links (new section)
- Explain the `?community=store-slug` feature
- Stores/organizers can share a branded link that filters the entire app to their community
- How to find your store's community link (store modal > Copy Link)
- Use cases: embed on Discord, share on social media, store website

#### Add Your Store (updated)
- Split into Physical Stores and Online Organizers (both supported now)
- Remove "Online tournament platforms may be added in the future"
- Physical: name, address, schedule
- Online: platform name, Limitless page URL, Discord/streaming links
- Updated contact links with real form URL

#### Request a New Scene (updated, renamed from "Region")
- Remove "currently focuses on Dallas-Fort Worth"
- Write as general onboarding for any new scene
- Prerequisites: 2-3 active stores/organizers
- Process: identify contact, submit request, we set up the scene
- Keep "What makes a scene?" sub-section

#### Become a Contributor (light refresh)
- Keep existing structure
- Minor copy updates for multi-region context

#### Report an Error (update links)
- Keep existing structure
- Update to use `LINKS$` constants

---

## ERR1: Sentry Error Tracking

### Package

`sentryR` v1.1.2 (CRAN). Dependencies: `httr`, `jsonlite` (both already in stack).

### Configuration

- Add `SENTRY_DSN` environment variable to `.env` / `.env.example`
- Initialize in `app.R` at startup, conditional on DSN:

```r
if (nzchar(Sys.getenv("SENTRY_DSN", ""))) {
  sentryR::configure_sentry(
    dsn = Sys.getenv("SENTRY_DSN"),
    app_name = "digilab",
    app_version = "0.28.0",
    environment = ifelse(.Platform$OS.type == "unix", "production", "development")
  )
}
```

No-op in local dev if DSN is not set.

### Integration Points

1. **Global Shiny error handler** — `options(shiny.error = ...)` captures unhandled errors
2. **`safe_query()` wrapper** — Add `sentryR::capture_exception(e)` in existing tryCatch error handler
3. **`safe_execute()` wrapper** — Same pattern

### What Gets Captured

- Unhandled Shiny errors (global handler)
- Database query failures (safe_query)
- Database write failures (safe_execute)
- Environment context: app version, scene, OS type

### What Does NOT Change

- Existing `notify()` toast behavior — users see same error messages
- Existing `message()` console logging — still works for local debugging
- No client-side JS error tracking (not needed for R Shiny)

### Manual Setup (outside the app)

- Create Sentry project at sentry.io (free tier: 5K errors/month)
- Get DSN, add to `.env` on Posit Connect
