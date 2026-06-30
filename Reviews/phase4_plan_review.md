# Phase 4 Plan Review — Edge OCR & Document Submission

> **Gate B — Plan Review.** Reviewer: Claude (per `MASTER_CONTEXT.md` section 5).
> Subject: Phase 4 Implementation Plan (`1780375572355_implementation_plan.md`).
> This file is authoritative plan-review feedback for the Antigravity agent.

## Verdict: APPROVED WITH CHANGES

The plan is strong. It correctly handles every Phase 4 entry condition, closes most of
the carry-over items, and the technical design is sound. Five concrete changes must be
incorporated before the build is considered complete, plus two smaller notes. The
revised plan does not need to be re-submitted for Gate B — the changes can be
incorporated and the resolution reported in the Phase 4 walkthrough at Gate D.

---

## What the plan got right

- **Gate B acknowledgment is direct and honest.** No euphemism; explicit commitment to
  the four-gate protocol going forward. This closes the process item from Phase 3.
- **All four Phase 2 open questions answered.** "Deferred" is acceptable for guest
  access and MFA. The email-confirmation disclosure (disabled for dev/test on the
  mobile project; to be coordinated with the web team before staging) is exactly the
  kind of explicit decision that was missing.
- **`patients` UPDATE policy check performed.** The policy is quoted from
  `schema.sql` line 193 and is sufficient. This closes the schema risk flagged in the
  Phase 3 review for the Profile edit feature.
- **Offline submission routes through `OfflineDocumentsQueue`** — correctly uses the
  Drift table built as Phase 3 groundwork.
- **Bucket/path convention is sensible** (path-prefixed by `auth.uid()`).

---

## Change 1 — Storage RLS policies are a NEW schema proposal, not a confirmed item

The plan presents the Storage bucket + four policies under "User Review Required," but
those policies **do not exist in the canonical `schema.sql`** — that file covers public
tables only. So the Storage policies are not a "we confirmed it" item; they are a new
**mobile-originated schema proposal**, the same status as the `patients` INSERT policy.

**Action:**
- File the Storage proposal in `web_reference/schema_proposals.md` alongside the
  existing entry. Both items must be adopted by the web team before the Phase 6 merge.
- Build against the mobile project as the working stand-in (consistent with how the
  `patients` INSERT policy is being handled).

**Technical correction to the policy shape.** Storage policies are written against
`storage.objects` with a path check, not against role strings. The correct shape is
roughly:

```sql
create policy "patients upload own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'patient-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
```

Same shape for SELECT. The staff-view policy should call the existing
`get_auth_user_role()` helper (already in `schema.sql`), not enumerate role strings.
Confirm exact wording with the web team — that is what proposal review is for.

---

## Change 2 — File naming will collide

`filename_timestamp.ext` with a Unix-second timestamp **will collide** if a patient
retakes within a second or rapid-fires submissions.

**Action:** use a UUID. Suggested format: `<auth.uid()>/<uuid>_<original_name>.ext`.
Dart's `uuid` package handles this. Small change; prevents a real bug.

---

## Change 3 — OCR pre-screen logic is too vague to test or defend

"Pre-screen recognized OCR text for keywords like doctor signature, patient name, lab
request, and date" is not precise enough. ML Kit recognizes **text**, not images of
signatures — so "doctor signature" really means looking for tokens like `"Dr."` or
`"M.D."`. Say so explicitly.

**Action:** define each checklist item as something the integration test can assert.
Suggested concrete checks:
- Date pattern present (e.g. regex `\d{1,2}[/-]\d{1,2}[/-]\d{2,4}`).
- Doctor token present (`"Dr."` or `"M.D."` or equivalent).
- Patient-name match — fetch `first_name` / `last_name` from the logged-in user's
  `patients` row and check both tokens appear in the OCR text. This is a stronger
  signal than a free-text scan and uses real data already in the app.
- Request-keyword set present (define the set explicitly).

Store the matched/missing fields into `documents.extracted_metadata` (jsonb) so the
result is auditable from the web side later. Locking this down here also avoids drift
when staff reviews these documents in the web portal.

---

## Change 4 — The `documents` insert payload is not spelled out

The plan describes the insert but doesn't lock the payload column-by-column. The
following columns need explicit decisions before the build:

- **`patient_id`** — nullable in the schema, but should be set when the logged-in user
  has a `patients` row. Do not leave it null when the linkage is known.
- **`file_type`** — what goes here? The MIME type, the file extension, a canonical
  internal enum? Pick one and document it. The web app will need to interpret this
  field.
- **`extracted_metadata`** (jsonb) — define the shape. Suggested keys: `matched_fields`,
  `missing_fields`, `ocr_text_length`, `keyword_set_version` (so OCR rule changes are
  traceable), maybe `ocr_engine_version`. Lock the shape now; the web app will read it.
- **`ocr_text`** — confirm the raw OCR output is stored here in full, not summarized.

**Action:** add a "Document insert payload — column-by-column" subsection to the plan
listing every column and the value it receives.

---

## Change 5 — The offline-replay design needs one more detail

"Background/foreground synchronization that automatically uploads queued entries once
connection is restored" — good intent, but two real questions are unanswered:

1. **What triggers replay?** Options: `connectivity_plus` stream listener, app-resume
   lifecycle event, manual pull-to-refresh, or all three. Pick the set and document it.
2. **What happens if `auth.uid()` no longer matches the queued `uploader_id`** (user
   signed out and signed back in as a different account)? Silently dropping is bad
   (data loss); silently uploading anyway is worse (RLS will reject anyway, but the
   intent is wrong).

**Recommended design:**
- Trigger replay on connectivity-restore AND on app foreground.
- Before each queued upload, verify the current `auth.uid()` matches the queue item's
  `uploader_id`. If it does not, mark the queue item as **orphaned** and surface it to
  the user — do not silently drop or upload.
- Cap retry attempts per item; after N failures, mark as failed and surface to the user.

**Action:** add this design detail to the plan before building.

---

## Two smaller notes (low priority but useful)

**Note A — Automate the "no network during OCR" check.** The plan currently says to
verify this manually. Make it an automated integration-test assertion: run the OCR
step with airplane mode (or a network mock) and assert ML Kit still produces output.
This gives a stronger guarantee for the "OCR is on-device" constraint than a manual
check.

**Note B — Test-data hygiene in Storage.** Phase 4's integration test will create
real Storage objects in the mobile project. Either add a teardown that deletes uploaded
test files after the run, or use a clear test prefix in the path (for example,
`<auth.uid()>/__test__/<uuid>...`) so test artifacts can be identified and purged.
Same principle as the Phase 1 RLS test users.

---

## Status & next gate

- **Gate B for Phase 4: APPROVED WITH CHANGES.** Incorporate Changes 1–5 and the two
  smaller notes, then proceed to **Gate C (Build)**. The revised plan does not need to
  be resubmitted for Gate B — the resolution can be documented in the Phase 4
  walkthrough at Gate D.
- **Carry-over reminder:** Phases 2 and 3 remain CONDITIONAL in the tracker. The plan
  states `schema_proposals.md` will be "coordinated with the web team prior to final
  database merge" — that is not the same as **sent now**. The act of sending must
  actually happen this week. Don't let it slide; the longer it stays unsent, the more
  divergent items pile onto it (the Storage policies above are now also on the same
  proposal file).

## Guidance for the Antigravity agent

1. **A schema item is "confirmed" only when it exists in the canonical `schema.sql`.**
   Storage policies, custom buckets, table policies — anything not in the web team's
   canonical schema is a **proposal**, not a confirmed item. File it in
   `schema_proposals.md` and send it to the web team.
2. **Lock down payload shapes in the plan, not during the build.** When inserting into
   a real table, every column needs a decided value before code is written. "Will be
   populated" is not a plan-level answer.
3. **Vague verification criteria are not verifiable.** "Pre-screen for keywords" must
   become "assert the OCR text matches regex X, contains token Y, contains the
   logged-in patient's name tokens." Tests can only assert what the plan defines.
4. **Edge cases in offline replay are part of the plan, not afterthoughts.** Trigger
   conditions, identity mismatches, retry caps — define them up front. The point of
   Gate B is to catch them now.
