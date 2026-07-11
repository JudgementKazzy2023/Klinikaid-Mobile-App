# 06 — Security: Authentication & Data Isolation Guards

This document is the second primary reference for the web team, since the two clients share auth, RLS, and Edge Functions.

## Authentication

Authentication is Supabase Auth via `supabase_flutter`. The client holds only the **public anon key** (injected through `env.dart` / `--dart-define`). No service-role key, Gemini key, or other server secret is present in the client — those live behind Edge Functions.

## Multi-Factor Authentication (TOTP)

Staff sessions use TOTP-based MFA with assurance levels:
- The MFA service (`lib/features/auth/data/mfa_service.dart`) enumerates verified TOTP factors, issues challenges, and inspects the session's next assurance level.
- Staff routes require **AAL2** (step-up). A session at AAL1 with a pending step-up is redirected to the TOTP verify screen (`/mfa-verify`).
- The password-change flow is MFA-aware: an AAL2 session skips current-password reauthentication; a non-MFA account reauthenticates with `signInWithPassword`.

## Route Guard Chain

Enforced in `lib/core/routing/app_router.dart` for staff routes, in this order:

```
authenticated → role match → department assigned → AAL2 (step-up MFA) → allow
```

The ordering is deliberate. Department assignment is validated **before** the MFA challenge, so an unassigned department-staff account is redirected to logout/login rather than completing TOTP and then hitting a dead end. Patients attempting staff routes (and vice versa) are redirected to their own area. Admin/owner accounts are blocked from the client entirely.

## Data Isolation

Isolation is **defense in depth** — the client scopes its queries, and the backend enforces the same scoping with RLS:

- **Department scoping** — repository read/write methods resolve the staff member's department from the session (`auth.uid()` → `profiles.department`), never from a caller-supplied argument. The backend RLS policies on `patient_queue` and `department_records` filter by the same `get_auth_user_dept()` helper. A lab account cannot read imaging data even by crafting a direct query — RLS returns an empty set.
- **Realtime channel filtering** — the department queue subscribes with a `department=eq.{dept}` filter at channel creation, so other-department inserts never reach client memory; the channel is unsubscribed on `dispose()`.
- **Patient scoping** — patients can read only their own records; RLS enforces this on `department_records`.

## AI & OCR Boundaries

- **Chatbot** — the client never contacts an AI model directly. It invokes the Supabase Edge Function `chat`; the model key and RAG/pgvector logic stay server-side.
- **OCR** — text recognition runs on-device (ML Kit). Only the extracted text is sent to the `assess-document-quality` Edge Function for scoring. No image or model key leaves the device beyond the stored document upload.

## Privacy / Compliance

- **RA 10173 (Data Privacy Act)** consent is captured at onboarding via a dedicated privacy modal, separate from terms-and-conditions, with two independent checkboxes.
- A hard 13+ age minimum is enforced on date of birth.

## Release Hardening

Before distribution, the release APK is decompiled and grep-checked to confirm the client ships **no** sensitive strings:

```bash
# decompile release APK to /tmp/decompiled, then:
grep -oE "AIzaSy[A-Za-z0-9_-]{35}" /tmp/decompiled   # expect 0 matches
grep -r "service_role" /tmp/decompiled                # expect 0 matches
grep -r "GEMINI" /tmp/decompiled                      # expect 0 matches
```

Any match is a release blocker. Reference to the live Supabase project is always replaced with a placeholder in shared artifacts and documentation.

## Cross-Platform Parity Note (Constraint #13)

Lab reference ranges and gender-fallback behavior are duplicated from the web platform (`constants.ts`) into `lib/features/department/domain/`. The duplication is a known coupling: any change to ranges, group membership, or the gender-fallback rule on either platform must be mirrored on the other, or lab flags will diverge between clients. The mobile client also stores the gender-resolved range on each lab row so the persisted range is always consistent with the row's flag.
