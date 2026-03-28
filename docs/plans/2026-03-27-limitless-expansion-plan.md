# Limitless Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add DigiGalaxy as a Tier 1 Limitless organizer, extend the sync floor to RSB2.0 (Nov 2024) for all organizers, and write classification rules for older-format decklists.

**Architecture:** Modify `scripts/sync_limitless.py` to support per-organizer config (dict-of-dicts), add format regex validation against DB, thread `skip_deck_check` through the sync chain. Create DigiGalaxy store record in Neon. Run phased sync: DigiGalaxy first, then backfill all orgs, then analyze and classify decklists.

**Tech Stack:** Python (psycopg2, requests), PostgreSQL (Neon), Limitless TCG API

**Spec:** `docs/plans/2026-03-27-limitless-expansion-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `scripts/sync_limitless.py` | Modify | TIER1_ORGANIZERS restructure, skip_deck_check threading, regex validation fix, total_synced bug fix, docstring updates |
| `scripts/classify_decklists.py` | Modify (Phase 3) | Add classification rules for RSB2.0-BT22 era archetypes |

---

### Task 1: Restructure TIER1_ORGANIZERS config

**Files:**
- Modify: `scripts/sync_limitless.py:56-64` (config dict)
- Modify: `scripts/sync_limitless.py:1-33` (docstring)

- [ ] **Step 1: Update TIER1_ORGANIZERS from flat dict to dict-of-dicts**

In `scripts/sync_limitless.py`, replace lines 56-64:

```python
# Tier 1 organizers for --all-tier1 flag
# These are high-quality organizers with good deck coverage (50%+ decklists)
# skip_deck_check: True for organizers that don't track decklists on Limitless
TIER1_ORGANIZERS = {
    452:  {"name": "Eagle's Nest",     "skip_deck_check": False},
    281:  {"name": "PHOENIX REBORN",   "skip_deck_check": False},
    559:  {"name": "DMV Drakes",       "skip_deck_check": False},
    578:  {"name": "MasterRukasu",     "skip_deck_check": False},
    2536: {"name": "Expanse Italia",   "skip_deck_check": False},
    1009: {"name": "DigiGalaxy",       "skip_deck_check": True},
}
```

- [ ] **Step 2: Update docstring and argparse help text**

Replace line 20:
```python
    --all-tier1        Sync all Tier 1 organizers (452, 281, 559, 578, 2536, 1009)
```

Also update the argparse help string at line ~1461:
```python
    parser.add_argument("--all-tier1", action="store_true",
                        help="Sync all Tier 1 organizers (452, 281, 559, 578, 2536, 1009)")
```

- [ ] **Step 3: Update sync_organizer() to read from dict-of-dicts**

In `scripts/sync_limitless.py`, at line 771, replace:
```python
    organizer_name = TIER1_ORGANIZERS.get(organizer_id, f"Organizer {organizer_id}")
```
with:
```python
    org_config = TIER1_ORGANIZERS.get(organizer_id, {"name": f"Organizer {organizer_id}", "skip_deck_check": False})
    organizer_name = org_config["name"]
    skip_deck_check = org_config["skip_deck_check"]
```

- [ ] **Step 4: Thread skip_deck_check through to sync_tournament()**

At line 821, update the `sync_tournament` call in `sync_organizer()`:
```python
            result = sync_tournament(cursor, tournament, organizer_id, store_id, dry_run, skip_deck_check)
```

- [ ] **Step 5: Update sync_tournament() signature and deck check**

At line 404, update the function signature:
```python
def sync_tournament(cursor, tournament, organizer_id, store_id, dry_run=False, skip_deck_check=False):
```

Update the docstring (lines 405-413) to include:
```python
        skip_deck_check: If True, skip the deck coverage check (for organizers without decklists)
```

At lines 474-480, replace the deck coverage check:
```python
    # Check deck coverage — skip tournaments where top 3 have no deck data
    # (unless organizer has skip_deck_check enabled)
    if not skip_deck_check and standings:
        top_3 = [s for s in standings if s.get("placing") and s["placing"] <= 3]
        top_3_with_deck = sum(1 for s in top_3 if s.get("deck") and s["deck"].get("id"))
        if top_3 and top_3_with_deck == 0:
            print(f"      SKIPPED: No deck data for top 3 players (tournament doesn't track decks)")
            return None
```

- [ ] **Step 6: Fix total_synced bug in main()**

At line 1561, `total_synced` is referenced before it's defined (at line 1588). Move the summary computation ABOVE the MV refresh block. Replace lines 1560-1588:

```python
    # Compute summary stats (must happen before MV refresh check)
    total_synced = sum(s.get("tournaments_synced", 0) for s in all_stats)
    total_skipped = sum(s.get("tournaments_skipped", 0) for s in all_stats)
    total_results = sum(s.get("total_results", 0) for s in all_stats)
    total_matches = sum(s.get("total_matches", 0) for s in all_stats)
    total_players = sum(s.get("total_players_created", 0) for s in all_stats)
    total_decks = sum(s.get("total_deck_requests", 0) for s in all_stats)
    errors = [s for s in all_stats if "error" in s]

    # Refresh materialized views after sync
    if not args.dry_run and total_synced > 0:
```

Then remove the duplicate computation that was at lines 1588-1594.

- [ ] **Step 7: Verify script parses without errors**

Run:
```bash
python -c "import py_compile; py_compile.compile('scripts/sync_limitless.py', doraise=True)"
```
Expected: No errors.

- [ ] **Step 8: Commit**

```bash
git add scripts/sync_limitless.py
git commit -m "feat: add DigiGalaxy to TIER1_ORGANIZERS with skip_deck_check support"
```

---

### Task 2: Fix format inference regex validation

**Files:**
- Modify: `scripts/sync_limitless.py:228-262` (infer_format function)

- [ ] **Step 1: Add DB validation after regex match**

In `scripts/sync_limitless.py`, replace the `infer_format` function body (lines 242-262):

```python
    # Strategy 1: Parse from name
    match = re.search(r'(BT)-?(\d+)|(EX)-?(\d+)', tournament_name, re.IGNORECASE)
    if match:
        if match.group(1):  # BT match
            candidate = f"BT{match.group(2)}"
        else:  # EX match
            candidate = f"EX{match.group(4)}"
        # Validate format exists in DB before returning
        cursor.execute("SELECT 1 FROM formats WHERE format_id = %s", (candidate,))
        if cursor.fetchone():
            return candidate
        # Format not in DB — fall through to date-based inference
        print(f"      Note: '{candidate}' from name not in formats table, using date fallback")

    # Strategy 2: Date-based fallback
    try:
        cursor.execute("""
            SELECT format_id FROM formats
            WHERE release_date <= %s
            ORDER BY release_date DESC
            LIMIT 1
        """, (event_date,))
        result = cursor.fetchone()
        return result[0] if result else None
    except Exception as e:
        print(f"    Warning: Could not infer format from date: {e}")
        return None
```

- [ ] **Step 2: Verify script still parses**

Run:
```bash
python -c "import py_compile; py_compile.compile('scripts/sync_limitless.py', doraise=True)"
```
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/sync_limitless.py
git commit -m "fix: validate format regex matches against DB before returning"
```

---

### Task 3: Create DigiGalaxy store record

**Files:**
- None (database operation only)

- [ ] **Step 1: Verify Online scene exists and get scene_id**

Run:
```bash
python -c "
import psycopg2
from dotenv import load_dotenv
import os
load_dotenv()
conn = psycopg2.connect(host=os.getenv('NEON_HOST'), dbname=os.getenv('NEON_DATABASE'),
    user=os.getenv('NEON_USER'), password=os.getenv('NEON_PASSWORD'), sslmode='require')
cur = conn.cursor()
cur.execute(\"SELECT scene_id, name, slug FROM scenes WHERE slug = 'online'\")
print(cur.fetchone())
conn.close()
"
```
Expected: A row like `(N, 'Online', 'online')`.

- [ ] **Step 2: Verify no store already exists for organizer 1009**

Run:
```bash
python -c "
import psycopg2
from dotenv import load_dotenv
import os
load_dotenv()
conn = psycopg2.connect(host=os.getenv('NEON_HOST'), dbname=os.getenv('NEON_DATABASE'),
    user=os.getenv('NEON_USER'), password=os.getenv('NEON_PASSWORD'), sslmode='require')
cur = conn.cursor()
cur.execute(\"SELECT store_id, name FROM stores WHERE limitless_organizer_id = 1009\")
print(cur.fetchone())
conn.close()
"
```
Expected: `None` (no existing store).

- [ ] **Step 3: Insert DigiGalaxy store record**

Run:
```bash
python -c "
import psycopg2
from dotenv import load_dotenv
import os
load_dotenv()
conn = psycopg2.connect(host=os.getenv('NEON_HOST'), dbname=os.getenv('NEON_DATABASE'),
    user=os.getenv('NEON_USER'), password=os.getenv('NEON_PASSWORD'), sslmode='require')
cur = conn.cursor()
cur.execute('''
    INSERT INTO stores (name, slug, is_online, limitless_organizer_id, scene_id)
    VALUES ('DigiGalaxy', 'digigalaxy', TRUE, 1009,
            (SELECT scene_id FROM scenes WHERE slug = %s))
    RETURNING store_id, name
''', ('online',))
result = cur.fetchone()
conn.commit()
print(f'Created store: id={result[0]}, name={result[1]}')
conn.close()
"
```
Expected: `Created store: id=N, name=DigiGalaxy`.

- [ ] **Step 4: Verify store was created correctly**

Run:
```bash
python -c "
import psycopg2
from dotenv import load_dotenv
import os
load_dotenv()
conn = psycopg2.connect(host=os.getenv('NEON_HOST'), dbname=os.getenv('NEON_DATABASE'),
    user=os.getenv('NEON_USER'), password=os.getenv('NEON_PASSWORD'), sslmode='require')
cur = conn.cursor()
cur.execute('''SELECT store_id, name, slug, is_online, limitless_organizer_id, scene_id
               FROM stores WHERE limitless_organizer_id = 1009''')
row = cur.fetchone()
print(f'store_id={row[0]}, name={row[1]}, slug={row[2]}, is_online={row[3]}, org_id={row[4]}, scene_id={row[5]}')
conn.close()
"
```
Expected: All fields correct, `is_online=True`, `limitless_organizer_id=1009`.

---

### Task 4: Phase 1 sync — DigiGalaxy

**Files:**
- None (runs existing sync script with new config)

**Prerequisites:** Tasks 1, 2, and 3 must be complete.

- [ ] **Step 1: Dry run DigiGalaxy sync**

Run:
```bash
cd "E:/Michael Lopez/Projects/repos/digilab-app"
python scripts/sync_limitless.py --organizer 1009 --since 2024-11-01 --dry-run
```
Expected: Lists ~20 tournaments that would be synced. Verify format inference assigns RSB2.0/RSB2.5/BT21/EX09/BT22/EX10/BT23/BT24/EX11 based on tournament dates. No errors.

- [ ] **Step 2: Run actual DigiGalaxy sync**

Run:
```bash
python scripts/sync_limitless.py --organizer 1009 --since 2024-11-01
```
Expected: ~20 tournaments synced, all results with UNKNOWN archetype. Players created or matched. MVs refreshed automatically.

- [ ] **Step 3: Verify synced data**

Run:
```bash
python -c "
import psycopg2
from dotenv import load_dotenv
import os
load_dotenv()
conn = psycopg2.connect(host=os.getenv('NEON_HOST'), dbname=os.getenv('NEON_DATABASE'),
    user=os.getenv('NEON_USER'), password=os.getenv('NEON_PASSWORD'), sslmode='require')
cur = conn.cursor()
cur.execute('''
    SELECT t.format, COUNT(*) as tournaments, SUM(t.player_count) as total_players
    FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE s.limitless_organizer_id = 1009
    GROUP BY t.format ORDER BY t.format
''')
for row in cur.fetchall():
    print(f'Format: {row[0]}, Tournaments: {row[1]}, Players: {row[2]}')
cur.execute('''
    SELECT COUNT(*) FROM tournaments t JOIN stores s ON t.store_id = s.store_id
    WHERE s.limitless_organizer_id = 1009
''')
print(f'Total DigiGalaxy tournaments: {cur.fetchone()[0]}')
conn.close()
"
```
Expected: Tournaments distributed across RSB2.0+ formats. No NULL formats.

---

### Task 5: Phase 2 sync — Backfill all Tier 1 organizers

**Files:**
- None (runs existing sync script)

**Prerequisites:** Task 4 must be complete.

- [ ] **Step 1: Dry run backfill**

Run:
```bash
python scripts/sync_limitless.py --all-tier1 --since 2024-11-01 --dry-run
```
Expected: Shows already-synced tournaments being skipped (180+), and ~100-150 new tournaments to sync. DigiGalaxy's already-synced tournaments also skipped. Format inference uses date-based fallback for old tournament names with BT17/EX07/etc.

- [ ] **Step 2: Run actual backfill (without --classify)**

Run:
```bash
python scripts/sync_limitless.py --all-tier1 --since 2024-11-01
```
Expected: ~100-150 new tournaments synced. New deck IDs from older formats create UNKNOWN results. MVs refreshed automatically. Note: this will take a while due to API rate limiting (~1.5s per request).

- [ ] **Step 3: Verify backfill results**

Run:
```bash
python -c "
import psycopg2
from dotenv import load_dotenv
import os
load_dotenv()
conn = psycopg2.connect(host=os.getenv('NEON_HOST'), dbname=os.getenv('NEON_DATABASE'),
    user=os.getenv('NEON_USER'), password=os.getenv('NEON_PASSWORD'), sslmode='require')
cur = conn.cursor()
# Tournament counts by organizer
cur.execute('''
    SELECT s.name, s.limitless_organizer_id, COUNT(*) as count,
           MIN(t.event_date) as earliest, MAX(t.event_date) as latest
    FROM tournaments t JOIN stores s ON t.store_id = s.store_id
    WHERE t.limitless_id IS NOT NULL
    GROUP BY s.name, s.limitless_organizer_id ORDER BY s.name
''')
print('Synced tournaments by organizer:')
for r in cur.fetchall():
    print(f'  {r[0]} ({r[1]}): {r[2]} tournaments, {r[3]} to {r[4]}')

# Format distribution
cur.execute('''
    SELECT t.format, COUNT(*) FROM tournaments t
    WHERE t.limitless_id IS NOT NULL
    GROUP BY t.format ORDER BY t.format
''')
print('\nFormat distribution:')
for r in cur.fetchall():
    print(f'  {r[0]}: {r[1]}')

# UNKNOWN results with decklists (candidates for classification)
cur.execute('''
    SELECT COUNT(*) FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    WHERE t.limitless_id IS NOT NULL
      AND r.archetype_id = 50
      AND r.decklist_json IS NOT NULL
''')
print(f'\nUNKNOWN results with decklists (to classify): {cur.fetchone()[0]}')
conn.close()
"
```
Expected: All organizers now have tournaments back to Nov 2024. New formats (RSB2.0, RSB2.5, BT21, EX09, BT22) appear in distribution.

---

### Task 6: Analyze unclassified decklists from older formats

**Files:**
- None (analysis only — informs Task 7)

**Prerequisites:** Task 5 must be complete.

- [ ] **Step 1: Extract unique card signatures from unclassified decklists**

Run:
```bash
python -c "
import psycopg2, json
from collections import Counter
from dotenv import load_dotenv
import os
load_dotenv()
conn = psycopg2.connect(host=os.getenv('NEON_HOST'), dbname=os.getenv('NEON_DATABASE'),
    user=os.getenv('NEON_USER'), password=os.getenv('NEON_PASSWORD'), sslmode='require')
cur = conn.cursor()

# Get UNKNOWN results with decklists from newly backfilled tournaments
cur.execute('''
    SELECT r.result_id, r.decklist_json, t.format, t.event_date
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    WHERE t.limitless_id IS NOT NULL
      AND r.archetype_id = 50
      AND r.decklist_json IS NOT NULL
    ORDER BY t.event_date
''')
rows = cur.fetchall()
print(f'Total UNKNOWN decklists to analyze: {len(rows)}')

# Group by format
by_format = {}
for result_id, decklist_json, fmt, event_date in rows:
    by_format.setdefault(fmt, []).append((result_id, decklist_json))

for fmt, decklists in sorted(by_format.items()):
    print(f'\n=== {fmt} ({len(decklists)} decklists) ===')
    # Extract most common mega/ultimate level cards across decklists
    card_counter = Counter()
    for _, dj in decklists:
        try:
            dl = json.loads(dj)
            for card in dl:
                name = card.get('card', {}).get('name', card.get('name', ''))
                if name:
                    card_counter[name] += 1
        except:
            pass
    # Show top 20 cards for each format
    for card, count in card_counter.most_common(20):
        pct = count / len(decklists) * 100
        print(f'  {card}: {count}/{len(decklists)} ({pct:.0f}%)')

conn.close()
"
```
Expected: Card frequency data grouped by format, showing which archetypes are present in older formats.

- [ ] **Step 2: Test existing classification rules against older decklists**

Run:
```bash
python -c "
import psycopg2, json, sys
sys.path.insert(0, 'scripts')
from classify_decklists import CLASSIFICATION_RULES, classify_decklist
from dotenv import load_dotenv
import os
load_dotenv()
conn = psycopg2.connect(host=os.getenv('NEON_HOST'), dbname=os.getenv('NEON_DATABASE'),
    user=os.getenv('NEON_USER'), password=os.getenv('NEON_PASSWORD'), sslmode='require')
cur = conn.cursor()

cur.execute('''
    SELECT r.result_id, r.decklist_json, t.format
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    WHERE t.limitless_id IS NOT NULL
      AND r.archetype_id = 50
      AND r.decklist_json IS NOT NULL
''')
rows = cur.fetchall()

classified = 0
unclassified = 0
archetype_counts = {}
unclassified_samples = []

for result_id, decklist_json, fmt in rows:
    archetype = classify_decklist(decklist_json)
    if archetype:
        classified += 1
        archetype_counts[archetype] = archetype_counts.get(archetype, 0) + 1
    else:
        unclassified += 1
        if len(unclassified_samples) < 10:
            try:
                dl = json.loads(decklist_json)
                cards = [c.get('card', {}).get('name', c.get('name', '')) for c in dl[:8]]
                unclassified_samples.append((result_id, fmt, cards))
            except:
                pass

print(f'Already classifiable: {classified}/{len(rows)}')
print(f'Need new rules: {unclassified}/{len(rows)}')
print(f'\nExisting rules that match:')
for arch, count in sorted(archetype_counts.items(), key=lambda x: -x[1]):
    print(f'  {arch}: {count}')
print(f'\nSample unclassified decklists (first 10):')
for rid, fmt, cards in unclassified_samples:
    print(f'  result_id={rid} ({fmt}): {cards}')

conn.close()
"
```
Expected: Shows how many existing rules already cover older decks, and samples of what needs new rules.

- [ ] **Step 3: Document findings**

Record the analysis output — which archetypes need new rules, which are already covered. This directly informs Task 7.

---

### Task 7: Write new classification rules for older formats

**Files:**
- Modify: `scripts/classify_decklists.py:53-421` (CLASSIFICATION_RULES list)

**Prerequisites:** Task 6 analysis must be complete.

- [ ] **Step 1: Add new classification rules based on analysis**

Based on Task 6's analysis output, add new rules to `CLASSIFICATION_RULES` in `scripts/classify_decklists.py`. Place them in the correct position (more specific before general). Rules follow the existing pattern:

```python
("Archetype Name", ["SignatureCard1", "SignatureCard2", "SignatureCard3"], min_matches),
```

Note: The exact rules depend on Task 6's analysis output. New archetypes may need corresponding entries in the `deck_archetypes` table if they don't already exist.

- [ ] **Step 2: Check if any new archetype names need DB entries**

For any new archetype names added to classification rules, verify they exist in `deck_archetypes`:

```bash
python -c "
import psycopg2
from dotenv import load_dotenv
import os
load_dotenv()
conn = psycopg2.connect(host=os.getenv('NEON_HOST'), dbname=os.getenv('NEON_DATABASE'),
    user=os.getenv('NEON_USER'), password=os.getenv('NEON_PASSWORD'), sslmode='require')
cur = conn.cursor()
cur.execute('SELECT archetype_name FROM deck_archetypes')
existing = {r[0] for r in cur.fetchall()}
# Compare against new rule names from Step 1
# new_names = ['ArchetypeA', 'ArchetypeB']  # fill in from Step 1
# missing = [n for n in new_names if n not in existing]
# print(f'Missing from DB: {missing}')
print(f'Existing archetypes: {len(existing)}')
for a in sorted(existing):
    print(f'  {a}')
conn.close()
"
```

If any new archetypes are missing, insert them into `deck_archetypes` before classification.

- [ ] **Step 3: Verify script still parses**

Run:
```bash
python -c "import py_compile; py_compile.compile('scripts/classify_decklists.py', doraise=True)"
```
Expected: No errors.

- [ ] **Step 4: Commit new rules**

```bash
git add scripts/classify_decklists.py
git commit -m "feat: add classification rules for RSB2.0-BT22 era archetypes"
```

---

### Task 8: Run classification and refresh views

**Files:**
- None (runs existing scripts)

**Prerequisites:** Task 7 must be complete.

- [ ] **Step 1: Dry run classification**

Run:
```bash
python scripts/classify_decklists.py --dry-run
```
Expected: Shows how many decklists would be classified, which archetypes, and any that remain unclassified.

- [ ] **Step 2: Run classification**

Run:
```bash
python scripts/classify_decklists.py
```
Expected: Decklists classified and updated in results table.

- [ ] **Step 3: Refresh materialized views**

Run:
```bash
python -c "
import psycopg2
from dotenv import load_dotenv
import os
load_dotenv()
conn = psycopg2.connect(host=os.getenv('NEON_HOST'), dbname=os.getenv('NEON_DATABASE'),
    user=os.getenv('NEON_USER'), password=os.getenv('NEON_PASSWORD'), sslmode='require')
cur = conn.cursor()
views = ['mv_player_store_stats', 'mv_archetype_store_stats', 'mv_tournament_list', 'mv_store_summary', 'mv_dashboard_counts']
for mv in views:
    print(f'Refreshing {mv}...')
    cur.execute(f'REFRESH MATERIALIZED VIEW {mv}')
    conn.commit()
    print(f'  Done')
conn.close()
print('All MVs refreshed.')
"
```
Expected: All materialized views refreshed successfully.

- [ ] **Step 4: Verify final state**

Run:
```bash
python -c "
import psycopg2
from dotenv import load_dotenv
import os
load_dotenv()
conn = psycopg2.connect(host=os.getenv('NEON_HOST'), dbname=os.getenv('NEON_DATABASE'),
    user=os.getenv('NEON_USER'), password=os.getenv('NEON_PASSWORD'), sslmode='require')
cur = conn.cursor()

# Total synced tournaments
cur.execute('SELECT COUNT(*) FROM tournaments WHERE limitless_id IS NOT NULL')
print(f'Total synced tournaments: {cur.fetchone()[0]}')

# By organizer
cur.execute('''
    SELECT s.name, COUNT(*) FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.limitless_id IS NOT NULL
    GROUP BY s.name ORDER BY s.name
''')
for r in cur.fetchall():
    print(f'  {r[0]}: {r[1]}')

# Remaining UNKNOWN with decklists
cur.execute('''
    SELECT COUNT(*) FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    WHERE t.limitless_id IS NOT NULL AND r.archetype_id = 50 AND r.decklist_json IS NOT NULL
''')
remaining = cur.fetchone()[0]
print(f'\nRemaining UNKNOWN with decklists: {remaining}')

# Pending deck requests
cur.execute(\"SELECT COUNT(*) FROM deck_requests WHERE status = 'pending'\")
print(f'Pending deck requests: {cur.fetchone()[0]}')

conn.close()
"
```
Expected: ~300-350 total tournaments, 6 organizers, reduced UNKNOWN count.

- [ ] **Step 5: Commit any remaining changes**

```bash
git add scripts/classify_decklists.py
git commit -m "feat: complete Limitless expansion - DigiGalaxy + RSB2.0 backfill"
```

---

## Task Dependencies

```
Task 1 (TIER1_ORGANIZERS + skip_deck_check + total_synced fix) ──┐
Task 2 (regex validation fix) ───────────────────────────────────┤
Task 3 (create DigiGalaxy store) ────────────────────────────────┘
        │
        └─→ Task 4 (Phase 1: DigiGalaxy sync)
              └─→ Task 5 (Phase 2: backfill all orgs)
                    └─→ Task 6 (analyze decklists)
                          └─→ Task 7 (write classification rules)
                                └─→ Task 8 (run classification + refresh)
```

Tasks 1, 2, and 3 are independent and can be parallelized (1 and 2 modify different parts of sync_limitless.py, 3 is a DB operation). Tasks 4-8 are sequential.

**Post-implementation:** After Task 8, review the admin deck_requests queue for any decklists the classifier couldn't handle. This is a manual admin step, not an automated task.

**Note on classify_decklists.py:** The script defaults to `--online-only` mode, which only classifies results from online stores. Since all Limitless organizers are online stores, this works for our use case.
