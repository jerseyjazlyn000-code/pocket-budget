# Pocket Budget Together — two-phone invitation + cloud sync

**Status:** App files are ready. Cloud syncing will NOT work until you configure a Supabase project and run `setup.sql`. This is not a fully activated shared service yet.

## Setup (the person who owns the app)

1. Go to https://supabase.com/dashboard and create a Supabase project. The free tier may be sufficient for light personal use (check current limits).
2. Open the project **SQL Editor**. Paste the entire contents of `setup.sql` and run it once. This creates the database, member-only access rules, and the create/join invitation functions.
3. Go to **Project Settings → API** (or the project's **Connect** panel) and copy the **Project URL** and **publishable key**. A legacy public **anon** key also works. **Do NOT use the secret/service-role key.**
4. Open `config.js` in a text editor, paste those two values into `url` and `key`, and save it.
5. Upload the updated files, **including `setup.sql` and `SETUP-START-HERE.md` if you like**, to https://github.com/jerseyjazlyn000-code/pocket-budget with `index.html`, `manifest.webmanifest`, `sw.js`, `config.js`, and both `icon-*.png` files in the root of the repository. The `.sql` setup file is not needed for the website to run, but keeping it in the repository makes it public (it contains no credentials).
6. The existing GitHub Pages site is at https://jerseyjazlyn000-code.github.io/pocket-budget/. After publishing, open/refresh it on both phones. If the old app still loads, close/reopen it; cached web apps may need another launch to update.
7. **Each person creates their own account with a different email and password.** Supabase may send confirmation emails; complete verification as instructed, then sign in.
8. The first person enters their display name and taps **Create household**. In **Invite**, copy the generated 16-character invitation code. Send it privately to the second person.
9. The second person installs/opens the same URL, creates their own account, types their display name and the code, and taps **Join**.
10. Both people now see the same entries and balances. The interface listens for real-time events and also refreshes about every 15 seconds while the app is open.

## Features

- Separate personal Cash, Bank and Savings balances for each household member
- Extra **Shared** balance to represent joint funds
- Combined Total, Available to Spend (not including either person's Savings), expenses and income
- Transaction types: Income, Expense and Transfer, including transfers between members or into shared money
- Per-person activity filters, combined activity, category monthly breakdown
- Export shared data as a JSON backup
- Optional legacy import: Settings/Invite → **Import old Pocket Budget data**, if the original local storage exists on that same origin/installed web app

## Data safety

- The 16-character invitation code lets another person join your household. Share it only with your partner. **Joining is restricted to two accounts.**
- Authenticated members can **both** view, edit, and delete all shared finance entries. The service is designed for trusted couples, not a bank account.
- The online database stores financial figures and descriptions. Use strong, unique passwords; enable Supabase email confirmation; do not enter bank login details.
- To keep the old budget, **export a backup before updating the site**. The old `pocket-budget-v1` local data is not automatically erased. The one-time old-data import can create duplicates if repeated.
- Offline viewing/editing are not supported for shared data: an internet connection is required to sync safely. The HTML may load from cache, but remote data requires network access.
- For privacy, the project credentials in `config.js` are public client credentials. The SQL row-level-security access policies, not the public key, are what protect household records.
- This is a working code package, **not a hosted database or activated deployment**. You must supply Supabase credentials and run the SQL.

## Troubleshooting

- **Invalid API key / failed fetch:** check `config.js`, Supabase project status, connection and URL.
- **function pb_create_household does not exist:** `setup.sql` was not run successfully.
- **Email not confirmed:** click the confirmation link before signing in.
- **Partner sees no household:** each phone must use the *same* Supabase project and different login email addresses; partner must join using the invitation code.
- **Existing app still loads:** GitHub Pages/service worker cache may still be serving the prior version. Refresh online, close the Home Screen app and reopen.
