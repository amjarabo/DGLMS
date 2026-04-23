# DGLMS Portal

A multi-page QA portal for the DOT Digital Grant Lifecycle Management System.
Gated to `@dot.gov` accounts. Live shared state via Supabase.

---

## Files in this repo

| File | What it is |
|---|---|
| `login.html` | The single sign-in page. Everyone starts here. |
| `index.html` | Portal home / dashboard after login. |
| `smoke.html` | Smoke tests — drop a workbook, push to team. |
| `regression.html` | Regression suite — drop a workbook, push to team. |
| `testcases.html` | Test cases — GRAN stories, with viewer per push. |
| `checklist.html` | Shared pre-release checklist (live). |
| `dashboard.html` | Sprint metrics — all pushes, all sections. |
| `compliance.html`, `scope.html`, `environment.html`, `section508.html`, `requirements.html` | Project documentation pages. Edit the content directly in each HTML file. |
| `portal.css` | Shared theme (dark + light mode). |
| `portal.js` | Shared auth guard, sidebar, theme toggle. |
| `upload.js` | Shared drop-zone + Supabase push widget. |
| `supabase_setup.sql` | One-time database setup — paste into Supabase SQL editor. |

---

## First-time setup (10 minutes)

### 1. Run the SQL

1. Open Supabase dashboard → your project → SQL Editor → **New query**
2. Open `supabase_setup.sql`, copy everything, paste into the editor
3. Click **Run**. You should see no errors.
4. Verify by going to **Database → Tables** — you'll see `login_audit` and `shared_workbooks`.

### 2. Tell Supabase where the portal lives

1. Supabase dashboard → **Authentication → URL Configuration**
2. **Site URL**: set to wherever you'll host the portal, e.g.
   - GitHub Pages: `https://your-username.github.io/dglms-portal/`
   - Local testing: `http://localhost:5500/` (or whatever port your local server uses)
3. **Redirect URLs**: add the same URL. Save.

### 3. Turn on the email provider

1. Supabase dashboard → **Authentication → Providers → Email**
2. Make sure **"Enable email provider"** is ON
3. Decide on **"Confirm email"** — I recommend OFF for internal use (users click invite → set password → signed in). ON means they also have to click a confirmation email.

### 4. Invite your first users

1. Supabase dashboard → **Authentication → Users → Add user**
2. Pick **"Send invite"** (not "Create user") so they set their own password
3. Enter `ana.whoever@dot.gov`, `franco.berrocal@dot.gov`, `zachary.kratsas@dot.gov`, etc.
4. Users get an email: click link → set password → land on the portal login.

**Anyone whose email isn't `@dot.gov` gets rejected** — both by client-side check and by the database-level RLS policies you just ran. You can't accidentally grant access by inviting a Gmail address.

### 5. Put the files on GitHub

1. Create a repo (e.g. `dglms-portal`)
2. Upload all files from this folder
3. Repo Settings → **Pages** → Source: `main` branch, `/` root → Save
4. Wait ~1 min. URL shows up at the top of the Pages section.
5. Go back to Supabase and make sure the Site URL matches.

---

## Daily use

- Everyone goes to the Pages URL → lands on `login.html` (or the deep-link they were sent, after auth).
- Drop an Excel/CSV file on any workstream page → previews the first 5 rows → **Push to team**.
- All teammates see the push within ~1 second. No refresh.
- The **Sprint Dashboard** rolls up pushes across every section.
- Sign-out button is at the bottom of the sidebar.

---

## How auth works (one paragraph)

`portal.js` creates a singleton Supabase client. Every page except `login.html` calls `Portal.init()` which checks for a session; no session → redirect to login. The session lives in `localStorage`, so moving between pages (even in a new tab) keeps you signed in. Closing the browser does **not** sign you out automatically — you use the sign-out button for that. If that's not what you want, see the note in "Adjusting behavior" below.

The `@dot.gov` gate runs in two places: in the browser before `signInWithPassword` (fast rejection) and in the database via RLS policies that check `auth.jwt() ->> 'email'` — so even if someone edits the HTML, they still can't read or write data.

Every page load logs a row to `login_audit` with `email`, `page`, `user_agent`, and `login_at`. To see it: `select * from public.login_audit order by login_at desc limit 20;` in SQL editor.

---

## Adjusting behavior

**Want tab-close to sign you out?** In `portal.js`, change `storage: window.localStorage` to `storage: window.sessionStorage`. Downside: opening a section in a new tab requires fresh sign-in.

**Want to change the accent color?** Search `portal.css` for `--gold` and change it in both the `:root` block (dark mode) and the `body.light` block.

**Want to add a new section page?** Copy any of the existing generated pages (e.g. `smoke.html`), rename it, update the title/section slug, add an entry to the `NAV_ITEMS` array in `portal.js`.

**Want Google SSO instead of password?** Supabase dashboard → Authentication → Providers → Google, then in `login.html` replace the password form with a `signInWithOAuth({ provider: 'google' })` button.

---

## Known limitations

- **Checklist uses `shared_workbooks` as its backing table.** This works but means checklist items show up in dashboard counts as "pushes". If you want them to be separate, add a dedicated `checklist_items` table — ask me and I'll write the migration.
- **No file search across pushes.** You can filter by filename and uploader on the Test Cases page but there's no full-text search over the parsed data yet.
- **No row-level edit.** Once a workbook is pushed, to change it you upload a new version. The old push stays in the history.
- **`sessionStorage` would break new-tab navigation.** Current `localStorage` default keeps you logged in across new tabs, which is the usual expectation for internal portals.

---

## Quick troubleshooting

| Problem | Fix |
|---|---|
| "Invalid login credentials" | The user needs to be invited via Supabase first. Self-signup is not allowed. |
| Redirects loop between login and index | Site URL in Supabase doesn't match the actual Pages URL. Fix in Authentication → URL Configuration. |
| "Access restricted to @dot.gov accounts" | User's email is on a different domain. Invite a `@dot.gov` address instead. |
| Pushes don't appear live for other users | Realtime not enabled on `shared_workbooks`. The SQL does this but if you skipped it, run `alter publication supabase_realtime add table public.shared_workbooks;`. |
| "permission denied for table login_audit" | RLS policy is missing. Re-run `supabase_setup.sql` — it's safe to re-run. |

---

## Credentials embedded in this portal

The Supabase **anon key** is in `portal.js`. This is by design — it's a public key that's safe to expose. What actually protects data is RLS on each table. **Never put the service_role key** (also in Supabase Settings → API) into any of these files — it bypasses RLS.
