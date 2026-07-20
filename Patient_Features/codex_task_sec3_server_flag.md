# SPEC — SEC3: Server-Authoritative Lab Flag

**KlinikAid Mobile (Flutter/Android). Coder: ChatGPT Codex. Reviewer gates the
plan (Gate B) and the on-device walkthrough (Gate D).**

## STANDING RULES (read fully — this brief is self-contained)
- **Investigate before changing.** Report the current state before writing code.
- **Trim testing:** one regression guard + one critical happy path; run touched
  test files during iteration, full suite once at end.
- **Mock all external channels** (Supabase/auth/platform) — never a live client.
- **Real-device verification** is mandatory.
- **No native/dep change is expected here → release build not required** (state
  it). If that turns out wrong and you touch deps/manifest/native, then
  `flutter build apk --release` IS required at Gate D.
- **No images/mockups.** Terse pass/fail. **Do not claim a check you didn't run.**

---

## Problem
Mobile computes `isFlagged` client-side and submits it as the stored truth. A
tampered client could persist a "normal" flag on an abnormal value — an
integrity gap on a medical app.

## Goal
The **server/database** decides the persisted flag. Mobile keeps computing the
flag **for UX only** and stops persisting its own value as truth.

---

## INVESTIGATE FIRST — this decides whether SEC3 is even a mobile-only change

Mobile writes **directly to the database** via the anon key + RLS. It does **not**
go through the web team's Next.js API route. So any flag recompute that lives in
a web route does **NOT** run for mobile's writes.

Determine, from the shared DB schema (`schema.sql`) or the web team:

- **Is the server-side flag recompute a Postgres trigger/function on the records
  table** (fires on every `INSERT`/`UPDATE`, including mobile's direct write),
  **or is it Next.js-route-only** (never touches mobile)?

Report which, with the evidence (the trigger/function definition, or confirmation
none exists on the table).

### Branch on the finding
- **DB trigger exists** → mobile is already covered on write. Mobile change is
  small: stop sending `isFlagged` as truth (let the trigger set it) and treat the
  DB's stored value as authoritative on read-back.
- **Route-only / no DB trigger** → mobile **cannot** be made server-authoritative
  by a mobile change alone. Make the mobile change anyway (stop trusting the
  client flag), but **state clearly that the integrity guarantee is incomplete
  until a DB trigger is added to the shared backend** (web-team / shared-DB
  coordination). Do NOT claim server-authoritative flagging works if nothing
  recomputes for mobile's writes.

**Stop after investigation and report the branch before coding** if the finding
is "route-only" — that outcome needs a coordination decision, not just code.

---

## Changes (mobile side — both branches)
- **Keep** computing `isFlagged` locally **for UX only**: the flagged-value
  confirmation popup and the analytics reference bands still need it. Do not
  remove that.
- **Stop persisting the client flag as truth.** On insert, prefer to **omit the
  flag column** so the DB default/trigger sets it. If the column must be sent,
  then on read-back treat the **DB-stored value as authoritative** and display
  that — never the client-computed value — as the record's official flag.
- Do not change the reference-range values or the flag *computation* logic itself
  (that's the placeholder-range topic, out of scope here).

## Tests (mocked)
- Unit: the insert path no longer persists the client `isFlagged` as truth (omits
  it, or the read path uses the DB value).
- If a DB trigger is confirmed: simulate a submitted abnormal value carrying a
  forced-"normal" client flag → assert the authoritative (DB) flag is abnormal
  (mock the backend/DB response per the trigger's documented behavior).
- Regression: the flagged-value confirmation popup and analytics reference bands
  still work off the local UX computation.

## Real-device verification
1. Submit a result where the client flag is (artificially) wrong → the
   **stored/displayed** flag reflects the **server** decision, not the client's.
   (If route-only was found, this instead documents that the client flag is no
   longer persisted as truth, pending the DB trigger.)
2. UX unaffected: confirmation popup + analytics bands still function.
3. No native/dep change → **release build not required** (state it). No secret
   surface changed → APK grep N/A (state it).

---

## Reviewer note
Gate B will not clear the *code* until the write-path branch is reported. If it's
route-only, the mobile change ships but SEC3's integrity goal is only partially
met — that must be stated honestly, not glossed.
