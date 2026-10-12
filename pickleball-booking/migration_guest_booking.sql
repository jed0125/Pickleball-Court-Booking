-- migration_guest_booking.sql
-- Phase 1: Guest Booking Rework
-- Run this in the Supabase SQL Editor

-- 1. Add guest fields to bookings table
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS guest_name TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS guest_phone TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS payment_method TEXT NOT NULL DEFAULT 'cash'
    CHECK (payment_method IN ('cash', 'online')),
  ADD COLUMN IF NOT EXISTS booking_code TEXT UNIQUE NOT NULL
    DEFAULT ('PK-' || UPPER(SUBSTR(MD5(RANDOM()::TEXT), 1, 4)));

-- 2. Make member_id nullable (safer than dropping - preserves FK integrity if any exists)
ALTER TABLE bookings
  ALTER COLUMN member_id DROP NOT NULL;

-- 3. Update status check constraint to include new guest booking statuses
-- First drop existing constraint if it exists
ALTER TABLE bookings
  DROP CONSTRAINT IF EXISTS bookings_status_check;

-- Add new constraint with all allowed statuses
ALTER TABLE bookings
  ADD CONSTRAINT bookings_status_check
  CHECK (status IN (
    'awaiting_payment',
    'awaiting_cash_payment',
    'confirmed',
    'cancelled'
  ));

-- 4. Ensure the double-booking unique constraint exists
-- (Should already exist from earlier version, but verify)
-- This prevents two bookings for same court/date/time regardless of member_id
ALTER TABLE bookings
  DROP CONSTRAINT IF EXISTS bookings_court_date_time_unique;

ALTER TABLE bookings
  ADD CONSTRAINT bookings_court_date_time_unique
  UNIQUE (court_id, date, time_slot)
  DEFERRABLE INITIALLY IMMEDIATE;

-- 5. RLS Policies
-- Enable RLS on tables (should already be enabled)
ALTER TABLE courts ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to start fresh
DROP POLICY IF EXISTS "courts_select_all" ON courts;
DROP POLICY IF EXISTS "courts_admin_all" ON courts;
DROP POLICY IF EXISTS "bookings_select_all" ON bookings;
DROP POLICY IF EXISTS "bookings_insert_anon" ON bookings;
DROP POLICY IF EXISTS "bookings_update_admin" ON bookings;
DROP POLICY IF EXISTS "bookings_delete_admin" ON bookings;
DROP POLICY IF EXISTS "profiles_select_own" ON profiles;
DROP POLICY IF EXISTS "profiles_admin_all" ON profiles;

-- Courts: PUBLIC SELECT (anon + authenticated) for schedule viewing
CREATE POLICY "courts_select_all" ON courts
  FOR SELECT
  TO anon, authenticated
  USING (active = true);

-- Courts: ADMIN full access
CREATE POLICY "courts_admin_all" ON courts
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  );

-- Bookings: PUBLIC SELECT for schedule (view availability)
CREATE POLICY "bookings_select_all" ON bookings
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- Bookings: ANON INSERT for guest bookings
-- Restrict status to only allowed initial statuses at creation time
CREATE POLICY "bookings_insert_anon" ON bookings
  FOR INSERT
  TO anon
  WITH CHECK (
    status IN ('awaiting_payment', 'awaiting_cash_payment')
    AND guest_name IS NOT NULL
    AND guest_name != ''
    AND guest_phone IS NOT NULL
    AND guest_phone != ''
    AND payment_method IN ('cash', 'online')
  );

-- Bookings: ADMIN UPDATE (Phase 1 - no customer "I've paid" updates yet)
CREATE POLICY "bookings_update_admin" ON bookings
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  );

-- Bookings: ADMIN DELETE
CREATE POLICY "bookings_delete_admin" ON bookings
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  );

-- Profiles: Users can see their own profile
CREATE POLICY "profiles_select_own" ON profiles
  FOR SELECT
  TO authenticated
  USING (id = auth.uid());

-- Profiles: ADMIN can see all profiles
CREATE POLICY "profiles_admin_all" ON profiles
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  );

-- 6. Create index for faster booking lookups by code
CREATE INDEX IF NOT EXISTS idx_bookings_booking_code ON bookings(booking_code);
CREATE INDEX IF NOT EXISTS idx_bookings_date_court ON bookings(date, court_id);
CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings(status);

-- 7. Verify the schema
-- Run these to confirm:
-- \d bookings
-- SELECT * FROM bookings LIMIT 5;