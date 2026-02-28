# Error Reporting Webhook Design

**Goal:** Replace the existing static "Report Error" buttons across the app with webhook-powered modals that send reports directly to Discord channels.

**Architecture:** Two webhook flows — contextual data error reports routed to scene coordination threads, and general bug reports posted to a #bug-reports Forum channel. Fire-and-forget pattern matching the existing store request webhook.

## Webhook Bot Names

| Bot Name | Channel | Purpose |
|----------|---------|---------|
| **Tentomon** | `#bug-reports` Forum | General bug/app error reports |
| **Gatomon** | `#scene-coordination` threads | Data error reports + store requests (existing) |
| **Veemon** | `#scene-requests` Forum | New scene/community requests (existing) |

## Flow 1: Data Error Reports (Contextual)

**Trigger:** Replace existing "Report Error" buttons on player, tournament, and deck meta modals with new webhook-powered buttons.

**Current state:** Player, tournament, and deck meta modals have large `btn-outline-secondary` anchor tags linking to Discord. These are removed and replaced.

**New behavior:**
1. User clicks a smaller, styled "Report Error" button in modal footer
2. A data error report modal opens, pre-filled with context:
   - Item type (Player / Tournament / Deck)
   - Item name (player name, tournament name, deck name)
   - Scene context (from active scene selection)
3. User describes the error in a free-text field
4. Optional: Discord username for follow-up
5. Submit → webhook fires to scene coordination thread via `discord_post_to_scene()`
6. User sees success notification
7. If no scene thread available, falls back to `#bug-reports` Forum

**Discord message format (Gatomon bot):**
```
**Data Error Report**
**Type:** Player
**Item:** PlayerName123
**Scene:** DFW
**Description:** Their deck from the Jan 15 tournament should be Blue Flare, not Jesmon
**Discord:** @username
**Submitted:** 02/27/2026 6:48 PM CT
*Submitted via DigiLab*
```

## Flow 2: General Bug Reports (Global)

**Trigger:**
- New "Report a Bug" link in the app footer (between "For Organizers" and GitHub icon)
- For Organizers page "Report an Error" section
- FAQ page "I found a bug" section

**Behavior:**
1. User clicks trigger → bug report modal opens
2. Fields: Title, Description, optional Discord username
3. Auto-attached context: current tab, active scene (not shown to user, sent in webhook)
4. Submit → webhook creates new Forum post in `#bug-reports` with "New" tag via `discord_post_bug_report()`
5. User sees success notification

**Discord message format (Tentomon bot):**
```
Thread title: "Bug: [user-provided title]"

**Description:** [user-provided description]
**Context:** Tab: Players, Scene: DFW
**Discord:** @username
**Submitted:** 02/27/2026 6:48 PM CT
*Submitted via DigiLab*
```

## New Environment Variables

```
DISCORD_WEBHOOK_BUG_REPORTS=     # Webhook URL for #bug-reports Forum
DISCORD_TAG_NEW_BUG=             # Forum tag ID for "New" tag
```

Existing env vars reused:
- `DISCORD_WEBHOOK_SCENE_COORDINATION` — already used by store request flow (Gatomon)
- `DISCORD_WEBHOOK_SCENE_REQUESTS` — already used by scene request flow (Veemon)

## New Functions in `R/discord_webhook.R`

### `discord_post_data_error(scene_id, item_type, item_name, description, discord_username, db_pool)`
- Routes to scene's coordination thread via existing `discord_send()` with `thread_id`
- Falls back to `discord_post_bug_report()` if scene has no thread

### `discord_post_bug_report(title, description, context, discord_username)`
- Creates new Forum post in `#bug-reports`
- Applies "New" tag via `DISCORD_TAG_NEW_BUG`
- Thread name: `"Bug: {title}"`

## Files Modified

| File | Change |
|------|--------|
| `R/discord_webhook.R` | Add `discord_post_data_error()` and `discord_post_bug_report()` |
| `server/public-players-server.R` | Replace "Report Error" button with modal trigger, add modal + handler |
| `server/public-tournaments-server.R` | Replace "Report Error" button with modal trigger, add modal + handler |
| `server/public-meta-server.R` | Replace "Report Error" button with modal trigger, add modal + handler |
| `app.R` | Add "Report a Bug" footer link + bug report modal UI |
| `server/shared-server.R` | Add bug report modal handler (shared across pages) |
| `views/for-tos-ui.R` | Update "Report an Error" section to trigger bug report modal |
| `views/faq-ui.R` | Update "I found a bug" section to trigger bug report modal |
| `.env.example` | Add `DISCORD_WEBHOOK_BUG_REPORTS` and `DISCORD_TAG_NEW_BUG` |

## What's NOT Included

- No database table for feedback (fire-and-forget to Discord, matching store requests)
- No admin feedback queue (future roadmap item FB2)
- No auto-attached browser/device info (YAGNI for now)
- No store modal changes (Report Error already removed, store request webhook handles that tab)
