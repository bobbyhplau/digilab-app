# Limitless Expansion: DigiGalaxy + Historical Format Backfill

**Date:** 2026-03-27
**Status:** Approved
**Scope:** Add DigiGalaxy as Tier 1 organizer, extend sync floor to RSB2.0 (Nov 2024) for all organizers, write classification rules for older-format decklists

---

## Summary

Expand the Limitless TCG sync to:
1. Add **DigiGalaxy** (organizer 1009) as a new Tier 1 online organizer
2. Move the sync floor from BT23 (~Oct 2025) to **RSB2.0 (Nov 2024)** for all organizers
3. Proactively write deck classification rules for older-format archetypes before syncing

DigiGalaxy has committed to collecting decklists going forward; historical tournaments will have UNKNOWN archetypes. Existing organizers' older tournaments have decklists that need new classification rules for pre-BT23 meta.

## Background

### Why Now
- DigiGalaxy has committed to collecting decklists from players going forward
- Players have requested older format data — Limitless organizers have tournaments going back well before BT23
- BT2.0 / RSB2.0 (global unification, Nov 2024) is a natural cutoff — consistent format numbering and card pool. Note: "BT2.0" is the community shorthand for the global unification era; the actual format_id in our DB is `RSB2.0`

### Current State
- **5 Tier 1 organizers** synced: Eagle's Nest (452), PHOENIX REBORN (281), DMV Drakes (559), MasterRukasu (578), Expanse Italia (2536)
- **180 tournaments** synced, all from BT23 era (~Oct 2025) onward
- **104 mapped Limitless deck IDs** in `limitless_deck_map`
- **~130 classification rules** in `classify_decklists.py` (BT23+ meta)

### DigiGalaxy Data (from Limitless API)
- **Organizer ID:** 1009
- **Total tournaments on Limitless:** 75 (since June 2023)
- **RSB2.0+ tournaments (Nov 2024+):** ~20
- **Decklists:** None (format field = null for all tournaments)
- **Player counts:** 4-24, averaging ~9-10
- **Tournament naming:** No format codes in names from Feb 2025 onward; date-based format inference required

### Format Records Added
Five historical formats added to the `formats` table (2026-03-27):

| Format ID | Set Name | Release Date | Active |
|-----------|----------|-------------|--------|
| RSB2.0 | Release Special Booster 2.0 | 2024-11-01 | Yes |
| RSB2.5 | Release Special Booster 2.5 | 2025-02-28 | Yes |
| BT21 | World Convergence | 2025-04-25 | Yes |
| EX09 | Versus Monsters | 2025-06-26 | Yes |
| BT22 | Cyber Eden | 2025-07-25 | Yes |

These bridge the gap between the RSB2.0 cutoff and the existing BT23+ records. No pre-RSB2.0 format records (BT17, BT18, EX07, etc.) should be added — the sync floor prevents those tournaments from being imported, and adding them could break date-based format inference for backfilled tournaments.

---

## Design

### Phase 1: Add DigiGalaxy + Sync

**1a. Create online store record**

```sql
INSERT INTO stores (name, slug, is_online, limitless_organizer_id, scene_id)
VALUES ('DigiGalaxy', 'digigalaxy', TRUE, 1009,
        (SELECT scene_id FROM scenes WHERE slug = 'online'));
```

Link to Online scene (same as other Limitless organizers).

**1b. Sync script changes**

Modify `TIER1_ORGANIZERS` config to support per-organizer settings:

```python
TIER1_ORGANIZERS = {
    452:  {"name": "Eagle's Nest",     "skip_deck_check": False},
    281:  {"name": "PHOENIX REBORN",   "skip_deck_check": False},
    559:  {"name": "DMV Drakes",       "skip_deck_check": False},
    578:  {"name": "MasterRukasu",     "skip_deck_check": False},
    2536: {"name": "Expanse Italia",   "skip_deck_check": False},
    1009: {"name": "DigiGalaxy",       "skip_deck_check": True},
}
```

**Breaking change:** This restructures `TIER1_ORGANIZERS` from `{id: "name"}` to `{id: {"name": ..., "skip_deck_check": ...}}`. All call sites that access the dict as a string must be updated:
- `sync_organizer()`: reads `TIER1_ORGANIZERS[id]["name"]` for display
- `sync_tournament()`: receives new `skip_deck_check` parameter threaded from `sync_organizer()`
- Docstring/argparse help text: update organizer list to include all 6 orgs

Thread `skip_deck_check` through the call chain:

```python
# In sync_organizer():
org_config = TIER1_ORGANIZERS.get(organizer_id, {"name": f"Organizer {organizer_id}", "skip_deck_check": False})
org_name = org_config["name"]
skip_deck_check = org_config["skip_deck_check"]
# ... pass skip_deck_check to sync_tournament()

# In sync_tournament(cursor, tournament, organizer_id, store_id, dry_run=False, skip_deck_check=False):
if not skip_deck_check and standings:
    top_3 = [s for s in standings if s.get("placing") and s["placing"] <= 3]
    top_3_with_deck = sum(1 for s in top_3 if s.get("deck") and s["deck"].get("id"))
    if top_3 and top_3_with_deck == 0:
        print(f"      SKIPPED: No deck data for top 3 players")
        return None
```

**1c. Fix format inference regex validation** (prerequisite for Phase 2 backfill)

The regex path extracts format codes like "BT17" from tournament names, but pre-RSB2.0 format IDs (BT17, BT18, etc.) don't exist in our DB. This primarily affects Phase 2 backfill where older organizer tournaments contain old format codes in names. Add a DB validation after regex match:

```python
if match:
    candidate = f"BT{match.group(2)}" if match.group(1) else f"EX{match.group(4)}"
    cursor.execute("SELECT 1 FROM formats WHERE format_id = %s", (candidate,))
    if cursor.fetchone():
        return candidate
    # Fall through to date-based inference
```

This ensures tournament names containing old format codes (e.g., "BT17 Tournament") correctly fall through to date-based inference, which maps to RSB2.0/RSB2.5 based on the tournament date.

**1d. Run Phase 1 sync**

```bash
python scripts/sync_limitless.py --organizer 1009 --since 2024-11-01
```

- ~20 tournaments synced
- All results get `archetype_id = NULL` (UNKNOWN)
- Players matched by `limitless_username` or created as new

### Phase 2: Backfill Existing Organizers

**2a. Run backfill sync (without --classify)**

```bash
python scripts/sync_limitless.py --all-tier1 --since 2024-11-01
```

- Idempotency via `limitless_id` — already-synced tournaments (180) are skipped
- Estimated ~100-150 new tournaments across all orgs
- Existing orgs have decklists — deck coverage check still applies to them
- Unmapped deck IDs create entries with UNKNOWN archetype
- **No `--classify` flag** — classification deferred to Phase 3

**2b. Analyze new decklists**

After sync, analyze the newly inserted UNKNOWN results that have `decklist_json`:
- Extract unique card signatures from older-format decklists
- Identify archetypes that already match existing rules
- Identify new archetypes that need rules (pre-BT23 meta)

### Phase 3: Classification Rules + Cleanup

**3a. Write new classification rules**

Analyze unclassified decklists from Phase 2 and add rules to `classify_decklists.py` for older-format archetypes. Many existing rules may already cover older variants (e.g., Gallantmon + Guilmon + Growlmon is timeless), but format-specific archetypes from RSB2.0-BT22 era will need new entries.

**3b. Run classification**

```bash
python scripts/classify_decklists.py --dry-run  # Preview first
python scripts/classify_decklists.py             # Apply
```

**3c. Review deck_requests queue**

Anything the classifier can't handle goes to the admin deck_requests queue for manual review.

**3d. Refresh materialized views**

Note: The sync script automatically refreshes MVs after each run (Phases 1d and 2a handle this). This step is only needed after running `classify_decklists.py` separately, since that script does NOT refresh MVs.

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_player_store_stats;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_archetype_store_stats;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_tournament_list;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_dashboard_counts;
```

---

## What's NOT In Scope

- **Pre-RSB2.0 tournaments** — Only syncing Nov 2024+ (BT2.0 era)
- **New organizers beyond DigiGalaxy** — Future expansion follows existing design criteria
- **UI changes** — No new views or filters needed; existing format dropdowns and filters already support the new formats
- **Rating changes** — Ratings are already format-agnostic; backfilled tournaments feed the same Elo pool

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Rate limiting from Limitless API during large backfill | Sync script already respects rate limit headers; run during off-peak |
| Code changes not deployed before scheduled sync | All sync script changes (skip_deck_check, regex fix) MUST be merged before the next GitHub Actions cron run (Tue/Fri midnight UTC), or DigiGalaxy tournaments will be silently skipped |
| Old format regex mismatches (BT17 in name → no DB record) | Regex validation fix falls through to date-based inference |
| Classification rules miss older archetypes | Analyze decklists before classifying; manual deck_requests as fallback |
| DigiGalaxy tournaments with <4 players | Existing minimum player threshold filters these naturally |
| Duplicate players across DigiGalaxy and existing orgs | `limitless_username` matching handles this automatically |

---

## Estimated Impact

| Metric | Before | After |
|--------|--------|-------|
| Tier 1 organizers | 5 | 6 (+DigiGalaxy) |
| Synced tournaments | 180 | ~300-350 |
| Sync floor | BT23 (Oct 2025) | RSB2.0 (Nov 2024) |
| Format coverage | BT23-EX11 | RSB2.0-EX11 |
| Classification rules | ~130 | ~130 + new older-format rules |
