# KlinikAid Mobile

KlinikAid Mobile — a patient-and-staff-facing Android app for Bloodcare Medical Laboratory, built in Flutter with a Supabase backend.

[![Flutter Version](https://img.shields.io/badge/Flutter-v3.44.0-blue.svg)](https://flutter.dev)
[![Android minSdk](https://img.shields.io/badge/Android-minSdk%2026-green.svg)](https://developer.android.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Quick Start
1. **Clone the repository**: `git clone https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App.git`
2. **Configure environment**: Copy `lib/core/config/env.dart.example` to `lib/core/config/env.dart` and enter your Supabase URL & Anon Key placeholders.
3. **Download packages**: `flutter pub get`
4. **Run the application**: `flutter run`

## What This App Does
KlinikAid Mobile digitizes clinical intake and results processing for Bloodcare Medical Laboratory. Patients can onboard directly from the app, submit diagnostic referrals using their device's camera, view real-time queue notifications, access their lab records, and query an AI health assistant. By digitizing intake at the point of care, it eliminates clinical paper dependencies, human data entry errors, and long queue bottlenecks.

The application also embeds three specialized staff portals tailored to different clinic operational roles: Document lookup and verification for Receptionists, department-specific waitlist and results reviews for Department Staff, and multi-term patient search alongside cross-department patient timelines for Medical Specialists. All of this runs as a secure, role-restricted mobile client talking to a backend shared with a web-portal administration team.

## Tech Stack
| Component | Technology | Description |
| :--- | :--- | :--- |
| **Framework** | Flutter / Dart | Native Android client wrapper & state rendering |
| **Backend** | Supabase | Auth, Postgres DB, Edge Functions, Storage, Realtime sync |
| **Database Extensions** | pgvector | Backend-side vector similarity search over text embeddings (server-side; not on the device) |
| **AI LLM Engine** | Gemini API (server-side) | Powers the QA chatbot via a Supabase Edge Function; the client never calls the model directly and holds no AI key |
| **Device AI** | Google ML Kit | Performs local OCR processing of document files for intake |
| **Local Cache** | Drift (SQLite) | Manages offline-first database sync with patient profile isolation |

## Roles Supported
| Role | Mobile Access | Details |
| :--- | :--- | :--- |
| **Patient** | Full access | Consent, onboarding, document upload with OCR, chatbot, records, queue |
| **Receptionist** | Reception workstation | Document validation, queue approve/route/reject, dashboard (write-capable) |
| **Department Staff** | Department workstation | Department-scoped queue + records, and clinical result entry (write-capable) |
| **Medical Specialist**| Patient history | Multi-term search, cross-department records timeline (read-only) |
| **Admin / Owner** | **None** | Mobile access is strictly blocked; system administration is web-only |

> Receptionist and Department Staff are write-capable as of the receptionist workstation (R1–R5) and department result entry (D2). Specialist and admin/owner mobile behavior may change in future phases. See [docs/04-development-story.md](docs/04-development-story.md).

## Documentation Index
- [01-Overview: Project Scope & Boundaries](docs/01-overview.md)
- [02-Architecture: Component Relationships & Helpers](docs/02-architecture.md)
- [03-Setup: Local Installation & Troubleshooting](docs/03-setup.md)
- [04-Development Story: Phases & Hardening Fixes](docs/04-development-story.md)
- [05-Features: Scoped Role Matrix](docs/05-features.md)
- [06-Security: Authentication & Data Isolation Guards](docs/06-security.md)
- [07-Deployment: Release Build & Distribution](docs/07-deployment.md)

## Acknowledgments
- **Capstone Team**: Healthioneers
  - Mobile Developer: `[Team Member Name / GitHub Handle]`
  - Web Developers: `[Team Member Name]`, `[Team Member Name]`, `[Team Member Name]`
- **Institution**: FEU Diliman
- **Project Sponsors**: Bloodcare Medical Laboratory & Web-Team Partners

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
