   const SUPABASE_URL = 'https://uguqqwcepkdeytrjlgdc.supabase.co';
   const SUPABASE_ANON_KEY = 'sb_publishable_UDx56mYBm6r1C7bbz-h0Xg_8rXQsVBz';

let supabaseClient = null;

function initSupabase() {
  if (typeof window.supabase !== 'undefined') {
    supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  }
}

function formatDate(date) {
  return date.toISOString().split('T')[0];
}

function formatTime(date) {
  return date.toTimeString().slice(0, 5);
}

function parseDate(dateStr) {
  return new Date(dateStr + 'T00:00:00');
}

function getUrlParam(name) {
  const params = new URLSearchParams(window.location.search);
  return params.get(name);
}

function showAlert(message, type = 'info') {
  const container = document.getElementById('alert-container') || document.body;
  const alert = document.createElement('div');
  alert.className = `alert alert-${type}`;
  alert.textContent = message;
  if (container === document.body) {
    container.insertBefore(alert, container.firstChild);
  } else {
    container.innerHTML = '';
    container.appendChild(alert);
  }
  setTimeout(() => alert.remove(), 5000);
}

function showLoading(btn) {
  btn.disabled = true;
  btn.dataset.originalText = btn.textContent;
  btn.textContent = 'Loading...';
}

function hideLoading(btn) {
  btn.disabled = false;
  btn.textContent = btn.dataset.originalText || 'Submit';
}

async function fetchCourts() {
  const { data, error } = await supabaseClient.from('courts').select('*').eq('active', true).order('name');
  if (error) throw error;
  return data;
}

// FIX 4b: use the public-safe view — exposes only court_id, date, time_slot,
// status. No guest_name, guest_phone, or booking_code leaks to the client.
async function fetchBookingsForDate(date) {
  const { data, error } = await supabaseClient
    .from('court_availability')
    .select('court_id, date, time_slot, status')
    .eq('date', date);
  if (error) throw error;
  return data;
}

async function createBooking(bookingData) {
  const { data, error } = await supabaseClient
    .from('bookings')
    .insert(bookingData)
    .select()
    .single();
  if (error) throw error;
  return data;
}

// FIX 4b: anon has no direct SELECT on bookings. Use the SECURITY DEFINER
// RPC instead — one row at a time, not a full table dump.
async function fetchBookingByCode(bookingCode) {
  const { data, error } = await supabaseClient.rpc('get_booking_by_code', { p_booking_code: bookingCode });
  if (error) throw error;
  return data && data.length ? data[0] : null;
}

async function fetchBookingById(id) {
  const { data, error } = await supabaseClient.rpc('get_booking_by_id', { p_id: id });
  if (error) throw error;
  return data && data.length ? data[0] : null;
}

async function checkAdmin() {
  const { data: { user } } = await supabaseClient.auth.getUser();
  if (!user) return false;
  const { data: profile } = await supabaseClient.from('profiles').select('is_admin').eq('id', user.id).single();
  return profile?.is_admin === true;
}

function requireAdmin() {
  return checkAdmin().then(isAdmin => {
    if (!isAdmin) {
      window.location.href = 'admin-login.html';
      return false;
    }
    return true;
  });
}

// FIX 4b: anon has no direct SELECT on messages. Use the SECURITY DEFINER
// RPC instead — one booking's messages at a time, not a full table dump.
async function fetchMessages(bookingId) {
  const { data, error } = await supabaseClient.rpc('get_messages_for_booking', { p_booking_id: bookingId });
  if (error) throw error;
  return data;
}

async function sendMessage(bookingId, senderType, senderName, text, imageUrl = null) {
  const { data, error } = await supabaseClient
    .from('messages')
    .insert({
      booking_id: bookingId,
      sender_type: senderType,
      sender_name: senderName,
      text: text,
      image_url: imageUrl
    })
    .select()
    .single();
  if (error) throw error;
  return data;
}

async function uploadPaymentProof(file, bookingId, messageId) {
  const ext = file.name.split('.').pop().toLowerCase();
  const fileName = `${bookingId}/${messageId}.${ext}`;
  const { data, error } = await supabaseClient.storage
    .from('payment-proofs')
    .upload(fileName, file, { cacheControl: '3600', upsert: false });
  if (error) throw error;
  const { data: urlData } = supabaseClient.storage.from('payment-proofs').getPublicUrl(fileName);
  return urlData.publicUrl;
}

// FIX 4c: anon has no direct UPDATE on bookings. Use the SECURITY DEFINER
// RPC instead — it internally checks the booking's own id and status,
// so a single request can never bulk-update multiple rows.
async function markBookingPaid(bookingId) {
  const { error } = await supabaseClient.rpc('mark_booking_paid', { p_booking_id: bookingId });
  if (error) throw error;
}

function subscribeToMessages(bookingId, onMessage) {
  const channel = supabaseClient
    .channel(`messages:${bookingId}`)
    .on(
      'postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'messages', filter: `booking_id=eq.${bookingId}` },
      (payload) => onMessage(payload.new)
    )
    .subscribe();
  return channel;
}

const PAYMENT_AMOUNT = 500;

async function fetchAllCourts() {
  const { data, error } = await supabaseClient.from('courts').select('*').order('name');
  if (error) throw error;
  return data;
}

async function createCourt(name) {
  const { data, error } = await supabaseClient.from('courts').insert({ name, active: true }).select().single();
  if (error) throw error;
  return data;
}

async function updateCourt(id, updates) {
  const { data, error } = await supabaseClient.from('courts').update(updates).eq('id', id).select().single();
  if (error) throw error;
  return data;
}

async function updateBookingStatusByAdmin(bookingId, newStatus) {
  const { data, error } = await supabaseClient
    .from('bookings')
    .update({ status: newStatus })
    .eq('id', bookingId)
    .neq('status', 'cancelled')
    .select()
    .single();
  if (error) throw error;
  return data;
}

async function fetchAllBookings(filters = {}) {
  let query = supabaseClient
    .from('bookings')
    .select(`
      *,
      courts (name)
    `)
    .order('created_at', { ascending: false });

  if (filters.status && filters.status !== 'all') {
    query = query.eq('status', filters.status);
  }
  if (filters.bookingCode) {
    query = query.ilike('booking_code', `%${filters.bookingCode}%`);
  }

  const { data, error } = await query;
  if (error) throw error;
  return data;
}

document.addEventListener('DOMContentLoaded', initSupabase);