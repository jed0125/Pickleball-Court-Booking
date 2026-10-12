-- migration_phase4_admin_dashboard.sql
-- Phase 4: Admin dashboard unread tracking
-- Run this in the Supabase SQL Editor after migration_phase3.sql

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS last_seen_by_admin TIMESTAMPTZ;

-- Optional: default recent admin view for existing rows
UPDATE bookings
SET last_seen_by_admin = NOW()
WHERE last_seen_by_admin IS NULL;

-- Helpful index for admin review checks
CREATE INDEX IF NOT EXISTS idx_bookings_last_seen_by_admin
  ON bookings (last_seen_by_admin);
