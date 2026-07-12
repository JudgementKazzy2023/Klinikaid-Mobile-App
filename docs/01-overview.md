# 01 — Overview: Project Scope & Boundaries

## What KlinikAid Mobile Is

KlinikAid Mobile is the Flutter/Android client for Bloodcare Medical Laboratory. It digitizes clinical intake and results processing at the point of care: patients onboard from the app, submit diagnostic referrals with their device camera (on-device OCR), receive real-time queue updates, read their lab records, and query an AI health assistant. Staff use role-scoped portals for reception, department result entry, and cross-department patient lookup.

The mobile client is one half of a two-client system. A separate web platform (repo `Setsuna-guwah/KlinikAid`, maintained by the web team) provides administration and additional staff workflows. **Both clients share a single Supabase project** — same Postgres database, same auth, same RLS policies, same Edge Functions. This document set exists partly so the web team can study how the mobile client reads and writes shared tables.

## Scope Boundaries

**In scope for the mobile client:**
- Patient self-onboarding, consent (RA 10173), profile
- Diagnostic document upload with on-device OCR + quality assessment
- Real-time patient queue notifications
- Patient record viewing (own records only)
- AI chatbot (via Supabase Edge Function, not a direct model call)
- Receptionist workstation: document validation, queue approve/route/reject, dashboard
- Department staff workstation: department-scoped daily queue, records history, **clinical result entry** (lab structured + free-text)
- Medical specialist: multi-term patient search, cross-department record timeline (read-only)

**Admin on mobile (oversight + RLS-governed management):**
- The admin role, previously blocked, now has a mobile workstation for oversight (dashboards, logs, cost tracking, cross-department records) and RLS-governed management (staff status/role edits, reception and department actions, RAG delete). It is scoped so that **no service-role operation runs on the device**.

**Out of scope — permanently web-only:**
- The **owner** role is blocked from mobile entirely.
- Service-role operations: staff account creation, password-reset emails, live-session revocation, Auth-metadata sync, and RAG document upload/embedding (server-side Gemini key). These require the service-role key, which never ships in the mobile binary.
- Backend Edge Function implementation and RAG ingestion/embedding pipeline.
- Backend Edge Function implementation, RAG document ingestion, pgvector embedding (backend-side; mobile only consumes the chat function)

## Cross-Platform Contract

The mobile client is a **consumer of a shared backend**, not the owner of it. Where mobile writes to tables the web platform also writes (`patient_queue`, `department_records`, `documents`), mobile deliberately mirrors web behavior — including quirks — to prevent cross-client divergence. Two such parity constraints are documented explicitly:

- **Constraint #12** — role-differentiated write permissions (reception and department staff evolved from read-only to write-capable; see [04-development-story](04-development-story.md)).
- **Constraint #13** — lab reference ranges and test groups are duplicated from the web platform's `constants.ts` into the mobile client, with no shared database catalog. Any web change must be manually synced. See [02-architecture](02-architecture.md) and [06-security](06-security.md).

## Audience for This Documentation

- **Web team** studying mobile's read/write patterns against shared tables — start with [02-architecture](02-architecture.md) and [06-security](06-security.md).
- **New contributors** — start with [03-setup](03-setup.md).
- **Reviewers / evaluators** — [04-development-story](04-development-story.md) and [05-features](05-features.md).
