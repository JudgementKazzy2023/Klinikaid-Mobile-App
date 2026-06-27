# Developer Setup and Onboarding Guide

This document provides a step-by-step guide to setting up your local development environment, configuring database credentials, launching emulators, running the app, and executing the test suite.

---

## 1. System Requirements and Prerequisites

Before setting up the project, install the following development packages:

### Flutter SDK
- **Version Constraint**: Stable channel matching SDK constraint `^3.12.0` (typically Flutter 3.16.x or newer).
- **Download**: Official installer from [flutter.dev](https://docs.flutter.dev/get-started/install).
- **Environment Variables**: Add the path to your `/flutter/bin` folder to your system `PATH` variable.

### Dart SDK
- Bundled automatically inside your Flutter SDK installation. Do not download it separately.

### Java Development Kit (JDK)
- **Version Requirement**: JDK 17 (required for Gradle and Android compilations).
- **Environment Variable**: Configure your `JAVA_HOME` environment variable to point to your JDK 17 installation directory.

### Android Studio
- **Installer**: Current stable release from [developer.android.com](https://developer.android.com/studio).
- **Required Modules**: Install the Android SDK Platform Tools, Android SDK Build Tools, and Android Emulator via the SDK Manager.
- **CPU Virtualization**: Verify Intel HAXM or Windows Hypervisor Platform (WHPX) is active in your BIOS to run hardware-accelerated emulators.

---

## 2. Cloning the Repository

Clone this private Git repository to your local workspace:

```bash
# Clone via HTTPS
git clone https://github.com/[Placeholder-Organization]/KlinikAid-Mobile.git
cd KlinikAid-Mobile

# Optional: Configure git settings for Capstone development
git config user.name "[Placeholder-Developer-Name]"
git config user.email "[Placeholder-Developer-Email]"
```

Verify your workspace files match the repository index:
- `pubspec.yaml`
- `lib/`
- `android/`
- `test/`
- `docs/`

---

## 3. Configuring Local Environment Credentials

KlinikAid Mobile connects to a shared Supabase backend. Because API credentials differ across testing environments, they are stored in a configuration file excluded from Git by `.gitignore`.

1. Copy the example configuration template to create the active configuration:
   ```bash
   # On macOS / Linux
   cp lib/core/config/env.dart.example lib/core/config/env.dart

   # On Windows PowerShell
   Copy-Item lib/core/config/env.dart.example lib/core/config/env.dart
   ```
2. Open `lib/core/config/env.dart` in your text editor. It should match this template:
   ```dart
   class Env {
     static const String supabaseUrl = 'https://<your-supabase-project-id>.supabase.co';
     static const String supabaseAnonKey = '<your-supabase-anon-key>';
   }
   ```
3. Locate your project credentials in the Supabase Dashboard:
   - Go to **Project Settings > API**.
   - Copy the **Project URL** and paste it into `supabaseUrl`.
   - Copy the **anon (public)** key and paste it into `supabaseAnonKey`.

> [!WARNING]
> Never commit `env.dart` or any files containing active project API keys. The Gemini API key is also never placed in this file; it is stored as a secret inside the Supabase Edge Function environment.

---

## 4. Installing Package Dependencies

Run the package manager to fetch the packages declared in `pubspec.yaml`:

```bash
flutter pub get
```

This retrieves the required libraries (including `supabase_flutter`, `drift`, and `image_picker`) and locks their versions in `pubspec.lock` to ensure reproducible builds across the team.

---

## 5. Configuring the Android Emulator

For local testing, we recommend using an Android Virtual Device (AVD) running Android 14 (API Level 34).

1. Launch Android Studio and select **Tools > Device Manager**.
2. Click **Create Device** and select **Pixel 6** (with Google Play services).
3. Select and download the system image for **API Level 34** (x86_64).
4. Complete the wizard. In the AVD settings under **Graphics**, select **Hardware - GLES 2.0** to enable GPU acceleration.
5. **Disable Nested Emulator View**:
   - Go to Android Studio **Settings** (or **Preferences** on macOS).
   - Navigate to **Tools > Emulator**.
   - **Uncheck** the checkbox for **Launch in a tool window**.
   - This opens the emulator in a separate window, allowing full device interaction.
6. Click the play button in the Device Manager to launch the emulator.

---

## 6. Building and Running the App

List all detected development targets to verify your emulator is online:

```bash
flutter devices
```

Build and launch the application in debug mode on your active emulator:

```bash
flutter run
```

If multiple devices are active, target your emulator directly:

```bash
flutter run -d <emulator-id>
```

---

## 7. Running the Test Suite

KlinikAid Mobile includes a suite of over 90 widget and unit tests to verify RLS policies, routing rules, local caching, and OCR processing.

To run the complete test suite:
```bash
flutter test
```

To run a specific test file:
```bash
flutter test test/phase9_ocr_retake_redirect_test.dart
```

---

## 8. Common Setup Issues and Fixes

### Issue 1: "Lost connection to device" during runs
- **Description**: The Flutter development link drops unexpectedly during testing.
- **Fix**: Re-run the application using `flutter run`. This reconnects the debug port without requiring a full reinstall.

### Issue 4: "FunctionException 404" on Chatbot Queries
- **Description**: The Gemini RAG edge function returns a 404 error on user messages.
- **Fix**: The chatbot Edge Function has not been deployed to your active Supabase project. Deploy the function from your CLI:
  ```bash
  supabase functions deploy chat --project-ref <your-supabase-project-id>
  ```
  Set your Gemini API key secret in Supabase:
  ```bash
  supabase secrets set GEMINI_API_KEY=<your-gemini-api-key> --project-ref <your-supabase-project-id>
  ```

### Issue 5: "StorageException 403" when uploading files
- **Description**: Uploading document referrals fails with a permission denied error.
- **Fix**: Verify that RLS policies are applied to the `patient-documents` bucket in your Supabase Storage dashboard, permitting authenticated inserts.
