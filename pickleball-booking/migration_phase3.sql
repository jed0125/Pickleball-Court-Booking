-- migration_phase3.sql
-- Phase 3: Admin Dashboard & Admin-Only Actions
-- Run this in the Supabase SQL Editor AFTER migration_phase2.sql

-- 1. Admin-only UPDATE policies for courts
DROP POLICY IF EXISTS "courts_admin_update" ON courts;
CREATE POLICY "courts_admin_update" ON courts
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

DROP POLICY IF EXISTS "courts_admin_insert" ON courts;
CREATE POLICY "courts_admin_insert" ON courts
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  );

-- 2. Admin-only UPDATE policies for bookings
-- Admin can set status to 'confirmed' or 'cancelled' from any prior status except 'cancelled'
DROP POLICY IF EXISTS "bookings_admin_update_status" ON bookings;
CREATE POLICY "bookings_admin_update_status" ON bookings
  FOR UPDATE
  TO authenticated
  USING (
    status != 'cancelled'
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  )
  WITH CHECK (
    status IN ('confirmed', 'cancelled')
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  );

-- 3. Verify anon CANNOT perform admin transitions
-- These statements should FAIL if run as anon (test in SQL Editor with anon role):
-- SET ROLE anon;
-- UPDATE bookings SET status = 'confirmed' WHERE id = 'some-uuid'; -- Should fail: no policy allows anon UPDATE
-- UPDATE courts SET active = false WHERE id = 'some-uuid'; -- Should fail: no policy allows anon UPDATE
-- INSERT INTO courts (name, active) VALUES ('Test Court', true); -- Should fail: no policy allows anon INSERT
-- RESET ROLE;

-- 4. Admin can also delete bookings (optional, for cleanup)
DROP POLICY IF EXISTS "bookings_admin_delete" ON bookings;
CREATE POLICY "bookings_admin_delete" ON bookings
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  );

-- 5. Courts: Admin can delete (optional)
DROP POLICY IF EXISTS "courts_admin_delete" ON courts;
CREATE POLICY "courts_admin_delete" ON courts
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  );

-- 6. Verify the policies are working
-- Run these to confirm:
-- \d courts
-- \d bookings
-- SELECT * FROM pg_policies WHERE tablename IN ('courts', 'bookings', 'messages');