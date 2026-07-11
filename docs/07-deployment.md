# 07 — Deployment: Release Build & Distribution

## Build Method

Releases are built manually with the Flutter CLI. There is no CI pipeline; the build is run from a configured local machine.

## Pre-Build Checklist

1. Toolchain matches [03-setup](03-setup.md): Flutter 3.44.0 stable, Dart 3.12.0.
2. `flutter analyze` is clean for production code (`lib/`).
3. `flutter test` passes.
4. Supabase credentials are provided via `--dart-define` (preferred for release) rather than a committed `env.dart`.

## Build

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=your_url \
  --dart-define=SUPABASE_ANON_KEY=your_anon_key
```

The output APK is produced under `build/app/outputs/flutter-apk/`.

## Post-Build Security Verification (Required)

Decompile the release APK and confirm no sensitive strings ship in the client:

```bash
# decompile the release APK to /tmp/decompiled first, then:
grep -oE "AIzaSy[A-Za-z0-9_-]{35}" /tmp/decompiled   # expect 0 matches
grep -r "service_role" /tmp/decompiled                # expect 0 matches
grep -r "GEMINI" /tmp/decompiled                      # expect 0 matches
```

Any non-zero result is a release blocker — the client must carry only the public anon key. Server secrets belong behind Supabase Edge Functions. See [06-security](06-security.md).

## Distribution

The signed release APK is distributed manually (direct install / side-load to target devices). Testing and acceptance are performed on a **real Android device**, minSdk 26, because on-device OCR and camera behavior are not reliably reproduced under emulation.

## Environment Notes

- The mobile client and the web platform share one Supabase project. A release points at the shared project's URL + anon key; do not point a public release at a development project by accident.
- When sharing build artifacts, logs, or documentation outside the team, ensure the live Supabase project reference is replaced with a placeholder.
