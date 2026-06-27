# Deployment and Release Guide — KlinikAid Mobile

This document details the build pipeline, signing configurations, post-deployment smoke tests, and distribution procedures for compiling KlinikAid Mobile into a production-ready Android Application Package (APK).

---

## 1. Pre-Build Verification Checklist

Before compiling a release build, ensure the codebase satisfies the following verification checks:

1. **Static Analysis**: Verify there are no syntax errors or lint warnings in your source files:
   ```bash
   flutter analyze
   ```
2. **Test Suite**: Run the complete test suite to confirm all 90+ tests pass:
   ```bash
   flutter test
   ```
3. **Environment Setup**: Ensure your target Supabase URL and Anon Key are set in `lib/core/config/env.dart`. Do not build with placeholder values.

---

## 2. Compiling the Release APK

Build the compiled, optimized Android package using the Flutter CLI:

```bash
flutter build apk --release
```

This command compiles Dart to native ARM machine code and optimizes resource packages. The compiled package is saved to the following workspace path:

```
build/app/outputs/flutter-apk/app-release.apk
```

---

## 3. Application Signing

KlinikAid Mobile must be digitally signed before sideloading onto mobile devices:

- **Debug / Academic Deployment**: The default compiler uses a standard debug keystore (`~/.android/debug.keystore`) automatically. This is suitable for development testing and capstone defense presentations.
- **Production Clinic Deployment**:
  - The project lead must generate a secure keystore file (`release-keystore.jks`).
  - Configure the build variables in `android/key.properties` (specifying keystore paths, aliases, and passwords).
  - The `android/app/build.gradle` file reads these variables to sign the release package.

> [!CAUTION]
> Never commit your production `release-keystore.jks` or `android/key.properties` files to your Git repository. Both paths are excluded via `.gitignore`.

---

## 4. Application Versioning

The app's version and build number are defined in `pubspec.yaml`:

```yaml
version: 1.0.0+1
```

- **`1.0.0` (Version Name)**: Represents the public-facing release version.
- **`1` (Version Code)**: Represents the build number, incremented with each release.

You can override these variables during compile time:
```bash
flutter build apk --release --build-name=1.0.1 --build-number=2
```

---

## 5. Distribution and Installation

Since KlinikAid Mobile is a private, specialized application for Bloodcare Medical Laboratory, it is distributed outside of public app stores:
- **Academic Defense**: Sideload the APK onto physical Android devices or emulators using `adb install`:
  ```bash
  adb install build/app/outputs/flutter-apk/app-release.apk
  ```
- **Clinic Deployment**: Sideload using USB transfers or distribute via a secure cloud storage link for clinic staff and patients.

---

## 6. Post-Deployment Smoke Tests

Once the APK is installed on a physical device, execute these three manual smoke tests to verify the deployment:

### Test 1: Authentication and Session Restoration
1. Log in using a test patient account.
2. Accept the privacy consent and complete onboarding.
3. Close the application, clear it from memory, and launch it again.
4. Verify the app bypasses the login screen and loads the patient dashboard immediately.

### Test 2: Edge Function Connection Check
1. Open the Chatbot tab.
2. Send the message "What are the lab hours?".
3. Verify that the chatbot returns a grounded answer and does not display an error banner.

### Test 3: Local Caching Verification
1. Disconnect the device from mobile data and Wi-Fi.
2. Navigate to the Patient Records tab.
3. Verify that previously loaded diagnostic findings are visible, confirming Drift database persistence.

---

## 7. APK Security Verification

To verify that no private database keys or API credentials leaked into the compiled package, run the following audit:

```bash
# Decompile the APK
apktool d build/app/outputs/flutter-apk/app-release.apk -o decompiled_audit/

# Verify that no credentials are found in the files
grep -r "AIzaSy" decompiled_audit/
grep -r "service_role" decompiled_audit/
```

Both queries must return **zero matches** to pass deployment requirements.
