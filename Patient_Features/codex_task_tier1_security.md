# SPEC — Tier 1 Security Hardening (Sequenced)

**KlinikAid Mobile (Flutter/Android). Coder: ChatGPT Codex. Reviewer gates the
plan (Gate B) and the on-device walkthrough (Gate D).**

Three security phases, built **in order** (SEC2 depends on SEC1). Each is its own
build cycle: plan → Gate B review → build → real-device walkthrough → Gate D.
Do NOT bundle all three into one PR.

---

## STANDING RULES (apply to every phase — read fully)

- **Investigate before changing.** Each phase starts by reading the current local
  code and reporting what's actually there. Do not change code before confirming
  the current state.
- **Trim testing budget.** Per change: one regression guard + one critical happy
  path. No exhaustive permutations. Run only touched test files during
  iteration; full suite once at the end.
- **Mock all external channels** in tests — Supabase, auth, secure storage,
  platform channels. Never a live client, never a real device write in a unit
  test. Unmocked async tests hang and waste time.
- **Real-device verification is mandatory.** Emulators do not faithfully
  reproduce Keystore/Keychain, scoped storage, or encrypted DB behavior.
- **Release build is required proof for SEC1 and SEC2.** Both add native
  dependencies. `flutter test` passing does NOT prove the app builds — manifest
  merges, R8/proguard, and NDK/native clashes only surface at
  `flutter build apk --release`. Run it as part of Gate D. "All tests passed" is
  not build proof.
- **No images/mockups** in plans or walkthroughs.
- **Do not claim a check you did not run.** If you didn't decompile the APK and
  grep it, say so — don't report a grep result you fabricated. Terse pass/fail
  output only.

---

## PHASE SEC1 — Secure Token Storage

**Problem:** auth tokens / session are persisted in **unencrypted
`shared_preferences`** — plaintext credentials on a device handling patient data.
**Goal:** move all tokens/session to **`flutter_secure_storage`** (encrypted
Android Keystore).

### Investigate first (report before changing)
1. Enumerate every `shared_preferences` key that holds a token, session,
   refresh token, or credential.
2. **How is the Supabase session persisted?** The biggest token is the Supabase
   auth session, persisted by the `supabase_flutter` SDK's storage accessor
   (varies by SDK version — older `localStorage`, newer
   `gotrueAsyncStorage`/`authFlowType` storage). Identify the installed
   `supabase_flutter` version and exactly how/where it stores the session. This
   is the core of the task — securing tokens is NOT just moving a few manual
   keys; it's overriding the SDK's session persistence.

### Changes
- Add `flutter_secure_storage`.
- Provide a **custom storage accessor backed by `flutter_secure_storage`** to
  `Supabase.initialize(...)` so the SDK persists the session into the encrypted
  keystore instead of `shared_preferences`.
- Move any manually-stored tokens/credentials to secure storage; **never store
  raw passwords** anywhere — confirm none are.
- **One-time migration on upgrade:** on first launch after this change, if legacy
  tokens exist in `shared_preferences`, copy them into secure storage, then
  delete them from `shared_preferences` — so already-logged-in users are NOT
  logged out.
- `clearAll()` on logout must also clear secure storage.

### Tests (mocked)
- Unit: the secure-storage wrapper reads/writes/deletes correctly.
- Unit: migration — legacy prefs token → secure storage, and the prefs entry is
  removed afterward.
- The Supabase session storage accessor is mocked; assert writes route to secure
  storage, not prefs.

### Real-device verification
1. Log in, kill the app, reopen → **still logged in** (session persisted
   securely).
2. Inspect the app's `shared_preferences` XML on device → **no tokens/session**
   present.
3. Logout → secure storage cleared.
4. **`flutter build apk --release` succeeds** (new native dep).
5. APK decompile + grep for secrets → 0 matches (run it for real, or state you
   didn't).

**Release build required.** Note `flutter_secure_storage` Android min-SDK /
Keystore requirements if the build surfaces any.

---

## PHASE SEC2 — Encrypt Local Data at Rest (depends on SEC1)

**Problem:** the Drift/SQLite cache is **unencrypted** — patient records in
plaintext on-device (RA 10173 data-protection issue). `clearAll()` on logout
helps but does nothing for data-at-rest **while logged in**.
**Goal:** encrypt the local database with **SQLCipher**, keyed from secure
storage (SEC1).

> **Approach is SQLCipher-encrypted Drift** (keeps offline capability). If
> investigation shows the SQLCipher/native integration is disproportionately
> heavy, the fallback is "**do not cache sensitive patient data locally**"
> (simpler, but loses offline). Recommend SQLCipher; raise the fallback at Gate B
> if integration is a problem — do not silently switch approaches.

### Investigate first (report before changing)
1. What does the Drift DB currently cache, and **which tables hold sensitive
   patient data**?
2. Confirm the cache is **derived** (re-fetchable from the server) — this decides
   the migration strategy.
3. Current Drift setup: is it using `sqlite3_flutter_libs`? (SQLCipher swaps this
   for `sqlcipher_flutter_libs`.)

### Changes
- Swap to `sqlcipher_flutter_libs` and open the Drift database with a
  `PRAGMA key` set from a **randomly generated passphrase stored in
  `flutter_secure_storage`** (generate once on first run; reuse thereafter).
  This is why SEC1 lands first — the DB key lives in the secure store.
- **Migration:** since the DB is a derived cache, on upgrade **drop the old
  unencrypted database and recreate it encrypted** (data re-syncs from the
  server). Do not attempt in-place re-encryption. Confirm nothing user-authored
  lives only in the cache before dropping.
- Keep `clearAll()` on logout.

### Tests (mocked)
- Unit: the DB opens successfully with the key read from (mocked) secure storage.
- Unit: a cached read/write round-trips through the encrypted DB.
- Regression: existing cache-backed screens still read their data after the swap.

### Real-device verification
1. App runs normally; cached data loads (re-synced) after upgrade.
2. **Pull the `.db` file off the device and confirm it is NOT readable as plain
   SQLite** — running `strings`/opening it shows no patient data, and it can't be
   opened without the key. This is the at-rest proof.
3. **`flutter build apk --release` succeeds** (SQLCipher native libs → this is
   the phase most likely to hit R8/proguard/NDK issues; the release build is the
   real proof).

**Release build required.**

---

## PHASE SEC3 — Server-Authoritative Lab Flag

**Problem:** mobile computes `isFlagged` client-side and submits it as truth — a
tampered client could store a normal result on an abnormal value.
**Goal:** the **server** decides the flag; mobile stops persisting its client
flag as the source of truth.

### Investigate FIRST — this decides whether SEC3 is even a mobile-only change
Mobile writes **directly to the database** via the anon key + RLS — it does **not**
go through the web team's Next.js API route. So web's route-level flag recompute
does **NOT** cover mobile's writes. Determine:

- **Is the server-side flag recompute a Postgres trigger/function on the table**
  (runs for every writer, including mobile's direct insert), **or is it
  Next.js-route-only** (never touches mobile)?
  - Confirm by reading the shared DB schema (`schema.sql`) for a trigger/function
    that sets/overwrites the flag on `INSERT`/`UPDATE` of the relevant records
    table, or by asking the web team.

**Branch:**
- **If a DB trigger exists** → mobile just stops sending `isFlagged` as truth (let
  the DB set it) and treats the DB's stored value as authoritative on read.
  Mobile-only change.
- **If route-only (no DB trigger)** → mobile CANNOT be made server-authoritative
  by a mobile change alone. The real fix is **adding a DB trigger** to the shared
  backend = web-team / shared-DB coordination. In that case: make the mobile
  change anyway (stop trusting client flag), and **flag clearly that the
  integrity guarantee is incomplete until the DB trigger is added** — do not
  claim server-authoritative flagging works if nothing recomputes for mobile.

### Changes (mobile side, both branches)
- Keep computing `isFlagged` **for UX only** — the flagged-value confirmation
  popup and the analytics reference bands still need it locally.
- **Stop persisting the client flag as truth:** on insert, either omit the flag
  column (let the DB default/trigger set it) or, if it must be sent, treat the
  **DB's stored value as authoritative on read-back**. Do not display or store
  the client-computed flag as the record's official flag.

### Tests (mocked)
- Unit: the insert path no longer sends the client `isFlagged` as the persisted
  truth (or the read path uses the DB value).
- If a DB trigger is confirmed: a submitted abnormal value with a forced-normal
  client flag results in the **DB-stored flag = abnormal** (test against the
  documented trigger behavior; mock the backend response accordingly).

### Real-device verification
1. Submit a result where the client flag is (artificially) wrong → the stored/
   displayed flag reflects the **server** decision, not the client's.
2. UX unaffected: the confirmation popup and analytics bands still work.
3. No native/dep change here → release build not required (state it). No secret
   surface changed → APK grep N/A (state it).

---

## Sequencing summary
1. **SEC1** (secure token storage) — foundational; SEC2's DB key depends on it.
2. **SEC2** (encrypt-at-rest) — uses SEC1's secure storage for the DB key.
3. **SEC3** (server-authoritative flag) — independent; gated on the write-path
   investigation, may require web-team DB-trigger coordination.

Each phase: plan → **Gate B** (reviewer) → build → real-device walkthrough →
**Gate D** (reviewer). SEC1 and SEC2 include a passing `flutter build apk
--release`.
