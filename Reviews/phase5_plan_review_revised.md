# Phase 5 Plan Review (Revised) — RAG Chatbot via Edge Function

> **Gate B — Plan Review (Round 2).** Reviewer: Claude (per `MASTER_CONTEXT.md`
> section 5).
> Subject: Revised Phase 5 Implementation Plan (`1780656810109_implementation_plan.md`).
> This file supersedes `phase5_plan_review.md` and is authoritative plan-review
> feedback for the Antigravity agent.

## Verdict: APPROVED WITH CHANGES — proceed to build

The revised plan addresses all six items from the prior review. Two technical
corrections are required during the build, plus three smaller items to fold in. None
of these requires another Gate B round — the agent should incorporate them during
Gate C and report the resolutions in the Phase 5 walkthrough at Gate D.

---

## Gap-by-gap status from the previous review

### Gap 1 — System prompt: RESOLVED
The verbatim prompt is well-constructed. The role definition is concrete (named clinic
and location). The three numbered safety rules are clear. Using **"respond EXACTLY
with"** for both the medical-advice case and the unknown-answer case is a strong
technique — it gives Gemini a deterministic fallback instead of forcing it to compose.
The grounding clause "do not assume, extrapolate, or use outside knowledge" is the
right wording for constraint #4. Good prompt.

### Gap 2 — `match_rag_documents` proposal: RESOLVED
Documented in `schema_proposals.md` Section 3, with the explicit "deploy on our working
database instance first" propose-then-apply pattern. Consistent with how the `patients`
INSERT policy and Storage policies are being handled.

### Gap 3 — Knowledge base ownership: RESOLVED, and improved
- Web team owns the production ingestion portal; mobile team's script is for testing.
- `service_role` lives in a developer-local `.env`, git-ignored.
- Demo data is tagged `is_placeholder: true` in `metadata` jsonb — better than the
  reviewer's prior suggestion, since cleanup becomes a one-row WHERE clause.

### Gap 4 — `chatbot_logs` payload: RESOLVED
Every column documented, `session_id` lifecycle defined (in-memory; rotates on tab
exit or logout), token-counting source named (`usageMetadata.totalTokenCount`), and the
critical security decision is explicit: the Edge Function initializes its Supabase
client with the user's JWT, so the insert runs under the user's RLS. That is the
correct answer for constraint #9.

### Gap 5a — Embedding model: RESOLVED and improved
The agent dropped `text-embedding-004` and switched to `gemini-embedding-001` with
`output_dimensionality: 768`. This is the better choice — `gemini-embedding-001` is
Google's Matryoshka-style embedding model with configurable output dimension, so 768
is a direct target match for `rag_documents.embedding vector(768)`. See Correction 1
below for the normalization detail this introduces.

### Gap 5b — "Locally" wording: RESOLVED
Verification now occurs on the Edge Function with mock tests for response states. No
client-side filter — correct per constraint #4.

---

## Correction 1 — Embedding normalization needs a clear reason and location

Step 4 of the Edge Function description says: *"Normalizes the vector values in
memory."*

This is a `gemini-embedding-001` detail worth getting right. Because the model is
Matryoshka-style, truncating from the default to 768 produces embeddings that are **no
longer unit-normalized.** For pgvector's `<=>` cosine-distance operator (already used
by the schema's HNSW index), this does not affect correctness — cosine distance is
invariant to magnitude. It would matter only for L2 or inner-product distance.

Two problems with the plan as written:
1. "In memory" is vague — normalize *where*? In the Edge Function before the RPC call?
   Inside the Postgres function?
2. The normalization step is unjustified given the current `<=>` cosine operator.

**Action — pick one:**
- **Keep it**, with a stated reason and location: e.g., "normalized in the Edge
  Function before the RPC call, so future swaps to L2 or inner-product distance keep
  working." Document it in the plan/walkthrough so a panelist's question has a clean
  answer.
- **Drop it** as unnecessary for the cosine operator.

**Critical sub-action — identical embedding config across both code paths.** The
`ingest_knowledge.ts` script must use the **same model**, **same
`output_dimensionality: 768`**, and **same normalization choice** as `index.ts`. If
they diverge, query embeddings and stored embeddings live in different spaces and
retrieval quality silently degrades. State this in the plan explicitly.

---

## Correction 2 — `loadHistory()` behavior across sessions is undefined

`session_id` is stored in memory and rotates on tab exit or logout. Edge case: if the
user force-closes the app, in-memory state is lost; a new `session_id` is generated on
relaunch. That is fine for new sessions.

But `chatbot_logs` rows are filtered by `user_id`, not `session_id`. So
`loadHistory()` will pull **all** prior logs across sessions. Over time, that grows
indefinitely.

**Action — decide which and document it:**
- (a) `loadHistory()` filters to the current `session_id` — a fresh launch shows an
  empty chat.
- (b) `loadHistory()` shows all prior logs, rendered with a grouping or "previous
  session" divider.
- (c) `loadHistory()` shows the last N logs only (paginate older).

Right now the plan is silent on this. Pick one and document it before the build.

---

## Smaller items (fold into the build, not blockers)

- **"préparer" typo.** The `ingest_knowledge.ts` description says *"préparer
  guidelines for ECG/ultrasound/fasting"*. Likely an autocomplete artifact for
  "preparation." Minor; fix in the doc trail.
- **`chatbot_logs` UPDATE RLS — verify before wiring `toggleFeedback`.** The schema
  likely already allows users to update their own logs (consistent with other
  patient-owned tables), but verify against `web_reference/schema.sql` before the
  build. If the policy is missing, file in `schema_proposals.md` as a new mobile
  proposal — same handling as everything else, no unilateral `CREATE POLICY`.
- **"Fast duration?" quick-chip ingestion.** The chip won't dead-end into "I don't
  have information about that" only if the corresponding fasting-requirements entry is
  actually ingested. Coordinate the quick-chip list with the ingested content so every
  chip resolves to a real answer.

---

## Carry-overs piling up — must leave the mobile team's side

`schema_proposals.md` now contains three items:
1. `patients` INSERT policy (Phase 2)
2. Storage policies for `patient-documents` bucket (Phase 4)
3. `match_rag_documents` function (Phase 5)

Phases 2, 3, and 4 remain CONDITIONAL until the file is **actually sent** to the web
team. The reconciliation cost compounds. **Action: send the file to the web team
before the Phase 5 build is complete.** Two reasons: (a) the web team has time to
react before Phase 6's merge; (b) the mobile build is developed against a reasonable
approximation of the final canonical schema.

---

## Status & next gate

- **Gate B for Phase 5: APPROVED WITH CHANGES.** Proceed to **Gate C (Build)**. The
  five corrections do not require another Gate B; the agent incorporates them during
  the build and reports resolutions in the Phase 5 walkthrough at Gate D.
- **Gate D for Phase 5 will be reviewed closely on the security side.** The reviewer
  will examine the actual deployed system prompt, the actual Edge Function code, the
  actual `chatbot_logs` rows produced, and the results of the hallucination-bait and
  medical-advice-bait tests.

## Guidance for the Antigravity agent

1. **State the reason for every cryptographic-or-numeric step in the data path.**
   "Normalize the vector in memory" without a reason invites the question "why?" at
   defense. Either justify or remove. Same for distance metric, dimension, chunk size,
   anything that affects retrieval quality.
2. **Two code paths into the same vector column must share identical embedding
   config.** Query-side and ingest-side embeddings must use the same model, same
   dimension, same normalization. If they drift, retrieval silently degrades — and the
   bug is hard to detect because every query still returns *something*.
3. **Define what user-visible state shows after restarts.** `loadHistory()` across
   sessions is a UX question with no obvious default; pick the behavior, document it,
   and test it. Don't leave restart-time behavior implicit.
4. **Verify RLS coverage before implementing every write operation.** Before wiring
   `toggleFeedback`, confirm the UPDATE policy on `chatbot_logs` exists. The pattern
   is: check `schema.sql`; if missing, propose; if present, proceed. Never assume.
5. **Send `schema_proposals.md` to the web team during Phase 5.** Three mobile
   proposals are now sitting in that file. The longer it stays unsent, the worse the
   pre-Phase-6 reconciliation will be.
