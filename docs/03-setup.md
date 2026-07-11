# 03 — Setup: Local Installation & Troubleshooting

## Toolchain

The project is developed and verified against:

| Tool | Version |
| :--- | :--- |
| Flutter | 3.44.0 (stable channel) |
| Dart SDK | 3.12.0 |
| DevTools | 2.57.0 |
| Android minSdk | 26 |

Confirm your toolchain with `flutter --version` and `flutter doctor` before building.

## Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App.git
   cd Klinikaid-Mobile-App
   ```

2. **Configure environment**

   Copy the example config and fill in the shared Supabase project credentials:
   ```bash
   cp lib/core/config/env.dart.example lib/core/config/env.dart
   ```
   `env.dart` exposes two values, both readable from `--dart-define` or a default placeholder:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`

   Only the **anon** (public) key belongs on the device. Never place a service-role key, Gemini key, or any server secret in the client — those live behind Supabase Edge Functions. See [06-security](06-security.md).

   You can inject credentials at run time instead of editing the file:
   ```bash
   flutter run \
     --dart-define=SUPABASE_URL=your_url \
     --dart-define=SUPABASE_ANON_KEY=your_anon_key
   ```

3. **Install packages**
   ```bash
   flutter pub get
   ```

4. **Run**
   ```bash
   flutter run
   ```
   Testing is done on a **real Android device**, not an emulator — on-device OCR (ML Kit) and camera capture behave differently under emulation.

## Running Tests

```bash
flutter analyze
flutter test
```

Test files live under `test/` and are named by phase (e.g. `phase_d1_department_queue_test.dart`, `phase_r5_receptionist_journey_test.dart`).

## Troubleshooting

- **`env.dart` not found / build fails on missing Supabase config** — you skipped step 2. Copy the example file or pass `--dart-define` values.
- **OCR returns nothing on emulator** — expected. Use a real device with a working camera.
- **MFA/TOTP challenge loops on a staff account** — confirm the account has a verified TOTP factor; staff routes require AAL2 step-up. See [06-security](06-security.md).
- **Empty department queue for a staff account** — confirm the account's `profiles.department` is set; an unassigned department triggers a logout redirect by design.
- **Deprecation warnings after a Flutter upgrade** — the project targets Flutter 3.44.0. Newer SDKs may deprecate APIs (e.g. form-field `value` → `initialValue`); pin the toolchain if you need reproducibility.
