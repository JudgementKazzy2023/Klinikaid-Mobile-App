# System Architecture and Component Relations

This document details the software architecture, folder structures, state management flows, database models, and domain helper implementations that define KlinikAid Mobile.

---

## 1. System Topology Diagram

The application operates as a standalone client connecting directly to a shared Supabase backend. The diagram below shows how the local systems, the device runtime environment, the remote backend database, and third-party AI interfaces communicate:

```
┌────────────────────────────────────────────────────────────────────────┐
│                              MOBILE CLIENT                             │
│                                                                        │
│  ┌───────────────────────┐                  ┌───────────────────────┐  │
│  │   Google ML Kit OCR   │                  │     Drift SQLite      │  │
│  │   (Local Text Extr.)  │                  │  (Offline-First Cache)│  │
│  └───────────┬───────────┘                  └───────────▲───────────┘  │
│              │ (Local extraction)                       │ (Sync/Cache)  │
│  ┌───────────▼───────────┐                  ┌───────────┴───────────┐  │
│  │   Flutter Widget UI   ◄──────────────────►    Provider States    │  │
│  └───────────────────────┴──────────────────┴───────────▲───────────┘  │
└─────────────────────────────────────────────────────────┼──────────────┘
                                                          │ (Supabase SDK)
                                                          ▼
┌────────────────────────────────────────────────────────────────────────┐
│                            SUPABASE BACKEND                            │
│                                                                        │
│  ┌──────────────┐    ┌─────────────────┐    ┌───────────────────────┐  │
│  │  Auth Engine │    │  Postgres DB    │    │    Private Storage    │  │
│  │  (Session)   │    │  (RLS Enforced) │    │  (Patient-Docs Bucket)│  │
│  └──────────────┘    └────────▲────────┘    └───────────────────────┘  │
│                               │                                        │
│  ┌────────────────────────────┴────────┐                               │
│  │       Gemini RAG Edge Function      │                               │
│  │  (pgvector Search + API Key Guard)  │                               │
│  └──────────────┬──────────────────────┘                               │
└─────────────────┼──────────────────────────────────────────────────────┘
                  │ (Server-Side HTTPS)
                  ▼
       ┌─────────────────────┐
       │   Gemini API Key    │
       │ (Protected Secrets) │
       └─────────────────────┘
```

---

## 2. Folder Structure (`lib/`)

The repository follows a clean, feature-driven directory structure:

*   **`lib/core/`**: Shared components and infrastructure.
    *   `cache/`: Drift database class (`local_database.dart`), generated files (`local_database.g.dart`), and connection controllers.
    *   `config/`: System environments (`env.dart`) containing Supabase API endpoint strings.
    *   `errors/`: Clinical failures (`failures.dart`) and mapping logic converting HTTP/Drift errors.
    *   `models/`: Data contracts mapping Supabase tables to Dart classes (`patient.dart`, `profile.dart`, `document.dart`).
    *   `routing/`: Navigational pathways (`app_router.dart`) governed by GoRouter guards.
    *   `supabase/`: DB initialization settings and instance clients (`supabase_client.dart`).
    *   `utils/`: Domain-agnostic utilities (date formats, UUID generator).
*   **`lib/features/`**: Role-based operational flows.
    *   `auth/`: Login inputs, signup fields, consent forms, and demographics onboarding screens.
    *   `chatbot/`: Conversational UI bubbles and log managers communicating with the Edge Function.
    *   `dashboard/`: Summary indicators displaying active queue tickets and pending documents.
    *   `documents/`: Image capture controllers, ML Kit text parsers, and verification screens.
    *   `queue/`: Dynamic ticket trackers observing PostgreSQL replication streams.
    *   `records/`: Historical results pages displaying consolidated lab/imaging outcomes.
    *   `staff/`: Scoped portals for clinic personnel:
        *   `data/`: Scoped repositories fetching patient listings.
        *   `presentation/providers/`: State objects managing data directories for staff.
        *   `presentation/screens/`: Layout screens for Receptionists, Department Staff, and Specialists.

---

## 3. State Management (Provider Flow)

State management is handled using the **Provider** package, separating UI presentation from database interactions:
- **`AuthProvider`**: Manages authentication sessions, accepts privacy consent, and loads patient profiles. It notifies GoRouter of session changes, triggering route updates.
- **`DocumentSubmissionProvider`**: Manages OCR parsing states, preview paths, checklist flags, and offline upload queues.
- **`RecordsProvider`**: Loads historical clinical records, groups row-based findings, and caches results in the Drift database.
- **`QueueProvider`**: Listens to active waitlists and establishes realtime listeners on queue tables.

---

## 4. Route Security and Navigation Guards

Client routing is configured via **GoRouter** in `lib/core/routing/app_router.dart`:
- **Initial Dispatch (`/`)**: Evaluates authentication state. Unauthenticated users are routed to `/login`.
- **Role Redirection**: When a profile is loaded, the router inspects the user's role:
  - Patients are guided to the onboarding screen if demographics are incomplete. If complete, they route to `/patient`.
  - Receptionists route directly to `/staff/reception`.
  - Department staff route to `/staff/department/{dept}`.
  - Specialists route to `/staff/specialist`.
- **Deep-Link Security**: The router intercepts unauthorized routes (e.g., a patient trying to access `/staff/reception` is redirected back to `/patient`).

---

## 5. Offline Data Caching

The app uses **Drift** (SQLite wrapper) for local offline storage:
- **Offline Writes**: Submissions are cached locally in the SQLite queue if the device loses connectivity. A background checker monitors network state and synchronizes the queue once online.
- **Data Leak Prevention**: When a user logs out, the app clears cached patient records. If a different user logs in, the cache is isolated by matching the stored user UUID, preventing data leaks on shared devices.

---

## 6. Supabase Edge Functions & Gemini Integration

To keep the Gemini API key secure (Constraint #1), the chatbot uses a **Supabase Edge Function** (`chat`):
1. **Request**: The client sends the user message to the `chat` Edge Function.
2. **Context Retrieval**: The function queries the `rag_documents` table in Postgres using `pgvector` similarity search, matching the user's message against embedded FAQs.
3. **Response Generation**: The matched clinical rules are passed to Gemini as context. The system prompt instructs Gemini to refuse medical diagnoses (Constraint #4) and limit responses to administrative and laboratory guidelines.
4. **Execution Log**: The exchange is recorded in `chatbot_logs` for user review.

---

## 7. Formatting Helpers Pattern

To prevent rendering discrepancies across screens, the app uses three domain formatters and a shared presentation widget:
- **`triage_notes_formatter.dart`**: Extracts clean notes from JSON-wrapped queue data, preventing raw JSON strings from showing in the UI.
- **`record_grouper.dart`**: Groups separate test parameter rows (e.g., findings and impressions of an X-ray) within a 5-minute recording window into a single card with worst-case-wins status badging.
- **`queue_status_formatter.dart`**: Maps queue status enums to clear labels (e.g., "NOW CALLING", "IN QUEUE").
- **`grouped_record_detail_modal.dart`**: A shared widget that provides a detailed breakdown of grouped test records, consumed by both patient records and specialist history screens.

Using centralized formatters ensures a consistent user experience across the app's patient-facing and staff-facing screens.
