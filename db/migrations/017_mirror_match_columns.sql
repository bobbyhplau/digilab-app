-- Migration 017: Archetype Matchups MV
-- Reverts mv_archetype_store_stats to its original form (removes mirror columns)
-- and creates mv_archetype_matchups for head-to-head archetype win rates.
--
-- Run via: source("scripts/run_migration_017.R")

-- =============================================================================
-- Step 1: Revert mv_archetype_store_stats to original (no mirror columns)
-- =============================================================================
DROP MATERIALIZED VIEW IF EXISTS mv_archetype_store_stats;

CREATE MATERIALIZED VIEW mv_archetype_store_stats AS
SELECT
  da.archetype_id,
  da.archetype_name,
  da.primary_color,
  da.secondary_color,
  da.display_card_id,
  da.is_multi_color,
  s.store_id,
  s.slug,
  s.scene_id,
  s.is_online,
  sc.country,
  sc.state_region,
  t.format,
  t.event_type,
  date_trunc('week', t.event_date)::date as week_start,
  COUNT(r.result_id) as entries,
  COUNT(CASE WHEN r.placement = 1 THEN 1 END) as firsts,
  COUNT(CASE WHEN r.placement <= 3 THEN 1 END) as top3s,
  SUM(r.wins) as total_wins,
  SUM(r.losses) as total_losses,
  COUNT(DISTINCT r.player_id) as pilots,
  COUNT(DISTINCT r.tournament_id) as tournaments
FROM deck_archetypes da
JOIN results r ON da.archetype_id = r.archetype_id
JOIN tournaments t ON r.tournament_id = t.tournament_id
JOIN stores s ON t.store_id = s.store_id
JOIN scenes sc ON s.scene_id = sc.scene_id
WHERE da.is_active = TRUE AND da.archetype_name != 'UNKNOWN'
GROUP BY da.archetype_id, da.archetype_name, da.primary_color, da.secondary_color,
         da.display_card_id, da.is_multi_color,
         s.store_id, s.slug, s.scene_id, s.is_online, sc.country, sc.state_region,
         t.format, t.event_type, date_trunc('week', t.event_date);

CREATE UNIQUE INDEX ON mv_archetype_store_stats
  (archetype_id, store_id, COALESCE(format, '__null__'), event_type, week_start);

CREATE INDEX idx_mv_arch_scene ON mv_archetype_store_stats (scene_id);
CREATE INDEX idx_mv_arch_format ON mv_archetype_store_stats (format);
CREATE INDEX idx_mv_arch_online ON mv_archetype_store_stats (is_online) WHERE is_online = TRUE;

-- =============================================================================
-- Step 2: Create mv_archetype_matchups
-- Grain: (archetype_id, opponent_archetype_id, format)
-- Used by: Meta tab ("vs Top Win %" column)
-- =============================================================================
DROP MATERIALIZED VIEW IF EXISTS mv_archetype_matchups;

CREATE MATERIALIZED VIEW mv_archetype_matchups AS
SELECT
  r1.archetype_id,
  r2.archetype_id AS opponent_archetype_id,
  t.format,
  SUM(CASE WHEN m.match_points = 3 THEN 1 ELSE 0 END) AS wins,
  SUM(CASE WHEN m.match_points = 0 THEN 1 ELSE 0 END) AS losses
FROM matches m
JOIN results r1 ON r1.tournament_id = m.tournament_id AND r1.player_id = m.player_id
JOIN results r2 ON r2.tournament_id = m.tournament_id AND r2.player_id = m.opponent_id
JOIN tournaments t ON t.tournament_id = m.tournament_id
WHERE r1.archetype_id IS NOT NULL AND r2.archetype_id IS NOT NULL
  AND m.match_points IN (0, 3)
GROUP BY r1.archetype_id, r2.archetype_id, t.format;

CREATE UNIQUE INDEX ON mv_archetype_matchups
  (archetype_id, opponent_archetype_id, COALESCE(format, '__null__'));

CREATE INDEX idx_mv_matchup_opponent ON mv_archetype_matchups (opponent_archetype_id);
CREATE INDEX idx_mv_matchup_format ON mv_archetype_matchups (format);
