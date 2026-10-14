-- full_schema.sql
-- Combined schema from all four migrations, with security fixes
-- Run this in Supabase SQL Editor on a brand-new, empty database
--
-- FIX (this pass): is_admin() is a LANGUAGE sql function. Postgres
-- parses LANGUAGE sql functions at CREATE FUNCTION time, which
-- requires any table it references to already exist. The previous
-- version defined is_admin() before the profiles table existed,
-- which would fail with "relation 'profiles' does not exist" the
-- moment this script tried to run. Fixed by moving all helper
-- functions to AFTER the table definitions.
 
-- ============================================================
-- 1. Tables
-- ============================================================
 
CREATE TABLE IF NOT EXISTS profiles (
  -- profiles.id references auth.users(id) ON DELETE CASCADE
  -- A profile row cannot exist without a real auth user, and gets
  -- cleaned up automatically if that user is deleted.
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  is_admin BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);
 
CREATE TABLE IF NOT EXISTS courts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);
 
CREATE TABLE IF NOT EXISTS bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id UUID REFERENCES profiles(id),
  court_id UUID REFERENCES courts(id),
  date DATE NOT NULL,
  time_slot TEXT NOT NULL,
  status TEXT NOT NULL,
  booking_code TEXT UNIQUE NOT NULL DEFAULT ('PK-' || UPPER(SUBSTR(MD5(RANDOM()::TEXT), 1, 4))),
  guest_name TEXT NOT NULL DEFAULT '',
  guest_phone TEXT NOT NULL DEFAULT '',
  payment_method TEXT NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('cash', 'online')),
  last_seen_by_admin TIMESTAMPTZ,
  CONSTRAINT bookings_status_check CHECK (status IN ('awaiting_payment','awaiting_cash_payment','pending_confirmation','confirmed','cancelled'))
  -- Double-booking prevention is a PARTIAL unique index, added below,
  -- not a plain UNIQUE constraint — see section 2 for why.
);
 
CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  sender_type TEXT NOT NULL CHECK (sender_type IN ('guest', 'admin')),
  sender_name TEXT NOT NULL,
  text TEXT,
  image_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
 
-- ============================================================
-- 2. Partial unique index — only non-cancelled bookings are unique
-- ============================================================
-- A plain UNIQUE (court_id, date, time_slot) would permanently block
-- rebooking a slot after cancellation. This partial index only
-- enforces uniqueness among non-cancelled bookings, so a cancelled
-- slot frees back up.
 
CREATE UNIQUE INDEX IF NOT EXISTS bookings_court_date_time_unique
  ON bookings (court_id, date, time_slot)
  WHERE status != 'cancelled';
 
-- ============================================================
-- 3. Helper functions (now safely placed after their tables exist)
-- ============================================================
 
-- Security definer function to check admin status without recursion.
-- A policy ON profiles that queries profiles triggers Postgres's
-- "infinite recursion detected in policy for relation 'profiles'"
-- error. is_admin() runs as the function owner (bypasses RLS), so
-- there is no recursion when policies call it instead of querying
-- profiles directly.
CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid()
    AND profiles.is_admin = true
  );
$$;
 
-- Trigger that auto-creates a profiles row on new auth signup.
-- Without this, is_admin() always returns false (no row = no match).
-- This is LANGUAGE plpgsql, which is lazily checked, so its
-- placement relative to the profiles table was never actually the
-- problem — only is_admin() (LANGUAGE sql) needed to move.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, is_admin)
  VALUES (new.id, false);
  RETURN new;
END;
$$;
 
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();
 
-- Scoped booking lookup by code. An anon guest who knows their
-- booking_code (shown at booking time and stored in localStorage)
-- calls this via supabase.rpc('get_booking_by_code', { p_booking_code }).
-- A bare GET /bookings (list) returns nothing for anon, since there
-- is no SELECT policy granting anon direct table access — this is
-- intentional: the code itself (not a password) is what gates access,
-- acceptable because it's a random 4-char suffix shown once at booking.
CREATE OR REPLACE FUNCTION get_booking_by_code(p_booking_code TEXT)
RETURNS SETOF bookings
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT * FROM bookings WHERE booking_code = p_booking_code;
$$;
 
GRANT EXECUTE ON FUNCTION get_booking_by_code(TEXT) TO anon, authenticated;
 
-- Same idea, scoped lookup by booking id (used when navigating
-- straight to reservation.html?id=... right after booking).
CREATE OR REPLACE FUNCTION get_booking_by_id(p_id UUID)
RETURNS SETOF bookings
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT * FROM bookings WHERE id = p_id;
$$;
 
GRANT EXECUTE ON FUNCTION get_booking_by_id(UUID) TO anon, authenticated;
 
-- Scoped message reads. Replaces a blanket SELECT policy on
-- messages, which would otherwise let anyone list every message
-- across every booking (including admin-uploaded payment-proof
-- links). Anyone with the booking_id can read that one booking's
-- messages; a bare GET /messages returns nothing for anon.
CREATE OR REPLACE FUNCTION get_messages_for_booking(p_booking_id UUID)
RETURNS SETOF messages
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT * FROM messages WHERE booking_id = p_booking_id;
$$;
 
GRANT EXECUTE ON FUNCTION get_messages_for_booking(UUID) TO anon, authenticated;
 
-- "I've paid" action. Anon can only move a booking from
-- awaiting_payment to pending_confirmation by calling this function
-- with one specific booking id. Because the WHERE clause is baked
-- into the function body (not left to whatever filter the client
-- happens to send), a guest cannot bulk-update every awaiting_payment
-- booking at once — each call only ever touches the one row whose id
-- was passed in, and only if it's still awaiting_payment and online.
CREATE OR REPLACE FUNCTION mark_booking_paid(p_booking_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE bookings
  SET status = 'pending_confirmation'
  WHERE id = p_booking_id
    AND status = 'awaiting_payment'
    AND payment_method = 'online';
END;
$$;
 
GRANT EXECUTE ON FUNCTION mark_booking_paid(UUID) TO anon, authenticated;
 
-- ============================================================
-- 4. Public-safe view for the schedule grid
-- ============================================================
-- Exposes only the four fields needed to draw the availability grid.
-- No guest_name, guest_phone, booking_code, member_id. The view
-- owner (the role running this script) bypasses RLS, so anon can
-- read it without needing a direct SELECT policy on bookings.
 
CREATE OR REPLACE VIEW court_availability AS
  SELECT court_id, date, time_slot, status
  FROM bookings
  WHERE status != 'cancelled';
 
GRANT SELECT ON court_availability TO anon, authenticated;
 
-- ============================================================
-- 5. Enable RLS on all tables
-- ============================================================
 
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE courts   ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
 
-- ============================================================
-- 6. Indexes (non-unique lookups)
-- ============================================================
 
CREATE INDEX IF NOT EXISTS idx_bookings_booking_code         ON bookings(booking_code);
CREATE INDEX IF NOT EXISTS idx_bookings_date_court           ON bookings(date, court_id);
CREATE INDEX IF NOT EXISTS idx_bookings_status               ON bookings(status);
CREATE INDEX IF NOT EXISTS idx_bookings_last_seen_by_admin   ON bookings(last_seen_by_admin);
CREATE INDEX IF NOT EXISTS idx_messages_booking_id           ON messages(booking_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at           ON messages(created_at);
 
-- ============================================================
-- 7. RLS Policies
-- ============================================================
 
-- -----------------------------------------------------------
-- profiles
-- -----------------------------------------------------------
 
CREATE POLICY "profiles_select_own" ON profiles
  FOR SELECT
  TO authenticated
  USING (id = auth.uid());
 
CREATE POLICY "profiles_admin_all" ON profiles
  FOR ALL
  TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());
 
-- -----------------------------------------------------------
-- courts
-- -----------------------------------------------------------
 
CREATE POLICY "courts_select_all" ON courts
  FOR SELECT
  TO anon, authenticated
  USING (active = true);
 
CREATE POLICY "courts_admin_all" ON courts
  FOR ALL
  TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());
 
CREATE POLICY "courts_admin_insert" ON courts
  FOR INSERT
  TO authenticated
  WITH CHECK (is_admin());
 
CREATE POLICY "courts_admin_update" ON courts
  FOR UPDATE
  TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());
 
CREATE POLICY "courts_admin_delete" ON courts
  FOR DELETE
  TO authenticated
  USING (is_admin());
 
-- -----------------------------------------------------------
-- bookings
-- Anon has NO direct SELECT policy — guests read specific bookings
-- only via get_booking_by_code() / get_booking_by_id() RPC calls,
-- and the schedule grid reads the court_availability view instead.
-- Anon has NO direct UPDATE policy — "I've paid" goes through the
-- mark_booking_paid() RPC only.
-- -----------------------------------------------------------
 
CREATE POLICY "bookings_select_admin" ON bookings
  FOR SELECT
  TO authenticated
  USING (is_admin());
 
CREATE POLICY "bookings_insert_anon" ON bookings
  FOR INSERT
  TO anon
  WITH CHECK (
    status IN ('awaiting_payment','awaiting_cash_payment')
    AND guest_name IS NOT NULL
    AND guest_name != ''
    AND guest_phone IS NOT NULL
    AND guest_phone != ''
    AND payment_method IN ('cash','online')
  );
 
CREATE POLICY "bookings_admin_update_status" ON bookings
  FOR UPDATE
  TO authenticated
  USING (
    status != 'cancelled'
    AND is_admin()
  )
  WITH CHECK (
    status IN ('confirmed','cancelled')
    AND is_admin()
  );
 
CREATE POLICY "bookings_admin_delete" ON bookings
  FOR DELETE
  TO authenticated
  USING (is_admin());
 
-- -----------------------------------------------------------
-- messages
-- Anon/authenticated have NO direct SELECT policy — reads go
-- through get_messages_for_booking() only.
-- -----------------------------------------------------------
 
CREATE POLICY "messages_insert_booking" ON messages
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (
    booking_id IS NOT NULL
    AND sender_type IN ('guest','admin')
    AND sender_name IS NOT NULL
    AND sender_name != ''
  );
 
CREATE POLICY "messages_admin_all" ON messages
  FOR ALL
  TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());
 
-- ============================================================
-- 8. Storage policies for 'payment-proofs' bucket
-- ============================================================
-- Note: the bucket itself must be created in Supabase Dashboard
-- > Storage > Create bucket "payment-proofs" before these policies
-- take effect.
 
DROP POLICY IF EXISTS "payment_proofs_admin_upload" ON storage.objects;
CREATE POLICY "payment_proofs_admin_upload" ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'payment-proofs'
    AND is_admin()
  );
 
CREATE POLICY "payment_proofs_public_read" ON storage.objects
  FOR SELECT
  TO anon, authenticated
  USING (bucket_id = 'payment-proofs');
 
DROP POLICY IF EXISTS "payment_proofs_admin_manage" ON storage.objects;
CREATE POLICY "payment_proofs_admin_manage" ON storage.objects
  FOR ALL
  TO authenticated
  USING (
    bucket_id = 'payment-proofs'
    AND is_admin()
  )
  WITH CHECK (
    bucket_id = 'payment-proofs'
    AND is_admin()
  );
 
-- ============================================================
-- 9. Verification queries (run these manually after, one at a time)
-- ============================================================
-- \d profiles
-- \d courts
-- \d bookings
-- \d messages
-- SELECT * FROM pg_policies WHERE tablename IN ('profiles','courts','bookings','messages');
 