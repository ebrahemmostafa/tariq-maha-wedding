# Tariq & Maha – Wedding Invitation

Digital wedding invitation for **Tariq Mohamed & Maha Khaled**, built on the Stained Glass (Bloom) template.

- **Date:** Saturday, 5 December 2026 · 5:00 PM
- **Venue:** The Vine, Line 7, Gameiat Oraby, Obour City — [Google Maps](https://maps.app.goo.gl/7niX5JG6fMhDFzjf6?g_st=ic)
- **Background color:** `#EBD1CE`

## Sections
1. Intro doors (T&M monogram) and hero
2. Welcome — Quran verse, couple and families
3. Countdown to 5 Dec 2026, 5:00 PM (Cairo time)
4. Scratch card — "so don't be late!"
5. Ceremony & Reception — The Vine, with Google Maps / calendar buttons
6. Dress code — color palette for the ladies
7. Program — arrival, entrance, katb ketab, party, photos, dinner
8. RSVP

## RSVPs (Supabase)
Guest replies are stored in your own Supabase project, and `admin.html` shows them (totals, search, CSV export, delete) behind a passcode.

1. Create a project at [supabase.com](https://supabase.com).
2. In **SQL Editor**, run `supabase/setup.sql`, replacing `__ADMIN_PASSCODE__` at the bottom with the admin passcode first. It creates the `rsvps` table with row-level security: guests can only add a reply; reading or deleting goes through the passcode-checked functions.
3. In **Project Settings → API**, copy the Project URL and the publishable (or `anon`) key into `js/supabase-config.js`.
4. Open `admin.html` (e.g. `https://<user>.github.io/tariq-maha-wedding/admin.html`) and enter the passcode.

Wrong passcodes are throttled: 10 from one IP address in 15 minutes locks that address, and 20 from everyone together locks the page for the rest of the 15 minutes. If you are ever locked out, run `delete from public.rsvp_admin_attempts;` in the SQL Editor. To change the passcode, re-run the last statement in `setup.sql` with the new value.

## Structure
- `index.html` – entry page
- `admin.html` – RSVP dashboard (passcode protected)
- `js/supabase-config.js` – your Supabase URL and publishable key
- `supabase/setup.sql` – database setup for RSVPs
- `js/index-B5N1kRjD.beautified.js` – app bundle (all invitation text lives here)
- `css/` – compiled styles
- `assets/` – images, intro video and background music

## Run locally
Serve the folder with any static server, e.g. `python -m http.server`, and open http://localhost:8000.
