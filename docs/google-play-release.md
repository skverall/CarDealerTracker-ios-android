# Google Play Release Notes

## App

- App name in Play Console: Car Dealer Tracker
- Android package name: `com.ezcar24.business`
- Current Android version in project: `2.1.12`
- Current Android version code in project: `2112`

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
