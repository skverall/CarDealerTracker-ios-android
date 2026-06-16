#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

from google.auth.transport.requests import Request
from google.oauth2 import service_account


PACKAGE_NAME = os.environ.get("PLAY_PACKAGE_NAME", "com.ezcar24.business")
KEYCHAIN_SERVICE = os.environ.get(
    "PLAY_SERVICE_ACCOUNT_KEYCHAIN_SERVICE",
    f"googleplay.{PACKAGE_NAME}.service_account_json_path",
)
DEFAULT_AAB_PATH = (
    Path(__file__).resolve().parents[1]
    / "Android Car Dealer Tracker"
    / "app"
    / "build"
    / "outputs"
    / "bundle"
    / "release"
    / "app-release.aab"
)
DEFAULT_RELEASE_NOTES = (
    "Improved Android subscription setup, dashboard parity, client and sales "
    "sync, account flows, and release stability."
)


def keychain_password(account: str, service: str) -> str:
    return subprocess.check_output(
        [
            "security",
            "find-generic-password",
            "-w",
            "-a",
            account,
            "-s",
            service,
        ],
        text=True,
    ).strip()


def android_publisher_token(service_account_path: str) -> str:
    credentials = service_account.Credentials.from_service_account_file(
        service_account_path,
        scopes=["https://www.googleapis.com/auth/androidpublisher"],
    )
    credentials.refresh(Request())
    return credentials.token


def api_request(method: str, url: str, token: str, body: dict | None = None):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            raw = response.read().decode()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        raw = error.read().decode(errors="replace")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"raw": raw[:1000]}
        return error.code, payload


def upload_bundle(upload_url: str, token: str, aab_path: Path):
    request = urllib.request.Request(
        f"{upload_url}?uploadType=media",
        data=aab_path.read_bytes(),
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/octet-stream",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            raw = response.read().decode()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        raw = error.read().decode(errors="replace")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"raw": raw[:1000]}
        return error.code, payload


def error_message(payload) -> str:
    if isinstance(payload, dict):
        return payload.get("error", {}).get("message") or payload.get("raw") or ""
    return "" if payload is None else str(payload)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Upload the EzCar24 Android AAB to a Google Play testing track."
    )
    parser.add_argument("--aab", default=str(DEFAULT_AAB_PATH), help="Path to app-release.aab")
    parser.add_argument("--track", default="alpha", help="Play track, e.g. alpha/internal/beta")
    parser.add_argument("--status", default="completed", help="Release status for the track")
    parser.add_argument("--name", default="2.1.14 (2114)", help="Release name")
    parser.add_argument("--notes", default=DEFAULT_RELEASE_NOTES, help="en-US release notes")
    parser.add_argument("--apply", action="store_true", help="Create edit, upload AAB, and update track")
    parser.add_argument("--commit", action="store_true", help="Commit the edit after upload/update")
    args = parser.parse_args()

    aab_path = Path(args.aab).expanduser().resolve()
    if not aab_path.is_file():
        print(f"AAB not found: {aab_path}", file=sys.stderr)
        return 1

    sha = file_sha256(aab_path)
    size_mb = aab_path.stat().st_size / (1024 * 1024)
    print(f"package: {PACKAGE_NAME}")
    print(f"aab: {aab_path}")
    print(f"size_mb: {size_mb:.1f}")
    print(f"sha256: {sha}")
    print(f"track: {args.track}")
    print(f"release_name: {args.name}")
    print(f"mode: {'apply' if args.apply else 'dry-run'}")

    if not args.apply:
        return 0

    try:
        service_account_path = keychain_password(PACKAGE_NAME, KEYCHAIN_SERVICE)
        token = android_publisher_token(service_account_path)
    except Exception as exc:
        print(f"setup failed: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1

    api_base = (
        "https://androidpublisher.googleapis.com/androidpublisher/v3/"
        f"applications/{PACKAGE_NAME}"
    )
    upload_base = (
        "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/"
        f"applications/{PACKAGE_NAME}"
    )

    status, payload = api_request("POST", f"{api_base}/edits", token, {})
    if status != 200 or not isinstance(payload, dict):
        print(f"edits.insert HTTP {status}; {error_message(payload)}")
        return 1
    edit_id = payload.get("id")
    print("edits.insert: HTTP 200")

    try:
        status, payload = upload_bundle(
            f"{upload_base}/edits/{edit_id}/bundles",
            token,
            aab_path,
        )
        if status != 200 or not isinstance(payload, dict):
            print(f"bundles.upload HTTP {status}; {error_message(payload)}")
            return 1
        version_code = str(payload.get("versionCode"))
        print(f"bundles.upload: HTTP 200; versionCode={version_code}")

        track_payload = {
            "track": args.track,
            "releases": [
                {
                    "name": args.name,
                    "versionCodes": [version_code],
                    "status": args.status,
                    "releaseNotes": [
                        {
                            "language": "en-US",
                            "text": args.notes,
                        }
                    ],
                }
            ],
        }
        status, payload = api_request(
            "PUT",
            f"{api_base}/edits/{edit_id}/tracks/{args.track}",
            token,
            track_payload,
        )
        if status != 200:
            print(f"tracks.update HTTP {status}; {error_message(payload)}")
            return 1
        print(f"tracks.update: HTTP 200; track={args.track}; versionCode={version_code}")

        status, payload = api_request("POST", f"{api_base}/edits/{edit_id}:validate", token)
        if status != 200:
            print(f"edits.validate HTTP {status}; {error_message(payload)}")
            return 1
        print("edits.validate: HTTP 200")

        if args.commit:
            status, payload = api_request("POST", f"{api_base}/edits/{edit_id}:commit", token)
            if status != 200:
                print(f"edits.commit HTTP {status}; {error_message(payload)}")
                return 1
            print("edits.commit: HTTP 200")
        else:
            status, _ = api_request("DELETE", f"{api_base}/edits/{edit_id}", token)
            print(f"edits.delete: HTTP {status}; not committed")
    except Exception as exc:
        status, _ = api_request("DELETE", f"{api_base}/edits/{edit_id}", token)
        print(f"failed: {type(exc).__name__}: {exc}")
        print(f"edits.delete: HTTP {status}")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
