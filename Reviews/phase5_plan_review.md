# Phase 5 Plan Review — RAG Chatbot via Edge Function

> **Gate B — Plan Review.** Reviewer: Claude (per `MASTER_CONTEXT.md` section 5).
> Subject: Phase 5 Implementation Plan (`1780656552010_implementation_plan.md`).
> This file is authoritative plan-review feedback for the Antigravity agent.

## Verdict: REVISE

Phase 5 is the highest-stakes phase of the project for non-negotiable constraint #1
(no secrets in the app) and constraint #4 (no medical advice). The plan's *direction*
is right — Edge Function, 768-dimension embeddings, server-side key, grounded prompt —
but four required Gate B items from the Phase 4 review are not in the plan, and one
section is technically wrong. Send a revised plan addressing the six items in "What is
needed before approval" below. **No Phase 5 code is written until Gate B is cleared.**

---

## What the plan got right

- **Architecture is correct.** Edge Function authenticates the JWT, embeds with
  Gemini, retrieves from `rag_documents`, generates with Gemini, logs to
  `chatbot_logs`. This matches the guide's Phase 5 design.
- **Embedding model dimension is correct.** Gemini `text-embedding-004` outputs
  768 dimensions, matching `rag_documents.embedding vector(768)` — pending the
  deprecation check in Gap 5a below.
- **Grounding banner in UI** — correct defense-in-depth alongside the system prompt.
- **Three manual-test cases are exactly the right tests** — clinic FAQ (grounded
  answer), hallucination bait (graceful "I don't know"), and medical-advice bait
  (redirect to staff).

---

## Gap 1 — The system prompt is missing entirely (CRITICAL)

The Phase 4 review checklist required: *"the exact system prompt for Gemini — Claude
will read this closely. It must enforce: answer only from provided clinic content; if
unknown, say so and suggest contacting the clinic; never give medical advice, interpret
lab values, or diagnose (constraint #4)."*

The plan describes intent — "prepares a strict, grounded context prompt enforcing
medical non-advice boundaries" — but does not contain the prompt text. Intent is not
reviewable.

The system prompt **is** the enforcement mechanism for constraint #4. There is no human
reviewer between Gemini's output and the patient. The prompt is the single most
important text in this phase, so it must go through Gate B explicitly.

**Action:** include the verbatim system prompt in the revised plan. At minimum it must
cover:
- Role definition (administrative assistant for a medical clinic).
- Hard rules: only use provided context; if information is not in the context, say so;
  never diagnose, interpret lab values, recommend treatment, or substitute for a
  clinician; redirect medical questions to clinic staff.
- The input shape it will receive (retrieved chunks + the user question).
- The output shape it should produce.

---

## Gap 2 — `match_rag_documents` is a new schema proposal, and the plan implies it already exists

Step 4 calls `match_rag_documents`. The User Review section says "ensure the SQL schema
patch (defined in `web_reference/schema_proposals.md`) has been applied to the target
database."

Two problems:

1. **The function is not in `schema_proposals.md` yet.** As of Phase 4, that file holds
   the `patients` INSERT policy and the Storage policies — no RPC. So this is a **new**
   mobile-originated schema proposal, not an existing one being referenced.
2. **The phrasing "ensure the patch has been applied" risks repeating the Phase 2
   unilateral-CREATE pattern.** Spell out the handling: file in `schema_proposals.md`,
   send to the web team, apply on the mobile project as the working stand-in, add to
   the Phase 6 merge checklist. Same pattern as the prior proposals. No `CREATE
   FUNCTION` first and propose after.

**Action:** add the full SQL of `match_rag_documents` to `schema_proposals.md`.
Suggested shape (confirm exact column shape with the web team):

```sql
create or replace function match_rag_documents(
  query_embedding vector(768),
  match_count int default 5
)
returns table (id uuid, title text, content text, similarity float)
language sql stable
as $$
  select id, title, content, 1 - (embedding <=> query_embedding) as similarity
  from public.rag_documents
  order by embedding <=> query_embedding
  limit match_count;
$$;
```

The HNSW `vector_cosine_ops` index already present in the canonical `schema.sql` will
be used by this function.

---

## Gap 3 — Knowledge-base ownership and `service_role` location not stated

The Phase 4 review checklist required: *"Knowledge-base ingestion approach — coordinate
with the web team so `rag_documents` is shared, not duplicated."* The plan describes
`ingest_knowledge.ts` as a mobile-team script that populates `rag_documents` using the
`service_role` key. If the web team also runs an ingestion pipeline, two divergent
copies of clinic policy land in `rag_documents`.

**Action — state explicitly:**
1. Who owns the knowledge base? Options: (a) the web team owns it and the mobile team
   reads only; (b) one shared ingestion script lives in one repo with both teams
   agreed; (c) both teams ingest with a stated deduplication strategy. State which.
2. Where is the `service_role` key stored for running ingestion? It must be a
   developer-machine local secret, never in the mobile repo, never in CI. Confirm.

---

## Gap 4 — The `chatbot_logs` insert payload is not spelled out

Same pattern as Phase 4's `extracted_metadata` gap. The plan says the Edge Function
"logs the transaction into `chatbot_logs`" — but no column-by-column payload. The
schema has `user_id`, `session_id`, `user_message`, `bot_response`, `tokens_used`,
`feedback`.

**Action — lock these down in the plan:**
- **`session_id`** — what generates it (client-side UUID? Edge Function?), where is it
  stored on the client (memory? Drift?), when does it rotate (per app launch? per X
  hours?). Decide and state.
- **`tokens_used`** — total tokens (prompt + completion), or broken down? The column is
  `integer`, so total is likely. State which.
- **`feedback`** — null at insert; updated later via `toggleFeedback`. Verify the
  existing RLS policies allow the user to update their own log row — if not, that is
  another schema proposal.
- **Critical security decision: does the Edge Function insert as the authenticated
  user (using their JWT context) or as `service_role`?** It must be the user, so the
  existing "user can insert own logs" RLS policy fires correctly. State this
  explicitly.

---

## Gap 5 — Two technical errors

### 5a — `text-embedding-004` deprecation risk
The model has been in Google's lineup for a while; Google has been pushing newer
Gemini embedding models since. Before building, **verify against current Google AI
Studio documentation** that:
- `text-embedding-004` is still available, and
- its output dimension is still 768.

If the model has been deprecated or replaced, switch to the current replacement **only
if** the replacement's dimension is also 768. If the dimension differs, that is a
schema problem (`rag_documents.embedding` is `vector(768)`) and you must either choose
a different model or file a schema proposal to change the column dimension. Do not
silently use a non-768 model.

**Action:** add a verification step in the plan and state the confirmed model + its
dimension before building.

### 5b — "Locally" in the medical-advice filter wording
Verification plan, safety checks, step 2 says: *"verify that prompt styling handles
empty answers and blocks medical inquiries locally/remotely."*

"Locally" is the wrong word here. There is **no** client-side medical-advice filter,
and there should not be — a client-side keyword blocker is brittle and trivially
bypassed (e.g., by spelling variations or non-English queries), and it would give a
false sense of security. All enforcement of constraint #4 lives in the Edge Function's
system prompt.

**Action:** remove "locally" from the safety-check wording so nobody builds a fragile
client-side filter.

---

## Smaller items (not blockers but address in the revision)

- **Chat model choice.** The plan mentions `gemini-1.5-flash`. Fine for the demo;
  verify it is still the current price/quality tradeoff (Gemini's lineup has shifted).
  Document the chosen model and a one-line reason.
- **Placeholder data must be labeled as such.** The "Open Questions" recommendation
  to ingest sample clinic documents covering hours, services, submission guidelines,
  and pricing is sensible — but mark the data clearly as "placeholder for capstone
  demo," not real clinic policy. The clinic will need to provide real content before
  any real patient uses the system. State this in the plan.

---

## What is needed before approval

Send a revised plan that adds:

1. **The verbatim system prompt** for the Edge Function (Gap 1).
2. **The full `match_rag_documents` SQL**, filed in `schema_proposals.md`, with the
   correct propose-then-apply handling (Gap 2).
3. **A stated decision on who owns the knowledge base** and where the `service_role`
   key lives for ingestion (Gap 3).
4. **The `chatbot_logs` insert payload column-by-column**, with the JWT-vs-service-role
   decision named explicitly (Gap 4).
5. **Confirmation that `text-embedding-004` is still the current 768-dim model**
   (verified against current docs) or the chosen replacement with confirmed dimension
   (Gap 5a).
6. **Removal of "locally"** from the medical-advice filter wording (Gap 5b).

This is a revision, not a rewrite — most of it is text the agent can produce in one
pass.

---

## Status & next gate

- **Gate B for Phase 5: REVISE.** Do not begin Phase 5 building. Address the six items
  above and resubmit the plan for a second Gate B review.
- Carry-over: `schema_proposals.md` must be **actually sent** to the web team.
  Phase 5 adds the `match_rag_documents` function to that same file, increasing the
  reconciliation cost of further delay.

## Guidance for the Antigravity agent

1. **The system prompt is the security artifact, not its description.** When a review
   asks for "the exact prompt," paste the verbatim text. The prompt's wording is what
   gets reviewed — descriptions of intent cannot be.
2. **Every schema artifact introduced by the mobile team is a proposal.** A SQL
   function, a policy, a bucket, an index — anything not in the web team's canonical
   `schema.sql` goes through `schema_proposals.md` and gets sent to the web team. No
   exceptions; the propose-then-apply pattern is not negotiable.
3. **Server-side identity is part of the design, not an implementation detail.**
   Whether an Edge Function calls Postgres as the authenticated user (JWT) or as
   `service_role` is a security decision that must be in the plan. RLS policies depend
   on which one is used.
4. **No client-side safety filters for medical advice.** They are bypassable and
   create false confidence. All enforcement lives in the system prompt server-side.
5. **Verify model availability against current docs.** Embedding and chat model
   lineups change. A model name from a few months ago may be deprecated. The plan
   must state the verification step.
