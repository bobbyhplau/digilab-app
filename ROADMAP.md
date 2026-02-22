# DigiLab - Roadmap

This document outlines the planned features, improvements, and bug fixes for the tournament tracker.

**Current Version:** v0.28.0
**Target:** v1.0 Public Launch
**Cadence:** ~1 milestone per week

---

## v0.29 - Website & SEO

| ID | Type | Description |
|----|------|-------------|
| WS1 | FEATURE | Static website at digilab.cards (GitHub Pages) — landing page, About, FAQ, For Organizers |
| WS2 | FEATURE | Shiny app footer links redirect to static site pages (parent frame navigation) |
| UX10 | UX | Custom GA4 events (track tab visits, filter usage, modal opens) |
| SEO1 | SEO | Crawlable static pages (replaces iframe-trapped content) |
| SEO2 | SEO | Structured data (JSON-LD) on static site |
| SEO3 | SEO | Search Console integration |
| REV2 | REVIEW | Review OCR setup and screenshot parsing pipeline — audit accuracy, error handling, and UX |

**Website Architecture:**
- digilab.cards becomes a hub: `/app` (Shiny iframe), `/about`, `/faq`, `/organizers`, `/meta-report` (future)
- Static site built with GitHub Pages (free, fast, crawlable by Google)
- Shiny app stays on Posit Connect unchanged — static site wraps it
- Future apps/reports (e.g., weekly meta report) get their own routes

---

## v1.0 - Public Launch

| ID | Type | Description |
|----|------|-------------|
| W2 | FEATURE | Methodology pages — simple rating overview + detailed formula breakdown |
| W3 | FEATURE | Weekly Meta Report page — auto-generated from tournament data |
| X1 | IMPROVEMENT | Remove BETA badge |
| PWA1 | FEATURE | PWA manifest + service worker for mobile "install" and offline shell |

---

## Post-v1.0 / Deferred

### User Accounts & Permissions

**Design:** `docs/plans/2026-02-05-user-accounts-design.md`

| ID | Type | Description |
|----|------|-------------|
| UA1 | FEATURE | Discord OAuth login ("Login with Discord") via `httr2` |
| UA2 | FEATURE | Users table with Discord ID, username, role, scene assignment |
| UA3 | FEATURE | Permission levels: Viewer (default, no login), Scene Admin, Super Admin |
| UA4 | FEATURE | Scene Admin can manage data for their assigned scene only |
| UA5 | FEATURE | Super Admin can manage all data, users, and scenes |
| UA6 | FEATURE | Admin invite links (Super Admin generates link → Scene Admin) |
| UA7 | FEATURE | Direct user promotion (Super Admin promotes existing users) |
| UA8 | UI | Permission-scoped admin tabs (hidden unless logged in with role) |
| UA9 | SECURITY | Cookie-based session persistence (survives page refresh) |
| UA10 | SECURITY | Permission middleware — check auth on every admin mutation |
| UA11 | SECURITY | `admin_actions` audit log table (who, what, when, before/after) |
| UA12 | SECURITY | Rate limiting on admin mutations |

### Self-Service Extras

| ID | Type | Description |
|----|------|-------------|
| F10 | FEATURE | Player achievement badges — auto-calculated, displayed in player modal |
| UX11 | UX | Player modal: head-to-head teaser ("Best record vs: PlayerX (3-0)") |
| UX12 | UX | Tournament table: result distribution mini-chart (top 3 deck colors inline) |

### Modal Enhancements

| ID | Type | Description |
|----|------|-------------|
| UX4 | UX | Player modal: deck history (which decks they've played) |
| UX5 | UX | Deck modal: matchup matrix (win/loss vs top 5 other decks) |

### Multi-Region Extras

| ID | Type | Description |
|----|------|-------------|
| MR8 | SCHEMA | Add `tier` to tournaments table (local, regional, national, international) |
| MR9 | FEATURE | Player "home scene" inference (mode of tournament scenes played) |
| MR10 | FEATURE | Scene comparison page (DFW vs Houston side-by-side stats) |
| MR11 | FEATURE | Cross-scene badges in player modal ("Competed in: DFW, Houston, Austin") |
| MR12 | FEATURE | Scene health dashboard for Scene Admins (trends, retention, store activity) |

### Infrastructure

| ID | Type | Description |
|----|------|-------------|
| LI8 | FEATURE | GitHub Actions daily automated Limitless sync |
| MR16 | PERFORMANCE | Pre-computed dashboard stats cache table (recalc on data change) |
| MR17 | PERFORMANCE | Profile with `shinyloadtest` and size Posit Connect tier |

---

## Parking Lot

Items for future consideration, not scheduled:

| ID | Type | Description | Notes |
|----|------|-------------|-------|
| FD1 | IMPROVEMENT | Smart format default | Default to current format group instead of "All Formats" |
| F2c | FEATURE | Error flagging | "Report Error" link in modals → creates admin notification |
| F8 | FEATURE | Embed widgets for stores | Let stores embed tournament history on their sites |
| P2 | FEATURE | Discord bot for result reporting | Could integrate with user accounts system |
| P4 | FEATURE | One Piece TCG support | Multi-game expansion |
| P5 | FEATURE | Mobile-first data entry PWA | Consider after v1.0 platform evaluation |
| RA1 | FEATURE | Regional Admin role | Middle tier between Scene Admin and Super Admin |
| UX7 | UX | Stores tab: "Next Event" prominently shown per store | Needs store schedule data |
| UX8 | UX | Dashboard: community pulse ("3 tournaments this week, 47 active players") | Nice-to-have |
| UX9 | UX | Dashboard: new format callout banner when a new set drops | Nice-to-have |
| UX13 | UX | Distance-based store sorting | Sort stores by proximity using localStorage scene |
| UX14 | UX | Tournament "upcoming" section | Show future events from store schedules above recent results |
| LI12 | FEATURE | Online store links (Discord/YouTube instead of address/map) | Partially done with community links |
| DM3 | UI | Agumon error/offline state — worried pose with sweat drop | See `docs/digimon-mascots.md` |
| DM6 | UI | Digivice footer watermark — subtle branding element | See `docs/digimon-mascots.md` |
| DM7 | UI | Agumon 404/not found state — lost/searching pose | See `docs/digimon-mascots.md` |
| DM8 | UI | Agumon achievement unlocked — celebrating pose | Needs achievement system (F10) first |
| DM-COMM | BRANDING | Commission custom Digimon SVG set — multi-character, multi-mood | See `docs/digimon-mascots.md` for full spec |

---

## Removed / Won't Do

| Description | Reason |
|-------------|--------|
| Global search bar in header | Not needed — tabs and modals provide sufficient navigation |
| Guided tour (standalone) | Replaced by revamped onboarding modal carousel (OH1) |
| Deck modal: pilots leaderboard | Already covered by Deck Meta tab "top pilots" section |
| Expand to other Texas regions | Already supported by scenes hierarchy (multi-region implemented v0.23) |
| Limitless TCG API deep integration | Completed in v0.24 |
| Date range filtering on dashboard | Not needed — format filter is sufficient |
| Detailed player profile views | Modals already cover this |
| Detailed deck profile views | Modals already cover this |
| Event calendar page | Bandai TCG Plus already covers this |
| Store directory page | Bandai TCG Plus already covers this |
| Data export for users | Handle manually on request |
| Season/format archive view | Format filter already covers this |
| GitHub Action keepalive ping | Burns Posit Connect hours 24/7 for minimal benefit |
| Aggressive idle timeout increases | Wastes Posit Connect hours on zombie sessions |

---

## Post-v1.0 Decision Point: Platform Evaluation

After v1.0 launch data, evaluate whether to begin a Next.js migration based on:

| Question | If Yes → Next.js | If No → Stay Shiny |
|----------|------------------|---------------------|
| Is organic search traffic a growth priority? | SSR pages are crawlable | Word-of-mouth via Discord is enough |
| Hitting Posit Connect scaling limits? | Stateless architecture scales better | Caching solved the problem |
| Want standalone API for bots/tools? | API routes are native | Manual data sharing is fine |
| Want mobile app / PWA features? | Native strengths | Basic PWA on Shiny is sufficient |
| Multiple regions need fast edge loading? | CDN + edge rendering | Single-region performance is adequate |

The React PoC on `explore/react-rewrite` branch serves as a reference for future migration decisions.

---

## Completed

### v0.28.0 - Content Updates, Error Tracking & Admin UX
- FAQ page rewrite: 5 categories, 22 questions covering all features through v0.27
- About page rewrite: multi-region language, Active Scenes stat, Discord link
- For Organizers page rewrite: Limitless Integration section, Community Links section, scene request flow
- Centralized external URLs into `LINKS` constant (Discord, Ko-fi, GitHub, contact form)
- Sentry error tracking integration (`sentryR`) with `safe_query()`/`safe_execute()` capture and global error handler
- Cross-page navigation sidebar sync fix (all 11 handlers)
- REV1 Admin UX audit — design doc + full implementation:
  - Expanded TX-only state dropdown to all 50 US states + DC
  - Replaced technical OCR error messages with user-friendly text
  - Added record format help text, release event callout, player matching explanation
  - Standardized info hint boxes across all 6 admin pages
  - Removed debug `message()` calls from production code
  - Added multi-color checkbox and geocoding help text
- UX polish round 2: skeleton loaders, filter-aware empty states, `notify()` smart durations, inline form validation, debounced search, value box count-up animation, modal system consolidation

### v0.27.0 - Onboarding & Help
- Revamped onboarding modal — 3-step carousel: Welcome (Agumon hero + feature list), Scene Selection (map + geolocation), Community Links (Discord, Ko-fi, For Organizers)
- Progress bar, pill-shaped dot indicators, per-step navigation (Skip/Get Started, Back/Almost Done, Back/Enter DigiLab)
- Welcome Guide icon in footer to reopen onboarding for returning users
- Contextual hints on dashboard tables ("Click a row for full results", "Click a deck for details")
- Rating/Score FAQ links in Players tab help text → navigate to FAQ methodology
- Info hint boxes on admin pages (Stores, Decks, Formats) explaining each form
- Per-page help text on all 5 public tabs (Dashboard, Players, Meta, Tournaments, Stores)
- Agumon mascot in empty states (7 call sites), About page hero (walking animation), and onboarding welcome step
- `agumon_svg()` helper and `digital_empty_state(mascot)` parameter for consistent mascot placement

### v0.26.0 - UI Polish & Responsiveness
- Filter prominence improvements across all tabs
- Pill toggle prominence on Players & Deck Meta
- Hot Deck value box auto-resize text
- Top Decks and Rising Stars responsive grid
- Player attendance chart filtered to local events
- Stores: Cards view as default, improved card styling
- Flat map projection for All/Online scenes
- Player modal rating trend sparkline
- Agumon SVG on loading screen
- Mobile table column prioritization
- Admin table row selection audit fix

### v0.25.0 - Stores & Filtering Enhancements
- Online Organizers World Map with country-level markers
- Cards View replaces "All Stores" table on Stores tab
- Community Links (`?community=store-slug` URL filtering across all tabs)
- Admin Scene Filtering (admin tables respect scene selection, super admin override)
- Country field for online stores, region-based mini maps in modals
- Unified store modal for physical and online stores

### v0.24.0 - Limitless Integration & Admin Improvements
- Limitless TCG sync script (137 tournaments, 2,124 results from 5 organizers)
- Deck auto-classification (80+ archetype rules, 95% success rate)
- Deck archetype merge tool, enhanced player merge (matches + limitless_username)
- Grid-based bulk entry for tournament results
- Paste from Spreadsheet modal, inline player matching badges
- Admin table row selection fix, dashboard initialization fix

### v0.23.1 - Multi-Region, Polish & Performance
- Scene selector with dynamic DB loading, onboarding modal, localStorage persistence
- Geolocation "Find My Scene" support
- Scene filtering across all tabs
- Dashboard split: format-specific meta + community health sections
- Dashboard layout: removed Top Players table, rearranged into Meta Diversity + Recent Tournaments row
- Player Growth chart switched from monthly to weekly granularity
- Meta Share chart uses percent stacking (always sums to 100%)
- Overview modals open in-place instead of switching tabs
- Pill toggle filters on Players and Deck Meta tabs
- Top Decks and Rising Stars clickable (open modals)
- Historical format rating snapshots (frozen Elo at era boundaries)
- Batched dashboard queries (deck_analytics + core_metrics)
- Connection auto-reconnection, clean shutdown handler
- Admin lock icon, Ko-fi to header, tab rename to "Deck Meta"
- Release events auto-assign UNKNOWN deck archetype (sealed packs)
- Mobile navbar improvements, XSS prevention

### v0.21.1 - Performance & Security Foundations
- SQL parameterization for all public queries (security)
- safe_query() wrapper for graceful error handling (resilience)
- bindCache() on dashboard outputs (performance)
- Pre-computed ratings cache tables (performance)
- Faster loading: removed delays, lazy-load admin modules
- Library audit: removed 5 unused packages from startup
- Visibility-aware keepalive, custom disconnect overlay (UX)
- SEO: robots.txt, sitemap.xml, og:image meta tags

### v0.21.0 - Deep Linking & Shareable URLs
- Shareable URLs for players, decks, stores, tournaments
- Tab navigation via URL, scene parameter foundation
- Copy Link button in all modal footers
- Browser back/forward support for modal navigation
- Schema: `slug` columns, `scenes` table with hierarchy

### v0.20.2 - Store Modal Polish & Map Improvements
- Store modal redesign: two-column layout (stats + mini map)
- Replaced Store Rating with Avg Player Rating (weighted Elo)
- Tiered bubble sizing based on avg event size

### v0.20.1 - Store Schedules & Calendar
- Store schedules schema, admin UI for schedule management
- Weekly calendar view with schedule/all stores toggle
- Store modal mini map, Mapbox geocoding

### v0.20.0 - Public Submissions & OCR
- Public "Upload Results" tab with screenshot-based submission
- Google Cloud Vision OCR, player pre-matching, image previews

### v0.19.0 - Content Pages & UI Polish
- About, FAQ, For Organizers content pages
- Footer navigation, seamless app frame
- Open Graph meta tags, favicon, GA4 tracking

### v0.18.x - Code Cleanup & Server Extraction
- Extracted server logic into modular files (82% reduction in app.R)
- Reactive value cleanup, CSS cleanup, ARCHITECTURE.md

### v0.17.0 and earlier
- Admin UX improvements, DigiLab rebranding, rating system
- Mobile UI polish, desktop design overhaul, modal stat boxes

*See CHANGELOG.md for full version history.*

---

## References

- **Bug Documentation:** `docs/solutions/`
- **Design Documents:** `docs/plans/`
- **Development Log:** `logs/dev_log.md`
- **SVG Assets:** `docs/digimon-mascots.md` — placement tracking, future commission spec, art style guidelines
- **User Feedback:** [Google Sheet](https://docs.google.com/spreadsheets/d/11ZeL7yZo7ee4rIdbGCCLvx_Om2VtvXtcj4U6WmH4bS8/edit?gid=0#gid=0)
