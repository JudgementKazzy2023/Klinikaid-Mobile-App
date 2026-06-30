# Mobile Team Handoff — KlinikAid Chat Edge Function

**Audience:** Mobile (Flutter) team
**Status:** Backend-side fix for the broken chat. Mobile codebase is intentionally NOT changing.
**Owner of this doc:** Web team
**Last updated:** Pre-deployment

---

## TL;DR

The `chat` Supabase Edge Function that your `supabase.functions.invoke('chat', ...)` call was already expecting **now exists**. Once it's deployed (web team handles this), your existing mobile code should work without modification — provided your payload and response handling match the contract below.

If your chat is still broken after deploy, read the **Troubleshooting** section first.

---

## Why this was broken

Mobile was calling `supabase.functions.invoke('chat', body)`. That call resolves to a Supabase Edge Function named `chat`, but no such function had ever been deployed. Every mobile chat request hit Supabase, found no function by that name, and returned an error — which the mobile client surfaced as the error banner you've been seeing.

The web app didn't hit this issue because web uses a Next.js API route (`/api/chat`) on the same Vercel deployment, not an Edge Function.

---

## What was built

A new Supabase Edge Function at `supabase/functions/chat/` that mirrors the web's RAG chatbot pipeline. It:

1. Verifies the caller's JWT.
2. Enforces a rate limit (20 requests/hour, keyed on `user.id` — same as web).
3. Embeds the user's message with Gemini (`gemini-embedding-001`, 768 dimensions).
4. Searches the `rag_documents` knowledge base via the `match_documents` RPC (cosine threshold `0.6`, top 5 matches).
5. Generates a response with `gemini-2.5-flash`, grounded ONLY on the matched chunks.
6. Inserts a row into `chatbot_logs` and returns its `id` so you can attach feedback to that specific log.

---

## Request / Response contract

### Endpoint

```
supabase.functions.invoke('chat', { body: <request> })
```

(No change needed in mobile — keep your existing call.)

### Auth

The Supabase Flutter SDK attaches the user's JWT to `Authorization: Bearer <jwt>` automatically when invoking Edge Functions. As long as the user is signed in on the mobile client, the function gets a valid JWT.

### Request body

```json
{
  "message": "What are the clinic hours?",
  "session_id": "mobile_<your-session-uuid>"
}
```

- `message` — string, non-empty. The single user message for this turn.
- `session_id` — string, non-empty. Client-generated session identifier (recommend a UUID per chat session). The function does NOT generate one for you if omitted; it returns 400.

> Note: the web client sends a *message history array*. The mobile contract is a single message — that is intentional. The function does NOT synthesize prior turns. If you want multi-turn context-awareness in mobile, that is a future feature, not a current one.

### Response body — success (HTTP 200)

```json
{
  "response": "Our clinic is open Mondays...",
  "log_id": 4271
}
```

- `response` — the bot's answer string.
- `log_id` — integer, the primary key of the `chatbot_logs` row just inserted. Use this to attach `feedback` ('helpful' | 'unhelpful') to this specific exchange.

### Response body — error

| HTTP | Meaning | Body shape |
|---|---|---|
| 400 | Missing/invalid `message` or `session_id` | `{ "error": "..." }` |
| 401 | No valid JWT / user not signed in | `{ "error": "..." }` |
| 429 | Rate limit hit (>20 messages in the last hour) | `{ "error": "Rate limit exceeded..." }` |
| 500 | Server error (Gemini failure, env var missing, etc.) | `{ "error": "..." }` (sanitized) |

Handle 429 with the same cooldown UI you'd use for any quota response. The hourly window is rolling, keyed on the user.

---

## Deployment (web team's responsibility — informational for mobile)

These steps must happen before the function is reachable. Mobile cannot test until they're done.

1. **Set the Gemini API key as a Supabase secret** (one-time):
   ```
   supabase secrets set GEMINI_API_KEY=<the-key>
   ```
   `SUPABASE_URL` and `SUPABASE_ANON_KEY` are auto-provided by Supabase to Edge Functions; only `GEMINI_API_KEY` is manual.

2. **Deploy the function:**
   ```
   supabase functions deploy chat
   ```

3. **Verify the function appears in Supabase Dashboard → Edge Functions.** Status should be "Active."

If either step is skipped, mobile will see the same error as before (or a "GEMINI_API_KEY not configured" 500).

---

## Troubleshooting from the mobile side

Run through these in order before pinging the web team.

### "Function not found" / 404-like error
The function hasn't been deployed yet, or the name doesn't match. Confirm `chat` (exact lowercase) is listed in Supabase Dashboard → Edge Functions. If not, deployment is incomplete.

### 401 Unauthorized
The user isn't signed in, or the Supabase client is misconfigured and not attaching the JWT. Confirm `supabase.auth.currentSession` is non-null at the moment of the call.

### 429 Rate limit
Working as designed — the user sent >20 messages in the last hour. Same limit as web. Surface a friendly cooldown message; the limit clears within the hour on a rolling basis.

### 500 with no clear cause
Likely `GEMINI_API_KEY` is unset. Web team checks Supabase Edge Function logs: Dashboard → Edge Functions → `chat` → Logs.

### Bot says "I don't have that information" for a question that should work
The RAG knowledge base doesn't contain a relevant document, OR the similarity threshold filtered out a weak match. The function uses `0.6` (same as web). This is content, not code — web team needs to add the relevant document to the RAG knowledge base via `/admin/rag`.

### Bot responds with diagnostic / medical advice text
**Report immediately to web team.** The function's system prompt explicitly forbids diagnostic output. If diagnostic text appears, the prompt has drifted or been changed — this is a project-wide hard rule (no AI diagnosis on any surface). High-priority bug.

---

## Important: Two implementations of the same pipeline

The web app uses `src/app/api/chat/route.ts` (Next.js). The mobile app uses `supabase/functions/chat/index.ts` (Deno Edge Function). Both implement the same RAG pipeline against the same database.

**This means: every future change to chat behavior (rate limit, threshold, model version, system prompt, schema) must be applied to BOTH files.** If you notice web and mobile chat returning different answers to the same question, this is the likely cause. Flag it to the web team.

This duplication is a deliberate tradeoff to avoid breaking changes on the mobile side. It is documented in `documentation/ARCHITECTURE.md` and in the function's own README.

---

## What is NOT changing on the mobile side

- Your `supabase.functions.invoke('chat', ...)` call.
- Your request payload shape.
- Your response parsing (assuming you're already reading `response` and `log_id`).
- Your auth handling.
- Your `chatbot_logs` writes (the function does this; you don't write logs from mobile).

If your mobile code already matches the contract above, **no mobile code changes are needed**. If it doesn't, the diffs are small and listed in the contract section.

---

## Open items / future considerations (not blocking)

- **Mobile multi-turn context.** The function currently accepts a single message per call. If you want the bot to remember earlier turns in the same session, that requires either: mobile sends a history array (web-style), or the function reads recent `chatbot_logs` for the session_id and constructs history server-side. Pick one, talk to web team before building.
- **Feedback writes.** The function returns `log_id`. The `chatbot_logs.feedback` column is `'helpful' | 'unhelpful' | null`. You write feedback directly from mobile via `supabase.from('chatbot_logs').update({ feedback: '...' }).eq('id', log_id)`. Standard RLS applies — verify the user can update their own log rows.
- **Cross-platform chat history.** A user's `chatbot_logs` rows are not currently segmented by platform. If mobile's history view shows web-originated chats (or vice versa), that's expected — flag if it's a UX problem and we'll decide whether to silo.

---

## Contact

Web-side owner: <your name / handle>. Reach out via your usual channel if anything in this doc is unclear or out of date.
