-- Migration: Add slug column to players table for efficient deep-link lookups
-- Date: 2026-03-15

ALTER TABLE players ADD COLUMN IF NOT EXISTS slug VARCHAR;
CREATE INDEX IF NOT EXISTS idx_players_slug ON players(slug) WHERE is_active = TRUE;

UPDATE players SET slug = LOWER(REGEXP_REPLACE(TRIM(display_name), '[^a-zA-Z0-9]+', '-', 'g'))
WHERE is_active = TRUE AND slug IS NULL;
