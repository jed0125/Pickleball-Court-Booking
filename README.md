# Pickleball Court Booking

A court booking and reservation platform for a pickleball facility. Guests browse live court availability, reserve a slot with just their name and phone number, and pay by cash at the court or online via GCash/Maya. Built with HTML, CSS, and JavaScript on Supabase (Auth, Postgres, Realtime, Storage).

**Live demo:** _add your Vercel/Netlify link here_

## Features

- **Guest booking** — No account or password required. Guests reserve a slot with just their name and phone number.
- **Live court schedule** — A real-time grid of courts and time slots, synced instantly via Supabase Realtime so a booked slot disappears for everyone the moment it's taken.
- **Flexible payment** — Pay cash at the court, or pay online via a GCash/Maya QR code and confirm with the front desk through an in-app chat.
- **Booking-scoped chat** — Each reservation has its own chat thread where the guest and admin sort out payment, including image attachments for payment proof.
- **Digital receipt** — Every booking gets a short reservation code (e.g. `PK-4Q7X`) and a receipt screen that can be shown at the front desk.
- **Admin dashboard** — A separate, authenticated admin view to manage courts, review all bookings, confirm payments, and cancel reservations.
- **Responsive design** — Works on desktop browsers and mobile devices, with a dedicated mobile layout.

## Tech Stack

- **Frontend:** HTML5, CSS3, JavaScript (ES6 Modules) — no framework, no build step
- **Backend:** Supabase (Postgres database, Auth, Realtime, Storage)
- **Authentication:** Supabase Auth (Email/Password) — admin accounts only; guests do not sign up
- **Hosting:** Vercel

## Project Structure

```
├── index.html              # Public welcome page
├── schedule.html           # Live court schedule (public)
├── booking-form.html       # Guest details + payment method
├── reservation.html        # Online payment: QR code, "I've paid", chat
├── receipt.html            # Reservation code / front-desk receipt
├── my-reservation.html     # Reservation status + chat (public, by code)
├── admin-register.html     # Admin account signup (does not grant access alone)
├── admin-login.html        # Admin-only login
├── admin.html               # Admin dashboard (bookings & courts)
├── full_schema.sql         # Database schema, RLS policies, and functions
├── css/
│   └── styles.css
└── app.js                  # Supabase client config + all data access functions
```

## Getting Started

1. Clone the repo and open the folder in VS Code.
2. Create a [Supabase project](https://supabase.com/dashboard).
3. Run `full_schema.sql` in the Supabase SQL Editor — it creates all tables, security policies, and helper functions in one pass.
4. In **Project Settings → API**, copy your Project URL and Publishable (anon) key into `app.js` (`SUPABASE_URL` and `SUPABASE_ANON_KEY`).
5. In **Storage**, create a bucket named exactly `payment-proofs` (private, 5 MB file size limit, allowed types: `image/jpeg, image/png, image/webp`).
6. Create the first admin account via `admin-register.html`, then in **Table Editor → profiles**, set that user's `is_admin` field to `true`.
7. In **Project Settings → Data API**, make sure all tables and functions are toggled on for API access (this is separate from Row Level Security, and is off by default on new projects).
8. Run locally with the VS Code **Live Server** extension (`index.html` → *Open with Live Server*).

## Deployment

```bash
npm install -g vercel
vercel login
vercel
```

For later updates, redeploy with:

```bash
vercel --prod
```

## Roles

- **Guest** — anyone booking a court. No account; identified by name, phone number, and a unique reservation code.
- **Admin** — manages courts and confirms payments. Created via `admin-register.html`, then granted access manually by an existing admin in the Supabase dashboard.

## Payment Flow

- **Cash** — booking is marked `awaiting_cash_payment`; the admin confirms once payment is received at the court.
- **Online** — booking is marked `awaiting_payment`; the guest scans a QR code, sends proof in the reservation chat, and the admin confirms once verified.

## Security

- Row Level Security (RLS) ensures only an authenticated admin can confirm payments, cancel bookings, or manage courts.
- A reservation's chat and status are accessible via its unique, unguessable booking ID or reservation code — there is no password-based privacy for guest bookings, matching the no-account design.
- A database constraint prevents the same court, date, and time slot from being double-booked, while still allowing a cancelled slot to be rebooked.
- Guest-facing reads never expose another guest's name or phone number; the schedule grid is powered by a PII-free view, and lookups by booking code or ID return only that one booking.

## License

This project is provided as-is for educational purposes.
