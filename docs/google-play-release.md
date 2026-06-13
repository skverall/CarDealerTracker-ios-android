# Google Play Release Notes

## App

- App name in Play Console: Car Dealer Tracker
- Android package name: `com.ezcar24.business`
- Current Android version in project: `2.1.12`
- Current Android version code in project: `2112`
- Current Android compile SDK: `35`
- Current Android target SDK: `35`

## Current release status

Updated: 2026-06-13 17:48 UZT

Firebase Android config is installed locally at:

```text
Android Car Dealer Tracker/app/google-services.json
```

Backup copy is stored outside the repository at:

```text
~/.hermes/secrets/firebase/com.ezcar24.business-google-services.json
```

The backup path is saved in macOS Keychain under:

```text
firebase.com.ezcar24.business.google_services_json_path
```

Local checks passed after moving the Android project to target API 35:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew :app:compileDebugKotlin

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew test

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew assembleDebug
```

Signed release AAB built successfully:

```text
Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab
```

Size: `12M`

SHA-256:

```text
8e93c88431010b6a8bfe7c1e24fe0f77464e6e43e901624f0a61c51478f33b16
```

Release build command:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew :app:bundleRelease
```

Google Play Developer API candidate key is configured in Keychain under:

```text
googleplay.com.ezcar24.business.service_account_json_path
```

The key can obtain a Google OAuth token, but Android Publisher API currently
returns:

```text
Package not found: com.ezcar24.business.
```

This means the service account does not currently see the Play Console app, or
the app has not been created in Play Console with package `com.ezcar24.business`.

The same key cannot currently fetch Firebase Android config. Firebase Management
API is disabled or unavailable for that Google Cloud/Firebase project.

## Release signing key

- Keystore path: `/Users/shokhabbos/.android-signing/ezcar24/ezcar24-business-release.jks`
- Key alias: `ezcar24business-upload`
- SHA-256 fingerprint for Android developer verification:

```text
55:B2:2C:4F:D0:42:98:4E:53:08:2D:31:3F:A7:B4:76:02:81:EC:EA:28:76:C6:C0:26:00:37:02:D8:C2:D8:55
```

## macOS Keychain entries

Signing secrets are stored in macOS Keychain, not in Git.

- Account: `com.ezcar24.business`
- Keystore path service: `googleplay.com.ezcar24.business.upload_keystore_path`
- Keystore password service: `googleplay.com.ezcar24.business.upload_keystore_password`
- Key alias service: `googleplay.com.ezcar24.business.upload_key_alias`
- Key password service: `googleplay.com.ezcar24.business.upload_key_password`

To retrieve a value manually:

```bash
security find-generic-password -w \
  -a "com.ezcar24.business" \
  -s "googleplay.com.ezcar24.business.upload_keystore_path"
```

Use the same pattern for the other services.

## Local Gradle signing config

The local file below was created so Gradle can sign release builds:

```text
Android Car Dealer Tracker/keystore.properties
```

This file contains signing passwords and is ignored by Git via `.gitignore`.

## Local Java

OpenJDK 17 is installed through Homebrew. For Gradle commands in Terminal, use:

```bash
export JAVA_HOME="$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"
```

Signing was verified with:

```bash
JAVA_HOME="$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home" ./gradlew :app:signingReport
```
