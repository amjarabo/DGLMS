# DGLMS E2E Tester Portal — Deployment Guide

End-to-End testing portal for the DGLMS GrantLens project. Hosted on GitHub Pages, backed by Supabase.

## What's in this folder

- `index.html` — the portal app (single self-contained file)
- `schema.sql` — Supabase database schema (one-time setup)
- `README.md` — this file

## Architecture

```
Tester browser → GitHub Pages (static HTML) → Supabase (Postgres + Auth + Storage)
```

- **Hosting**: GitHub Pages serves the HTML at `https://amjarabo.github.io/DGLMS/e2e-portal/`
- **Auth**: Supabase magic link sent to DOT email
- **Data**: Supabase Postgres (test results, issues, recipients)
- **Files**: Supabase Storage (issue screenshots)
- **Realtime**: Supabase WebSocket pushes updates to all connected testers

## One-time setup

### 1. Run the database schema

1. Open https://supabase.com/dashboard/project/jkwqcjvfuocxkxjcoqfx
2. Left sidebar → **SQL Editor** → **+ New query**
3. Open `schema.sql` from this folder, copy the whole file, paste it into the editor
4. Click **Run** (bottom right)
5. Verify the success message: "Schema setup complete!"

### 2. Create the screenshots storage bucket

1. Left sidebar → **Storage** → **New bucket**
2. Name: `screenshots`
3. Public bucket: **Yes** (so the portal can render uploaded images)
4. Click **Create bucket**

### 3. Configure auth

1. Left sidebar → **Authentication** → **Providers**
2. Confirm **Email** is enabled
3. Optional: turn off "Confirm email" if you want first-time logins to work without an extra confirm step
4. **Authentication** → **URL Configuration** → set **Site URL** to:
   ```
   https://amjarabo.github.io/DGLMS/e2e-portal/
   ```
5. Add to **Redirect URLs** (comma-separated):
   ```
   https://amjarabo.github.io/DGLMS/e2e-portal/
   http://localhost:*
   ```

### 4. Promote yourself to admin

After your first magic-link login, your user row is created. Then run this in SQL Editor:

```sql
update public.app_users set role = 'admin' where email = 'ana.jarabo.ctr@dot.gov';
```

(Replace with your actual email if different.)

### 5. Push to GitHub

From the root of your `DGLMS` repo:

```bash
mkdir -p e2e-portal
cp /path/to/index.html e2e-portal/index.html
cp /path/to/schema.sql e2e-portal/schema.sql
cp /path/to/README.md e2e-portal/README.md
git add e2e-portal/
git commit -m "Add E2E Tester Portal v6 (Supabase backend)"
git push origin main
```

### 6. Enable GitHub Pages

1. GitHub repo → **Settings** → **Pages**
2. Source: **Deploy from a branch**
3. Branch: `main` / `(root)`
4. Save
5. Wait ~1 min for the first deploy
6. Your portal lives at: `https://amjarabo.github.io/DGLMS/e2e-portal/`

## Daily use

### For testers

1. Open the portal URL
2. Enter DOT email → check inbox → click magic link
3. Pick a persona / environment → run tests → mark Pass/Fail
4. Log issues with the 🐛 button on any test card

### For admins (you)

- Same login flow
- Admin View tab appears in sidebar
- See every tester's results across all envs
- Export to CSV
- Manage admins/recipients via SQL Editor or the Supabase Table Editor

### Adding a new tester

Nothing needed — they just open the URL and sign in with their DOT email. They auto-get the `user` role.

### Promoting a tester to admin

```sql
update public.app_users set role = 'admin' where email = 'their.email@dot.gov';
```

### Demoting to guest (read-only)

```sql
update public.app_users set role = 'guest' where email = 'their.email@dot.gov';
```

### Adding an issue email recipient

```sql
insert into public.issue_recipients (display_name, recipient_email, active, notify_on_severity)
values ('John Smith', 'john.smith@dot.gov', true, array['High','Critical']);
```

Or use the Supabase Table Editor (Tables → issue_recipients → +Insert row).

## Troubleshooting

**"This email is not on the DOT allowlist"**: the email doesn't match the regex patterns in the portal. Edit `ALLOWED_EMAIL_PATTERNS` in `index.html` and re-push.

**Magic link doesn't arrive**: check spam folder. If still missing, in Supabase dashboard go to Authentication → Users to verify the email was received and the OTP was generated.

**Pass clicks don't save**: check browser console. Common cause: not signed in. Click the tester chip to sign in.

**Admin View doesn't appear**: you're not flagged as admin. Run the promote SQL in Step 4 above.

## Security model

- **anon key** (in HTML): can read/write data ONLY through the Row-Level Security policies. Safe to expose in source code.
- **service_role key** (in Supabase only): bypasses all policies. Never put this in HTML.
- **Row-Level Security**: testers can only write their own results. They can read team-wide aggregates (so the Overview works). Guests are read-only. Admins can do anything.

## Files mapping

| Item | Where |
|---|---|
| Portal HTML | `e2e-portal/index.html` in the repo, served from GitHub Pages |
| Schema | `e2e-portal/schema.sql`, paste into Supabase SQL Editor |
| Test results data | `public.test_results` table in Supabase |
| Issues data | `public.issues` table in Supabase |
| Screenshots | `screenshots` bucket in Supabase Storage |
| User accounts | `auth.users` (Supabase managed) + `public.app_users` (role assignment) |
