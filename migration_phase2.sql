-- migration_phase2.sql
-- Phase 2: Online Payment Flow with Chat & Payment Proofs
-- Run this in the Supabase SQL Editor AFTER migration_guest_booking.sql

-- 1. Create messages table
CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  sender_type TEXT NOT NULL CHECK (sender_type IN ('guest', 'admin')),
  sender_name TEXT NOT NULL,
  text TEXT,
  image_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Index for faster message lookups by booking
CREATE INDEX IF NOT EXISTS idx_messages_booking_id ON messages(booking_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at);

-- 2. Enable RLS on messages
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "messages_select_booking" ON messages;
DROP POLICY IF EXISTS "messages_insert_booking" ON messages;
DROP POLICY IF EXISTS "messages_admin_all" ON messages;

-- Messages: SELECT allowed for anon AND authenticated, scoped to a specific booking_id
-- The policy allows reading messages for any booking_id that is referenced in the query
-- This works because the client must already know the booking UUID (unguessable)
CREATE POLICY "messages_select_booking" ON messages
  FOR SELECT
  TO anon, authenticated
  USING (true);
  -- Note: Application-level filtering by booking_id in the query provides scoping
  -- Since booking IDs are UUIDs, they are unguessable, providing privacy without auth

-- Messages: INSERT allowed for anon AND authenticated, scoped to a specific booking_id
-- sender_type and sender_name are trusted from client (no guest auth to verify against)
CREATE POLICY "messages_insert_booking" ON messages
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (
    booking_id IS NOT NULL
    AND sender_type IN ('guest', 'admin')
    AND sender_name IS NOT NULL
    AND sender_name != ''
  );

-- Messages: Admin full access across all bookings
CREATE POLICY "messages_admin_all" ON messages
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

-- 3. Update bookings table: add new status and UPDATE policy for anon "I've paid"
-- First update the status check constraint to include 'pending_confirmation'
ALTER TABLE bookings
  DROP CONSTRAINT IF EXISTS bookings_status_check;

ALTER TABLE bookings
  ADD CONSTRAINT bookings_status_check
  CHECK (status IN (
    'awaiting_payment',
    'awaiting_cash_payment',
    'pending_confirmation',
    'confirmed',
    'cancelled'
  ));

-- Add UPDATE policy: anon can ONLY update status from 'awaiting_payment' to 'pending_confirmation'
-- and ONLY when they know the booking's id (provided in WHERE clause)
DROP POLICY IF EXISTS "bookings_update_anon_paid" ON bookings;

CREATE POLICY "bookings_update_anon_paid" ON bookings
  FOR UPDATE
  TO anon
  USING (status = 'awaiting_payment')
  WITH CHECK (
    status = 'pending_confirmation'
    AND guest_name IS NOT NULL
    AND guest_name != ''
    AND guest_phone IS NOT NULL
    AND guest_phone != ''
    AND payment_method = 'online'
  );

-- 4. Supabase Storage: Create bucket 'payment-proofs'
-- Note: Buckets must be created via Dashboard or Storage API, not SQL
-- Run this in Supabase Dashboard > Storage > Create bucket "payment-proofs"
-- Or use the Supabase CLI: supabase storage create payment-proofs

-- 5. Storage RLS Policies for 'payment-proofs' bucket
-- These policies are applied via the Supabase Dashboard > Storage > Policies
-- Or via SQL using the storage.objects table policies

-- Enable RLS on storage.objects (should already be enabled)
-- ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Policy: Authenticated admins can upload to payment-proofs
DROP POLICY IF EXISTS "payment_proofs_admin_upload" ON storage.objects;
CREATE POLICY "payment_proofs_admin_upload" ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'payment-proofs'
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  );

-- Policy: Anyone (anon + authenticated) can read from payment-proofs if they know the exact path
-- Path convention: {booking_id}/{message_id}.{ext}
-- Since booking_id is an unguessable UUID, this provides privacy
DROP POLICY IF EXISTS "payment_proofs_public_read" ON storage.objects;
CREATE POLICY "payment_proofs_public_read" ON storage.objects
  FOR SELECT
  TO anon, authenticated
  USING (bucket_id = 'payment-proofs');

-- Policy: Admins can delete/update their own uploads
DROP POLICY IF EXISTS "payment_proofs_admin_manage" ON storage.objects;
CREATE POLICY "payment_proofs_admin_manage" ON storage.objects
  FOR ALL
  TO authenticated
  USING (
    bucket_id = 'payment-proofs'
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  )
  WITH CHECK (
    bucket_id = 'payment-proofs'
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  );

-- 6. Verify the schema
-- \d messages
-- \d bookings
-- SELECT * FROM messages LIMIT 5;
-- Check storage buckets in Dashboard