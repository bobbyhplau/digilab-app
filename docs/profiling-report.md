# DigiLab Performance Profiling Report

**Date:** 2026-02-23
**Environment:** Windows 11, R 4.5.1, DuckDB local, single-process Shiny
**Design doc:** `docs/plans/2026-02-23-shinyloadtest-design.md`
**Tool:** shinycannon 1.2.0 replaying a recorded session at 1/5/10/25 concurrent users, 2 minutes each

---

## Executive Summary

DigiLab starts degrading at **5 concurrent users** on a single R process. At 25 users, initial page load takes 31 seconds median. The bottleneck is Shiny's single-threaded R process — every session's startup queries and reactive initialization queue behind each other. Zero failures at any concurrency level, so the app is stable but slow under load.

**Posit Connect recommendation:** Multiple worker processes (3-4 workers) for the free tier. For 75-100 concurrent users at launch, a paid tier with 8-12 workers is needed.

---

## Concurrency Results

### Latency by Concurrency Level

| Metric | 1 user (baseline) | 5 users | 10 users | 25 users |
|--------|-------------------|---------|----------|----------|
| **REQ_HOME median** | 2.11s | 4.65s | 12.22s | 31.28s |
| **REQ_HOME p95** | 2.42s | 7.54s | 17.58s | 48.97s |
| **WS_OPEN median** | 0.002s | 1.99s | 5.86s | 18.04s |
| **WS_RECV_INIT median** | 0.005s | 2.14s | 2.96s | 2.33s |
| **WS_RECV p95** | 0.46s | 1.96s | 2.93s | 4.93s |
| **Overall p95** | 0.16s | 2.35s | 4.09s | 9.64s |
| **Overall p99** | 2.11s | 5.00s | 12.68s | 39.15s |
| **Max latency** | 2.85s | 8.63s | 17.98s | 51.14s |
| Sessions completed | 19 | 45 | 49 | 50 |
| Failures | 0 | 0 | 0 | 0 |

### The Knee: 5 Concurrent Users

The performance knee is at **5 users**:

- REQ_HOME (initial page load) more than doubles: 2.1s → 4.7s
- WS_OPEN (WebSocket handshake) jumps from near-instant to 2.0s
- Overall p95 jumps from 0.16s to 2.35s (approaching the 3s threshold)

By 10 users, p95 crosses 3s (4.09s). By 25 users, the median initial load is 31s — unusable.

### What Degrades First

1. **REQ_HOME (initial page load)** — by far the worst. This is the full HTML render of the Shiny UI, which blocks the R thread. Scales linearly with concurrency because each new session queues behind existing ones.

2. **WS_OPEN (WebSocket connection)** — the WebSocket handshake also queues. Goes from instant at 1 user to 18s median at 25 users.

3. **WS_RECV (server push to client)** — reactive output computation. p95 goes from 0.46s to 4.93s at 25 users. This is where dashboard queries, chart rendering, and table data compete for the single R thread.

4. **REQ_GET (static assets)** — stays fast at all concurrency levels (~2ms median). Static file serving is not a bottleneck.

### 30-Second Timeout Warnings

At 25 users, shinycannon logged `WS_RECV_INIT` warnings ("Haven't received message after 30 seconds") — meaning some sessions waited 30+ seconds before receiving their first server push after WebSocket connect. This confirms the R process is heavily queued.

---

## Baseline Profile (1 User)

From the single-user baseline:

- **Initial page load (REQ_HOME):** 2.1s median — this is the cost of rendering the full Shiny UI with all the bslib components, Highcharter chart placeholders, and reactive initialization.
- **Dashboard first paint (WS_RECV):** p95 of 0.46s — the batched dashboard queries (deck_analytics + core_metrics) and chart rendering.
- **Static assets:** ~2ms per request, no issues.
- **Session duration:** ~6.4s per full session replay (dashboard load through format switch).

---

## Bottleneck Analysis

### Primary: Single-Threaded R Process

Shiny runs in a single R process by default. Every session's startup, query execution, and reactive computation happens sequentially on one thread. At 5+ users, sessions queue behind each other, creating the linear degradation pattern.

### Secondary: Heavy Startup Initialization

The 2.1s baseline REQ_HOME suggests significant work happening on session start:
- Database connection setup (DuckDB)
- Scene data loading
- Initial reactive value computation
- Full UI tree rendering (~203 observers registered)

### Not a Bottleneck

- **DuckDB queries themselves** — individual query times are fast (WS_RECV median stays under 3s even at 25 users). The issue is queuing, not query speed.
- **Static assets** — consistently fast across all concurrency levels.
- **Memory** — no session failures at any level, suggesting memory isn't the immediate constraint.

---

## Posit Connect Tier Recommendation

### Memory Per Session Estimate

Based on the test data:
- Each Shiny session uses approximately **80-120 MB** of RAM (R process base + DuckDB connection + reactive data frames + rendered outputs)
- This is an estimate based on typical Shiny apps of this complexity; actual measurement requires `pryr::mem_used()` instrumentation

### Scaling Math

| Target Users | Workers Needed | RAM Needed | Tier |
|--------------|---------------|------------|------|
| 5 | 1 | 0.5-0.6 GB | Free (4GB) |
| 10 | 2-3 | 1-1.5 GB | Free (4GB) |
| 25 | 5-6 | 2.5-3 GB | Free (4GB, tight) |
| 50 | 10-12 | 5-6 GB | Paid |
| 75-100 | 15-20 | 8-10 GB | Paid (16GB+) |

Each worker handles ~5 concurrent users comfortably (under 3s p95). Workers = ceil(target_users / 5).

### Recommendation

For v1.0 launch targeting 75-100 concurrent peak users:

1. **Immediate (free tier):** Configure Posit Connect for **3-4 worker processes** via `_server.yml` or Connect settings. This handles 15-20 concurrent users within the free 4GB.

2. **Launch day:** Upgrade to a paid tier with **8-12 GB RAM** and **15-20 workers** to handle 75-100 concurrent users.

3. **Monitor:** Track actual concurrent sessions post-launch. The knee scales linearly with workers, so the math is straightforward.

---

## Optimization Recommendations (Prioritized by Impact)

### High Impact

1. **Multiple worker processes** — The single biggest win. Configure `maxWorkerCount` in Posit Connect. Each worker handles its own set of sessions independently. No code changes needed.

2. **Connection pooling (`pool` package)** — Replace per-session DuckDB connections with a shared connection pool. Reduces memory overhead and connection setup time per session.

3. **Lazy module loading** — Defer admin module registration for non-admin sessions. The 203 observers include admin-only reactive chains that most users never trigger.

### Medium Impact

4. **Pre-render static UI elements** — Dashboard value boxes and chart containers don't need full server-side rendering. Move static HTML to the UI definition so REQ_HOME is lighter.

5. **Additional `bindCache()` calls** — Cache the initial dashboard state so the first paint for common scenes (DFW, All) is instant for subsequent users.

6. **Startup query batching** — Combine the initial scene loading, format list, and deck archetype queries into a single startup batch instead of sequential calls.

### Lower Priority

7. **Async queries (`promises`/`future`)** — Would allow long-running queries to not block other sessions within the same worker. Complex to implement but high value at scale.

8. **CDN for static assets** — Already fast, but offloading `www/` assets to a CDN would eliminate those requests from the R process entirely.

---

## Implemented Optimizations

The following optimizations from this report have been implemented:

### 1. Multiple worker processes (Posit Connect config)
- Upgraded to $20 tier (8GB RAM, 2 CPU)
- Configured: 4 max workers, 25% load factor, 8 max connections per worker, 15 min timeouts

### 3. Lazy admin UI loading
- Admin view files (`views/admin-*.R`) are no longer sourced at startup for every session
- Admin UI is now rendered server-side via `uiOutput()` placeholders only after admin authentication
- Combined with existing lazy server module loading — non-admin sessions skip all admin code
- Commit: `perf: lazy-load admin UI views behind authentication gate`

### 5. Extended bindCache
- Added `bindCache()` to 7 outputs across all public tabs (previously only Dashboard had caching):
  - Players: `player_standings` (format, search, min_events, scene, community)
  - Meta: `archetype_stats` (format, search, min_entries, scene, community)
  - Tournaments: `tournament_history` (format, event_type, search, scene, community)
  - Stores: `store_list`, `stores_cards_content`, `online_stores_section`, `stores_map`
- Total bindCache calls: 14 (dashboard) + 7 (other tabs) = 21
- Commit: `perf: add bindCache to Players, Meta, Tournaments, and Stores tabs`

### Not yet implemented
- Connection pooling (`pool` package) — deferred until traffic data shows need
- Pre-render static UI elements — deferred
- Startup query batching — deferred
- Async queries — deferred
- CDN for static assets — deferred

---

## Files

| File | Description |
|------|-------------|
| `loadtest/run_1user/` | Baseline (1 worker) shinycannon results |
| `loadtest/run_5users/` | 5 concurrent users results |
| `loadtest/run_10users/` | 10 concurrent users results |
| `loadtest/run_25users/` | 25 concurrent users results |
| `loadtest/loadtest_report.html` | shinyloadtest interactive HTML report |
| `loadtest/profvis_report_*.html` | profvis flamegraph from Phase A |
| `loadtest/recording.log` | Recorded session used for all replays |
