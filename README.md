# Money Moves NYC: student accounts and saved progress

This folder turns Money Moves into a site you host yourself, with a real database behind it:

- **Student accounts.** Students sign up inside the game with a **class code + username + 6-digit PIN**. No email, no real name needed.
- **Saved progress.** All three levels (Queens, college town, Manhattan), every milestone, choice and score save to the student's account, so they can pick up on any device.
- **Class leaderboard, class events and the shared world** all run through your database. It no longer depends on students having claude.ai accounts.
- **A facilitator dashboard** (`teacher.html`). Create classes, see every student's progress live, reset PINs, remove students, export a CSV, send class events and put the leaderboard on a projector.

It uses **Supabase**, which matches the Next.js + Supabase platform you've planned, so this data can move into that platform later.

```
money-moves-backend/
├── public/                  ← upload this folder to your web host
│   ├── index.html           the game (students)
│   ├── teacher.html         facilitator dashboard
│   └── config.js            your Supabase keys go here
├── supabase/
│   ├── schema.sql           database tables + security rules (run once)
│   └── functions/manage-student/index.ts   PIN reset + remove student
├── src/game.html            game source (same file as the claude.ai version)
└── build.py                 rebuilds public/index.html from src/game.html
```

---

## Setup (about 30–45 minutes, once)

### 1. Create a Supabase project
1. Go to supabase.com → sign in → **New project**. Name it `money-moves`, pick the **East US** region, and save the database password somewhere safe.
2. Wait about 2 minutes for it to finish setting up.

### 2. Create the database
1. In your project: **SQL Editor → New query**.
2. Open `supabase/schema.sql`, copy all of it, paste it in, and click **Run**. You should see "Success". It's safe to run again later.

### 3. Change two sign-in settings (important)
1. **Authentication → Sign In / Providers → Email**: turn **off "Confirm email"**. Student logins use placeholder addresses that can't receive mail. Leave "Allow new users to sign up" **on**.
2. **Authentication → Rate Limits**: raise **"sign-ups and sign-ins"** from 30 to **300** per 5 minutes. A whole classroom shares one school internet address, and the default would block your 31st student.

### 4. Make yourself a facilitator
1. **Authentication → Users → Add user → Create new user**. Use your email and a strong password, and tick **Auto Confirm User**.
2. Copy the new user's **UID** (click the user to see it).
3. In **SQL Editor**, run (paste your UID):
   ```sql
   insert into public.facilitators (user_id, name)
   values ('PASTE-YOUR-UID-HERE', 'Mo');
   ```
   Repeat for any co-facilitator. If you skip this, the dashboard shows the exact line to run.

### 5. Add your keys to `config.js`
In Supabase go to **Project Settings → API** and copy:
- **Project URL** → `supabaseUrl`
- **anon public** key → `supabaseAnonKey`

Paste them into `public/config.js`. The anon key is meant to be public. The security rules in `schema.sql` decide what each person can see and do. **Never** put the `service_role` key in any file you upload.

### 6. Deploy the PIN-reset function
This lets you reset a forgotten PIN or remove a student from the dashboard. Pick one way.

**Option A: in the browser.** Go to **Edge Functions → Deploy a new function → Via Editor**, name it `manage-student`, paste in the contents of `supabase/functions/manage-student/index.ts`, and click **Deploy**.

**Option B: with the Supabase command line.**
```bash
npm install -g supabase        # or: brew install supabase/tap/supabase
supabase login
supabase link --project-ref YOUR-PROJECT-REF
supabase functions deploy manage-student
```
Everything else works without this step. Only Reset PIN and Remove need it.

### 7. Put the site online
Upload the **`public`** folder to any static host.
- **Vercel or Netlify:** create a new project and drag in the `public` folder. Both have free plans.
- **GitHub Pages:** push the folder to a repo and turn on Pages.
- To use your own address such as `play.moneyhubnyc.co`, add it as a custom domain on the host and add the DNS record they show you.

The game is then at `https://your-site/` and the dashboard at `https://your-site/teacher.html`.

### 8. Try it before class
1. Open `teacher.html`, log in, and create a class such as `TEST-1`.
2. In a private browser window, open the game → **Create account** → class code `TEST-1`, any username, a 6-digit PIN → play the first milestone.
3. Back in the dashboard, the student appears in the roster with 1/8 progress. Try **Big screen**, **Class events → Send**, and **Reset PIN**.
4. Remove the test student, or archive the class.

---

## How it works in class

1. Create a class in the dashboard and write the **class code** on the board.
2. Students open the game → **Create account** → class code, a username, the name the class sees, and a 6-digit PIN. Next time they choose **Log in**.
3. Progress saves automatically: within a few seconds, after every milestone, and when the tab closes.
4. Use **Big screen** on the projector and **Class events** to shake things up mid-session.
5. A forgotten PIN: Roster → **Reset PIN** → type a new one → tell the student.
6. Afterward, **Export CSV** gives you milestones, scores and activity for your records or a funder report.

Students can still pick "Play without an account". Their progress then stays on that device only and they won't appear on the board.

---

## Costs and limits (Supabase free plan)

- **Accounts, saves, leaderboard, class events:** small. The free plan covers many classes. Free projects pause after a week with no activity, and you unpause them from the dashboard. The Pro plan ($25/month) never pauses.
- **Shared world (classmates' avatars):** this is the one feature that uses meaningful realtime traffic. Students are grouped 8 to a "squad", and positions are sent at most about once a second while moving. Supabase's free plan allows 100 realtime messages per second and 2 million a month. Expect a full class of 30 to use a few hundred thousand messages per class-hour and to brush against the per-second limit at busy moments. For regular use with full classes, the **Pro plan** is the safer choice (500 messages/second, 5 million/month, then $2.50 per extra million). To switch the shared world off, set `sharedWorld: false` in `config.js`. To reduce traffic, raise `positionIntervalMs`.

These numbers are estimates. Check **Reports → Realtime** in Supabase after your first session.

---

## Student data and privacy

- What's stored: a username, a display name the student chooses, the class, game progress, scores and timestamps. No email, phone, birthday or real name is required. Students are told not to use their full name or a PIN they use elsewhere.
- Students can only ever see their own data plus their class's leaderboard (display names and scores). Facilitators see only classes they created. This is enforced by the database, not the web page.
- If you run this with NYC public schools, student data is covered by **NY Education Law 2-d**. The school or district will likely ask for a data privacy agreement and your data security plan. CUNY and nonprofit partners may have their own requirements. Check with each partner before rollout.
- To delete a student's data: dashboard → **Remove**. This deletes the login, profile, progress and run history.

## Known limits

- Scores are calculated in the student's browser. The database caps them at 16,000 and keeps each student's best score, but a determined student with browser developer tools could still post a fake score. That's fine for classroom motivation. Don't use these scores for grades or prizes with real value.
- A 6-digit PIN is light security, which suits a classroom game. Don't reuse this login style for anything sensitive.
- The claude.ai version of the game keeps working as before, with its own separate leaderboard. The two don't share data.

## Upgrading from the first version
If you already ran `schema.sql` before the 3-level update, run the new `schema.sql` again in the SQL Editor. It widens the limits for 20 milestones and 60 stars without touching any student data.

## Updating the game later
Edit `src/game.html` (or replace it with a new version of the claude.ai game file), then run:
```bash
python3 build.py
```
and re-upload `public/index.html`.
