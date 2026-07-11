# 02 — Architecture: Component Relationships & Helpers

This is the primary reference for the web team studying how the mobile client is structured and how it touches the shared backend.

## High-Level Shape

The app is a Flutter/Android client using `provider` for state, `go_router` for navigation and route guards, `supabase_flutter` for backend access, `drift` (SQLite) for a local read cache, and `google_mlkit_text_recognition` for on-device OCR. There is no direct model/API access from the device — the AI chatbot goes through a Supabase Edge Function.

## Layering

The codebase follows a feature-first layout under `lib/features/`, with shared infrastructure under `lib/core/`.

```
lib/
├── core/
│   ├── cache/         Drift local database (offline read cache)
│   ├── config/        env.dart (Supabase URL + anon key, injected)
│   ├── errors/        shared error types
│   ├── models/        domain models: profile, patient, patient_queue,
│   │                  department_record, document, chatbot_log, rag_document
│   ├── repositories/  shared repository base
│   ├── routing/       app_router.dart (all routes + guard chain)
│   ├── supabase/      Supabase client bootstrap
│   ├── theme/         app theme
│   └── utils/         formatters (role, reference-status, triage-notes), date helpers
└── features/
    ├── auth/          login, register, consent, forgot-password, TOTP verify, MFA service
    ├── chatbot/       AI assistant (calls Edge Function 'chat')
    ├── dashboard/     patient dashboard, profile
    ├── department/    department staff: shell, queue, records, result entry (D1 + D2)
    ├── documents/     patient document submit + status
    ├── ocr/           quality assessment domain + thresholds
    ├── queue/         patient queue view
    ├── reception/     receptionist workstation (R1–R5): validation, queue, dashboard
    ├── records/       patient record viewing + grouping
    └── staff/         role landing screens (reception/department/specialist home)
```

Within a feature the convention is `data/` (repositories, services), `domain/` (models, pure logic), and `presentation/` (providers, screens, widgets).

## State & Data Flow

A screen reads from a `provider` (ChangeNotifier). The provider calls a repository. The repository talks to Supabase (and, for reads that benefit from it, hydrates from the Drift cache first). For live data (queues), providers subscribe to Supabase Realtime channels and refresh on change.

Example — department daily queue:
1. `DepartmentQueueScreen` watches `DepartmentProvider`.
2. Provider calls `DepartmentRepository.getDailyQueue()`.
3. Repository resolves the staff member's department **from the session** (never a caller-supplied argument) and queries `patient_queue` filtered to that department.
4. Provider also opens a Realtime channel filtered `department=eq.{dept}` so other-department inserts never reach the client; the channel is torn down on `dispose()`.

## Routing & Guards

All routes and the redirect guard chain live in `lib/core/routing/app_router.dart` (`go_router`). Staff routes enforce, in order:

```
authenticated → role match → department assigned → AAL2 (step-up MFA) → allow
```

Order matters: department assignment is checked before the MFA challenge so an unassigned staff account is redirected to logout/login rather than completing TOTP and then hitting an error.

Route groups:
- **Public/auth:** `/`, `/login`, `/register`, `/consent`, `/verify`, `/forgot-password`, `/mfa-verify`
- **Patient:** `/patient`, `/submit`, `/records`, `/queue`, `/documents/status`, `/chatbot`, `/profile`
- **Reception:** `/staff/reception`, `/reception/queue`, `/reception/dashboard`, `/reception/document/:submissionId`, `/reception/profile`
- **Department (ShellRoute):** `/department/queue`, `/department/records`, `/department/profile`; plus `/department/result-entry/:patientId` (full-screen, **outside** the shell so back-navigation returns to the queue)
- **Specialist:** `/staff/specialist`

## Shared Backend Touchpoints

Tables the mobile client reads/writes on the shared Supabase project:

| Table | Mobile reads | Mobile writes |
| :--- | :--- | :--- |
| `profiles` | role, department, name | password/email change flows |
| `patients` | patient demographics, gender | — |
| `patient_queue` | department daily queue | reception approve/route/reject; department result-entry status → `completed` |
| `department_records` | records history, patient records | department result entry (lab + free-text) |
| `documents` | patient status, reception validation | patient upload (OCR text + quality metadata) |

Backend features the mobile client depends on but does not implement: the `chat` Edge Function (AI assistant), the `assess-document-quality` Edge Function (OCR quality scoring), RLS policies, and the `get_auth_user_dept()` helper used for department scoping.

## Lab Result Entry Domain (D2)

Because it crosses platforms, the lab entry logic is worth calling out:

- `lib/features/department/domain/lab_reference_ranges.dart` — hardcoded reference ranges + test groups, copied from web `constants.ts` (Constraint #13). The file header marks it as a sync source. Group names and parameter names are **case-sensitive** because they double as stored `test_type`/`test_name` values and drive the range lookup.
- `lib/features/department/domain/flag_calculator.dart` — gender-aware boundary check. Null/"other" gender falls back to male ranges (matches web, no exception).
- `lib/features/department/data/department_repository.dart` — `submitLabResults` / `submitFreeTextResult`. Writes **N rows per N parameters**, then separately updates `patient_queue` to `completed`. The two calls are **non-atomic by design** (no transaction, no RPC) to mirror the web platform; a failed queue update logs a warning and does not roll back the inserted records.

The stored `reference_range_min`/`max` on each lab row are the **gender-resolved** values actually used for the flag decision, so a row's stored range is always self-consistent with its `is_flagged` value.
