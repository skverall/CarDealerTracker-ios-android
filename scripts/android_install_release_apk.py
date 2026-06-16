#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ANDROID_DIR = ROOT / "Android Car Dealer Tracker"
DEFAULT_APK = ANDROID_DIR / "app/build/outputs/apk/release/app-release.apk"
METADATA_PATH = ANDROID_DIR / "app/build/outputs/apk/release/output-metadata.json"
PACKAGE_NAME = "com.ezcar24.business"


def run(args: list[str], cwd: Path = ROOT, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True, check=check)


def find_adb() -> Path | None:
    candidates: list[Path] = []
    for env_name in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        value = os.environ.get(env_name)
        if value:
            candidates.append(Path(value) / "platform-tools/adb")
    candidates.extend(
        [
            Path.home() / "Library/Android/sdk/platform-tools/adb",
            Path("/opt/homebrew/share/android-commandlinetools/platform-tools/adb"),
            Path("/usr/local/share/android-commandlinetools/platform-tools/adb"),
        ]
    )
    for candidate in candidates:
        if candidate.exists():
            return candidate

    try:
        result = run(["/usr/bin/which", "adb"], check=False)
    except OSError:
        return None
    path = result.stdout.strip()
    return Path(path) if path else None


def connected_devices(adb: Path) -> list[tuple[str, str]]:
    result = run([str(adb), "devices"], check=False)
    devices: list[tuple[str, str]] = []
    for line in result.stdout.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2:
            devices.append((parts[0], parts[1]))
    return devices


def build_release() -> None:
    java_home = "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
    env = os.environ.copy()
    env.setdefault("JAVA_HOME", java_home)
    env.setdefault("ANDROID_HOME", "/opt/homebrew/share/android-commandlinetools")
    command = ["./gradlew", ":app:assembleRelease"]
    subprocess.run(command, cwd=ANDROID_DIR, env=env, check=True)


def apk_metadata() -> str:
    if not METADATA_PATH.exists():
        return "metadata=missing"
    try:
        payload = json.loads(METADATA_PATH.read_text())
        element = payload.get("elements", [{}])[0]
        return f"version={element.get('versionName')} ({element.get('versionCode')})"
    except (json.JSONDecodeError, OSError, IndexError):
        return "metadata=unreadable"


def main() -> int:
    parser = argparse.ArgumentParser(description="Install the latest signed release APK on a connected Android device.")
    parser.add_argument("--apk", type=Path, default=DEFAULT_APK, help="APK path to install")
    parser.add_argument("--build", action="store_true", help="Build :app:assembleRelease before installing")
    parser.add_argument("--serial", help="Install to a specific adb device serial")
    parser.add_argument("--wait", action="store_true", help="Wait until a device is connected")
    parser.add_argument("--no-launch", action="store_true", help="Do not launch the app after install")
    args = parser.parse_args()

    adb = find_adb()
    if not adb:
        print("adb not found. Install Android platform-tools or open Android Studio once.", file=sys.stderr)
        return 1

    if args.build:
        build_release()

    apk = args.apk
    if not apk.exists():
        print(f"APK not found: {apk}", file=sys.stderr)
        print("Run with --build or build it in Android Studio first.", file=sys.stderr)
        return 1

    if args.wait:
        run([str(adb), "wait-for-device"], check=False)

    devices = connected_devices(adb)
    if not devices:
        print("No Android device is visible through adb.", file=sys.stderr)
        print("On the phone: connect USB, allow USB debugging, and tap Allow on the RSA prompt.", file=sys.stderr)
        return 2

    bad_states = [f"{serial}:{state}" for serial, state in devices if state != "device"]
    if bad_states:
        print(f"Device is connected but not authorized/ready: {', '.join(bad_states)}", file=sys.stderr)
        print("Unlock the phone and tap Allow on the USB debugging prompt.", file=sys.stderr)
        return 3

    serial = args.serial or devices[0][0]
    if args.serial and args.serial not in {item[0] for item in devices}:
        print(f"Requested device not found: {args.serial}", file=sys.stderr)
        return 4

    print(f"adb: {adb}")
    print(f"device: {serial}")
    print(f"apk: {apk}")
    print(apk_metadata())

    install = run([str(adb), "-s", serial, "install", "-r", "-g", str(apk)], check=False)
    print(install.stdout.strip())
    if install.returncode != 0:
        print(install.stderr.strip(), file=sys.stderr)
        return install.returncode

    if not args.no_launch:
        launch = run(
            [
                str(adb),
                "-s",
                serial,
                "shell",
                "monkey",
                "-p",
                PACKAGE_NAME,
                "-c",
                "android.intent.category.LAUNCHER",
                "1",
            ],
            check=False,
        )
        print(launch.stdout.strip())
        if launch.returncode != 0:
            print(launch.stderr.strip(), file=sys.stderr)
            return launch.returncode

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
