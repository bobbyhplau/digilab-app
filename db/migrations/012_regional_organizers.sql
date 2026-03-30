-- Migration 012: Rollback regional organizer columns (feature reverted)
-- Original migration added is_regional_organizer and venue_name; both dropped.

ALTER TABLE stores DROP COLUMN IF EXISTS is_regional_organizer;
ALTER TABLE tournaments DROP COLUMN IF EXISTS venue_name;
