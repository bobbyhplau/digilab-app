# Content Updates & Error Tracking Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite all content pages for multi-region audience, normalize external links, and integrate Sentry error tracking.

**Architecture:** Content pages are R-HTML in `views/*.R` files, rendered via `nav_panel_hidden()` in app.R. External links will be centralized as constants. Sentry integrates via `sentryR` package into existing `safe_query()`/`safe_execute()` wrappers.

**Tech Stack:** R Shiny, bslib accordion, sentryR, shinyjs

**Design Doc:** `docs/plans/2026-02-22-content-and-error-tracking-design.md`

---

## Task 1: Link Constants & External Presence Normalization (CP4)

Define a single source of truth for all external URLs and replace all hardcoded links across the codebase.

**Files:**
- Modify: `app.R` (~line 354, after EVENT_TYPES)
- Modify: `app.R:674` (header Ko-fi link)
- Modify: `app.R:815` (footer GitHub link)
- Modify: `views/faq-ui.R:218,240,246` (Ko-fi, form, GitHub links)
- Modify: `views/about-ui.R:103,109,115` (GitHub, Ko-fi, form links)
- Modify: `views/for-tos-ui.R:140,146,198,204,271,315,321,340,346,352` (form, GitHub, Ko-fi links)
- Modify: `views/onboarding-modal-ui.R:153,163` (Discord, Ko-fi links)
- Modify: `server/public-submit-server.R:1079` (placeholder form URL)

**Step 1: Add LINKS constant to app.R**

After `EVENT_TYPES` (line 353), add:

```r
# External links (single source of truth)
LINKS <- list(
  discord = "https://discord.gg/ABcjha7bHk",
  kofi    = "https://ko-fi.com/digilab",
  github  = "https://github.com/lopezmichael/digimon-tcg-standings",
  contact = "https://forms.gle/shc6cGjBFNjqvkSw9"
)
```

**Step 2: Replace hardcoded links in app.R**

- Line 674: `href = "https://ko-fi.com/atomshell"` → `href = LINKS$kofi`
- Line 815: `href = "https://github.com/lopezmichael/digimon-tcg-standings"` → `href = LINKS$github`

**Step 3: Replace hardcoded links in views/faq-ui.R**

Replace all occurrences:
- `"https://ko-fi.com/digilab"` → `LINKS$kofi`
- `"https://forms.google.com/digilab-contact"` → `LINKS$contact`
- `"https://github.com/lopezmichael/digimon-tcg-standings/issues/new?title=Bug%20Report"` → `paste0(LINKS$github, "/issues/new?title=Bug%20Report")`

**Step 4: Replace hardcoded links in views/about-ui.R**

Replace all occurrences:
- `"https://github.com/lopezmichael/digimon-tcg-standings"` → `LINKS$github`
- `"https://ko-fi.com/digilab"` → `LINKS$kofi`
- `"https://forms.google.com/digilab-contact"` → `LINKS$contact`

**Step 5: Replace hardcoded links in views/for-tos-ui.R**

Replace all occurrences (6 form links, 3 GitHub links, 1 Ko-fi link):
- `"https://forms.google.com/digilab-contact"` → `LINKS$contact`
- `"https://github.com/lopezmichael/digimon-tcg-standings/issues/new?title=New%20Store%20Request"` → `paste0(LINKS$github, "/issues/new?title=New%20Store%20Request")`
- `"https://github.com/lopezmichael/digimon-tcg-standings/issues/new?title=New%20Region%20Request"` → `paste0(LINKS$github, "/issues/new?title=New%20Region%20Request")`
- `"https://github.com/lopezmichael/digimon-tcg-standings/issues/new?title=Data%20Error%20Report"` → `paste0(LINKS$github, "/issues/new?title=Data%20Error%20Report")`
- `"https://github.com/lopezmichael/digimon-tcg-standings"` → `LINKS$github`
- `"https://ko-fi.com/digilab"` → `LINKS$kofi`

**Step 6: Replace hardcoded links in views/onboarding-modal-ui.R**

- Line 153: `href = "https://discord.gg/ABcjha7bHk"` → `href = LINKS$discord`
- Line 163: `href = "https://ko-fi.com/digilab"` → `href = LINKS$kofi`

**Step 7: Fix placeholder in server/public-submit-server.R**

- Line 1079: `href = "https://forms.gle/placeholder"` → `href = LINKS$contact`

**Step 8: Commit**

```bash
git add app.R views/faq-ui.R views/about-ui.R views/for-tos-ui.R views/onboarding-modal-ui.R server/public-submit-server.R
git commit -m "refactor: centralize external links into LINKS constant"
```

---

## Task 2: FAQ Page Rewrite (CP1)

Complete rewrite of `views/faq-ui.R` with 5 categories covering all features through v0.27.

**Files:**
- Modify: `views/faq-ui.R` (full rewrite, ~254 lines → ~400 lines)

**Step 1: Rewrite the entire file**

Replace the full contents of `views/faq-ui.R` with the new 5-category FAQ. The file uses the existing pattern of `accordion()` with `accordion_panel()` items inside a `div(class = "content-page")` wrapper.

**New structure:**

```
faq_ui <- div(
  class = "content-page",

  # Header
  # (same pattern: content-page-header, h1, p subtitle)

  # Category 1: Getting Started
  h2(class = "faq-category", icon, "Getting Started")
  accordion(id = "faq_getting_started", open = FALSE,
    - "What is DigiLab?" — Community-built tournament tracker for any Digimon TCG scene. Not global meta — focused on regional communities. Scene-based: your data is about the people you actually play against.
    - "How do I find my scene?" — Use the scene selector in the header. Geolocation auto-detects your area, or pick manually. Scenes are metro areas / communities. "Online" scene covers Limitless webcam tournaments.
    - "How do I find tournaments near me?" — Stores tab shows all active locations with map. Tournaments tab for chronological list. Filter by scene for your area. Online events appear in the Online scene.
    - "How do I see my tournament history?" — Players tab, search your name, click row. Shows: all results, rating, achievement score, decks played, performance trend.
    - "What are community links?" — Stores and organizers can share a filtered view of DigiLab for their community. If you arrive via a community link (?community=slug), all tabs filter to that community's data. Look for the community badge in the header.
  )

  # Category 2: Ratings & Scores
  h2(class = "faq-category", icon, "Ratings & Scores")
  accordion(id = "faq_ratings", open = FALSE,
    - "How is Competitive Rating calculated?" — KEEP existing content (lines 59-80). Elo-style, implied results, K-factor, starting 1500.
    - "What is Achievement Score?" — KEEP existing content (lines 82-108). Points table, size bonus.
    - "How does Store Rating work?" — KEEP existing content (lines 110-129). Weighted player base.
    - "Why did my rating go down even though I won matches?" — KEEP existing content (lines 130-139). Placement-based.
    - "Are online and in-person ratings the same?" — NEW. Yes, all tournaments feed the same Elo rating pool regardless of whether they're in-person or online. This means your rating reflects your full competitive performance across all formats.
  )

  # Category 3: Scenes & Regions
  h2(class = "faq-category", icon, "Scenes & Regions")
  accordion(id = "faq_scenes", open = FALSE,
    - "What is a scene?" — A scene is a community of players who regularly compete together, usually based on a metro area. DigiLab organizes data by scenes so your leaderboards and meta analysis reflect the players you actually face. Scenes follow a hierarchy: Global > Country > State > Metro.
    - "What scenes are currently active?" — Use the scene selector dropdown in the header to see all available scenes. Each scene has its own stores, players, and tournament data. New scenes are added as communities join.
    - "How do I request a new scene?" — Link to For Organizers page. Need 2-3 active stores with regular events. A community contact who can help gather initial data.
    - "What is the Online scene?" — The Online scene covers webcam tournaments run through platforms like Limitless TCG. Online tournament data is synced automatically. Online and in-person results feed the same rating system.
  )

  # Category 4: Data & Coverage
  h2(class = "faq-category", icon, "Data & Coverage")
  accordion(id = "faq_data", open = FALSE,
    - "Where does the data come from?" — Three sources: (1) Community uploads via the Upload Results tab using Bandai TCG+ screenshots. (2) Automatic sync from Limitless TCG online tournaments. (3) Admin contributors who enter results manually. Card data and images come from DigimonCard.io API.
    - "How do I upload tournament results?" — NEW. Go to Upload Results tab. Take screenshots of final standings from Bandai TCG+ app (make sure placements, usernames, and member numbers are visible). Fill in tournament details (store, date, event type, format, players, rounds). Our OCR system reads the screenshots and extracts data automatically. Review results, fix any OCR errors, assign deck archetypes if known. Submit — results go live immediately.
    - "How often is data updated?" — Community uploads go live immediately. Limitless online tournaments sync weekly. Card data syncs monthly from DigimonCard.io. Ratings and stats recalculate automatically.
    - "Why isn't my tournament listed?" — Nobody has uploaded the results yet. The store isn't registered. The tournament was unofficial. You can upload results yourself via Upload Results tab. See For Organizers page for guides.
    - "Can I request a new deck archetype?" — NEW. If a deck isn't in the dropdown when assigning archetypes, you can request it. Use the "Request New Deck" option in the deck selector. Requests are reviewed and approved by community contributors.
    - "Can I get my data corrected or removed?" — Yes. Reach out via the contact links below. We want accuracy and respect player privacy.
  )

  # Category 5: General
  h2(class = "faq-category", icon, "General")
  accordion(id = "faq_general", open = FALSE,
    - "Is this an official Bandai tool?" — KEEP existing content. No, fan-made.
    - "How can I support DigiLab?" — Submit results, spread the word, report bugs, join the Discord, support on Ko-fi. Add Discord link. Use LINKS$ constants.
    - "I found a bug! How do I report it?" — What to include list. Contact links using LINKS$ constants (form + GitHub). Add Discord as option.
    - "What do the columns in the tables mean?" — MOVED from "Using the App". Rating, Score, Record, Meta %, Conv %.
  )
)
```

**Key rules:**
- Use `LINKS$kofi`, `LINKS$contact`, `LINKS$github`, `LINKS$discord` for all external URLs
- Keep `actionLink()` for internal cross-page navigation (e.g., `actionLink("faq_to_upload", ...)`)
- Keep existing accordion_panel `value` attributes where content is preserved (for deep linking)
- Use `bsicons::bs_icon()` for all icons
- Match existing CSS classes: `content-page`, `content-page-header`, `faq-category`, `contact-links`, `contact-link`, `formula-box`, `points-table`

**Step 2: Commit**

```bash
git add views/faq-ui.R
git commit -m "feat: rewrite FAQ page for multi-region audience with v0.24-v0.27 features"
```

---

## Task 3: About Page Rewrite (CP2)

Rewrite `views/about-ui.R` for multi-region audience with updated coverage section.

**Files:**
- Modify: `views/about-ui.R` (rewrite, ~133 lines → ~150 lines)
- Modify: `server/public-dashboard-server.R` (add scenes count output if not exists)

**Step 1: Rewrite about-ui.R**

Replace the full contents with the new multi-region About page.

**New structure:**

```
about_ui <- div(
  class = "content-page",

  # Header — keep pattern
  div(class = "content-page-header",
    h1("About DigiLab"),
    p("Tournament tracking for the Digimon TCG community")
    # Remove "Regional" — it's for any community now
  )

  # Hero — keep Agumon walking animation
  div(class = "about-hero",
    # Keep mascot walkway animation exactly as-is
    p(class = "about-tagline", "Track. Compete. Connect."),
    p(class = "about-description",
      "DigiLab is a community-built platform for tracking Digimon TCG tournament results, ",
      "player ratings, and deck meta across local and online scenes.")
    # Changed from "local Digimon TCG tournament results" to include online
  )

  # What is DigiLab? — rewrite for multi-region
  div(class = "content-section",
    h2("What is DigiLab?"),
    p("DigiLab brings tournament data to your Digimon TCG community. Unlike global meta trackers, ",
      "DigiLab is scene-based — it helps you understand how you stack up against the players ",
      "you actually compete with, whether that's at your local game store or in online webcam tournaments."),
    ul(
      li("Track your tournament history and rating progression"),
      li("See what decks are performing in your scene's meta"),
      li("Compare performance across stores and online events"),
      li("Discover active tournament locations and communities")
    )
  )

  # Who is it For? — add online competitors and community builders
  div(class = "content-section",
    h2("Who is it For?"),
    p(strong("Players"), " — Track your results, see your rating, and follow your local meta"),
    p(strong("Tournament Organizers"), " — Upload results via Bandai TCG+ screenshots or get contributor access"),
    p(strong("Online Competitors"), " — Limitless and webcam tournament data syncs automatically"),
    p(strong("Community Builders"), " — Share community links, build store pages, and grow your scene")
  )

  # Active Scenes — replaces "Current Coverage"
  div(class = "content-section",
    h2("Active Scenes"),
    # Remove all "Dallas-Fort Worth" references
    p("DigiLab tracks Digimon TCG communities across multiple scenes. ",
      "Each scene has its own stores, players, and meta data. ",
      "Want your area added? See the ",
      actionLink("about_to_for_tos", "For Organizers page"), "."),

    # Stats grid — keep existing textOutput pattern, add Scenes count
    div(class = "about-stats-grid",
      div(class = "about-stat-item",
        div(class = "about-stat-value", textOutput("about_scene_count", inline = TRUE)),
        div(class = "about-stat-label", "Active Scenes")),
      div(class = "about-stat-item",
        div(class = "about-stat-value", textOutput("about_store_count", inline = TRUE)),
        div(class = "about-stat-label", "Active Stores")),
      div(class = "about-stat-item",
        div(class = "about-stat-value", textOutput("about_player_count", inline = TRUE)),
        div(class = "about-stat-label", "Players Tracked")),
      div(class = "about-stat-item",
        div(class = "about-stat-value", textOutput("about_tournament_count", inline = TRUE)),
        div(class = "about-stat-label", "Tournaments"))
    )
    # Removed "Results Recorded" (4th stat) — replaced with "Active Scenes" (1st stat)
  )

  # Built By — generalize
  div(class = "content-section",
    h2("Built By"),
    p("DigiLab was created by a Digimon TCG community member who wanted better tools for ",
      "tracking local tournament performance. The project is open source and community-driven."),
    # Contact links using LINKS$ constants — add Discord
    div(class = "contact-links contact-links--centered",
      a(href = LINKS$discord, "Discord"),
      a(href = LINKS$github, "GitHub"),
      a(href = LINKS$kofi, "Ko-fi"),
      a(href = LINKS$contact, "Contact Form")
    )
  )

  # Disclaimer — keep as-is
)
```

**Step 2: Add scene count server output**

In `server/public-dashboard-server.R`, find the existing about page outputs (`output$about_store_count`, etc.) and add:

```r
output$about_scene_count <- renderText({
  if (is.null(rv$db_con) || !dbIsValid(rv$db_con)) return(0)
  safe_query(rv$db_con, "SELECT COUNT(*) as n FROM scenes WHERE slug != 'all'",
             default = data.frame(n = 0))$n
})
```

**Step 3: Commit**

```bash
git add views/about-ui.R server/public-dashboard-server.R
git commit -m "feat: rewrite About page for multi-region audience"
```

---

## Task 4: For Organizers Page Rewrite (CP3)

Rewrite `views/for-tos-ui.R` with new Limitless and Community Links sections, updated for multi-region.

**Files:**
- Modify: `views/for-tos-ui.R` (rewrite, ~359 lines → ~500 lines)

**Step 1: Rewrite the entire file**

Replace the full contents with the new 6-section For Organizers page.

**New structure:**

```
for_tos_ui <- div(
  class = "content-page",

  # Header
  div(class = "content-page-header",
    h1("For Organizers"),
    p("Help grow your Digimon TCG community")
    # Changed from "local Digimon TCG scene" to "community"
  )

  # Intro — rewrite
  p("Tournament organizers and community builders are the backbone of the Digimon TCG scene. ",
    "DigiLab helps you showcase your events, track your community's growth, and connect with players.")

  # Section 1: Upload Tournament Results (updated, keep existing 5-step guide mostly intact)
  h2("Upload Tournament Results")
  accordion(id = "tos_submit", open = TRUE,
    - "How to upload results" — Keep existing 5-step OCR guide. Minor copy refresh. Use LINKS$ for any external links.
    - "What you'll need" — Keep existing. Minor updates.
    - "Uploading match history" — Keep existing.
  )

  # Section 2: Limitless Integration (NEW)
  h2("Limitless Integration")
  accordion(id = "tos_limitless", open = FALSE,
    - "How Limitless sync works" — Online tournaments from Limitless TCG are synced automatically into DigiLab. Results, placements, and deck archetypes are imported weekly. Online tournaments appear in the "Online" scene and feed the same rating system as in-person events.
    - "Currently synced organizers" — List: Eagle's Nest, PHOENIX REBORN, DMV Drakes, MasterRukasu. These are Tier 1 organizers with regular events.
    - "Get your organizer page added" — If you run online tournaments on Limitless TCG, contact us to add your organizer page to the sync. Provide: your Limitless organizer name/URL, approximate event frequency. Use LINKS$contact.
  )

  # Section 3: Community Links (NEW)
  h2("Community Links")
  accordion(id = "tos_community", open = FALSE,
    - "What are community links?" — Every store and organizer on DigiLab has a unique community link. When shared, it filters the entire app to show only that community's data — tournaments, players, meta, everything. URL format: digilab.cards/?community=your-store-slug.
    - "How to find your community link" — Go to the Stores tab, find your store, click it to open the modal. Look for the "Copy Link" button in the modal footer. Share this link on your Discord server, social media, or store website.
    - "Use cases" — Embed on your Discord: post the link so players can check standings anytime. Social media: share after events so players can see updated results. Store website: link to your community's DigiLab page.
  )

  # Section 4: Add Your Store (updated — split physical/online)
  h2("Add Your Store")
  accordion(id = "tos_store", open = FALSE,
    - "Physical stores" — Provide: store name, address, city, state. Share tournament schedule (days/times). Contact us via form or GitHub. Use LINKS$ constants.
    - "Online organizers" — Already running webcam events? Online organizers are supported. Provide: platform name, Limitless page URL, Discord server. Events sync automatically via Limitless integration once added. Use LINKS$ constants.
    - "Store requirements" — Physical: regular Digimon TCG events (at least monthly), uses Bandai TCG+ or Limitless, open to public. Online: regular scheduled events, public registration. Remove "Online tournament platforms may be added in the future."
  )

  # Section 5: Request a New Scene (updated from "Region")
  h2("Request a New Scene")
  accordion(id = "tos_scene", open = FALSE,
    - "How to get your scene added" — REMOVE "currently focuses on Dallas-Fort Worth." Write as general onboarding. Your scene should have at least 2-3 active stores or organizers with regular events. Identify a community contact. Submit request via form/GitHub. Use LINKS$ constants.
    - "What makes a scene?" — Keep existing "geography + community + activity" definition. Update examples to be more diverse (not just Texas cities). A scene is a community of players who regularly compete. Usually a metro area or region.
  )

  # Section 6: Become a Contributor (light refresh)
  h2("Become a Contributor")
  accordion(id = "tos_contributor", open = FALSE,
    - "What is a contributor?" — Keep existing. Minor copy updates.
    - "How do I become a contributor?" — Keep existing. Use LINKS$ for contact.
  )

  # Section 7: Report an Error (update links)
  h2("Report an Error")
  accordion(id = "tos_errors", open = FALSE,
    - "How to report data errors" — Keep existing structure. Use LINKS$ constants for all contact links.
  )

  # Contact section (bottom) — use LINKS$ constants, add Discord
  div(class = "content-section",
    h2("Questions?"),
    div(class = "contact-links",
      a(href = LINKS$discord, "Discord"),
      a(href = LINKS$contact, "Contact Form"),
      a(href = LINKS$github, "GitHub"),
      a(href = LINKS$kofi, "Ko-fi")
    )
  )
)
```

**Key rules:**
- All external links use `LINKS$` constants
- Keep existing `actionLink()` patterns for internal navigation
- Keep existing accordion `value` attributes where content is preserved
- Remove all DFW-specific language
- Use `bsicons::bs_icon()` for all icons

**Step 2: Commit**

```bash
git add views/for-tos-ui.R
git commit -m "feat: rewrite For Organizers page with Limitless, community links, multi-region"
```

---

## Task 5: Sentry Error Tracking (ERR1)

Integrate sentryR for production error visibility.

**Files:**
- Modify: `.env.example` (add SENTRY_DSN)
- Modify: `app.R` (~line 354, after LINKS constant — add Sentry init)
- Modify: `server/shared-server.R:445-484` (safe_query — add capture_exception)
- Modify: `server/shared-server.R:501-513` (safe_execute — add capture_exception)

**Step 1: Install sentryR**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "install.packages('sentryR')"
```

Then add to renv:

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "renv::snapshot()"
```

**Step 2: Add SENTRY_DSN to .env.example**

Append to `.env.example`:

```
# Sentry Error Tracking (optional - errors logged to console if not set)
# Create a project at https://sentry.io and get your DSN
SENTRY_DSN=
```

**Step 3: Add Sentry initialization to app.R**

After the `LINKS` constant (added in Task 1), add:

```r
# Sentry error tracking (no-op if DSN not set)
sentry_enabled <- FALSE
if (nzchar(Sys.getenv("SENTRY_DSN", ""))) {
  tryCatch({
    sentryR::configure_sentry(
      dsn = Sys.getenv("SENTRY_DSN"),
      app_name = "digilab",
      app_version = "0.28.0",
      environment = ifelse(.Platform$OS.type == "unix", "production", "development")
    )
    sentry_enabled <- TRUE
    message("[sentry] Initialized successfully")
  }, error = function(e) {
    message("[sentry] Failed to initialize: ", conditionMessage(e))
  })
}
```

Also add the global Shiny error handler. Inside the `server <- function(input, output, session) {` block, near the top, add:

```r
# Global error handler for Sentry
if (sentry_enabled) {
  options(shiny.error = function() {
    sentryR::capture_exception(geterrmessage())
  })
}
```

**Step 4: Add Sentry capture to safe_query()**

In `server/shared-server.R`, inside the `safe_query` function's error handler (line 453), add a Sentry capture call right after the existing `message()` log line (line 457):

```r
    # Send to Sentry if enabled
    if (sentry_enabled) {
      tryCatch(sentryR::capture_exception(e), error = function(se) NULL)
    }
```

Place this AFTER line 457 (`message("[safe_query] Error: ", msg, ...)`) and BEFORE the reconnection logic (line 460).

**Step 5: Add Sentry capture to safe_execute()**

In `server/shared-server.R`, inside the `safe_execute` function's error handler (line 508), add after the existing `message()` lines:

```r
    # Send to Sentry if enabled
    if (sentry_enabled) {
      tryCatch(sentryR::capture_exception(e), error = function(se) NULL)
    }
```

Place this AFTER line 510 and BEFORE `0  # Return 0 rows affected`.

**Step 6: Add library(sentryR) to app.R**

Find the library loading section at the top of `app.R` and add `library(sentryR)`. Since Sentry is optional, this should be a conditional load. Alternatively, since we use `sentryR::` prefix everywhere, we can skip the library() call entirely — the namespace prefix handles it.

Actually, since we use `sentryR::configure_sentry()` and `sentryR::capture_exception()` with full namespace prefixes, and the init is wrapped in tryCatch, we do NOT need `library(sentryR)`. The package just needs to be installed. This means it fails gracefully if the package isn't available.

**Step 7: Commit**

```bash
git add app.R server/shared-server.R .env.example
git commit -m "feat: integrate Sentry error tracking (sentryR)"
```

Note: Do NOT commit renv.lock changes in this commit — renv snapshot may not work cleanly from bash. The user can run `renv::snapshot()` manually.

---

## Task 6: Verification

**Files:** None (verification only)

**Step 1: Run R syntax check**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "tryCatch(source('app.R'), error = function(e) cat('ERROR:', e[['message']], '\n'))"
```

Expected: No errors (renv warning is OK).

**Step 2: Verify no hardcoded links remain**

Search for old hardcoded URLs that should have been replaced:

```bash
grep -r "forms.google.com/digilab-contact" views/ server/
grep -r "ko-fi.com/atomshell" views/ app.R
grep -r "forms.gle/placeholder" server/
```

Expected: No matches.

**Step 3: Verify LINKS constant is used**

```bash
grep -r "LINKS\$" views/ app.R server/
```

Expected: Multiple matches across all content files.

**Step 4: Manual verification checklist**

Ask user to verify:
1. FAQ page loads with 5 categories and all questions expand
2. About page shows live stats including Scenes count
3. For Organizers page has Limitless and Community Links sections
4. All external links (Discord, Ko-fi, GitHub, Contact) work correctly
5. App starts without errors when SENTRY_DSN is not set (graceful no-op)
