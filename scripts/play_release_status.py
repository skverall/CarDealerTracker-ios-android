#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

from google.auth.transport.requests import Request
from google.oauth2 import service_account


PACKAGE_NAME = os.environ.get("PLAY_PACKAGE_NAME", "com.ezcar24.business")
KEYCHAIN_SERVICE = os.environ.get(
    "PLAY_SERVICE_ACCOUNT_KEYCHAIN_SERVICE",
    f"googleplay.{PACKAGE_NAME}.service_account_json_path",
)
DEFAULT_SUBSCRIPTION_IDS = [
    "com.ezcar24.business.weekly",
    "com.ezcar24.business.monthly",
    "com.ezcar24.business.quarterly",
    "com.ezcar24.business.yearly",
]
EXPECTED_SUBSCRIPTION_IDS = [
    item.strip()
    for item in os.environ.get(
        "PLAY_EXPECTED_SUBSCRIPTION_IDS",
        ",".join(DEFAULT_SUBSCRIPTION_IDS),
    ).split(",")
    if item.strip()
]


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
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read().decode()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        raw = error.read().decode(errors="replace")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"raw": raw[:500]}
        return error.code, payload


def error_message(payload) -> str:
    if isinstance(payload, dict):
        return payload.get("error", {}).get("message") or payload.get("raw") or ""
    return "" if payload is None else str(payload)


def print_subscriptions(base_url: str, token: str) -> None:
    status, payload = api_request("GET", f"{base_url}/subscriptions", token)
    if status == 204:
        print("subscriptions: HTTP 204; no Google Play subscription products returned")
        return
    if status != 200:
        print(f"subscriptions: HTTP {status}; {error_message(payload)}")
        return

    subscriptions = payload.get("subscriptions", []) if isinstance(payload, dict) else []
    print(f"subscriptions: HTTP 200; count={len(subscriptions)}")
    for item in subscriptions:
        product_id = item.get("productId", "<unknown>")
        state = item.get("listings", [])
        base_plans = item.get("basePlans", [])
        base_plan_summary = ", ".join(
            f"{base_plan.get('basePlanId', '<unknown>')}:{base_plan.get('state', '<unknown>')}"
            for base_plan in base_plans
        )
        print(
            f"  - {product_id}; basePlans={len(base_plans)}; "
            f"listings={len(state)}; states=[{base_plan_summary}]"
        )


def print_expected_subscription_details(base_url: str, token: str) -> None:
    if not EXPECTED_SUBSCRIPTION_IDS:
        return

    print("subscriptions.expected:")
    for product_id in EXPECTED_SUBSCRIPTION_IDS:
        encoded_id = urllib.parse.quote(product_id, safe="")
        status, payload = api_request("GET", f"{base_url}/subscriptions/{encoded_id}", token)
        if status == 200 and isinstance(payload, dict):
            base_plans = payload.get("basePlans", [])
            listings = payload.get("listings", [])
            base_plan_summary = ", ".join(
                f"{base_plan.get('basePlanId', '<unknown>')}:{base_plan.get('state', '<unknown>')}"
                for base_plan in base_plans
            )
            print(
                f"  - {product_id}: HTTP 200; basePlans={len(base_plans)}; "
                f"listings={len(listings)}; states=[{base_plan_summary}]"
            )
        else:
            message = error_message(payload)
            print(f"  - {product_id}: HTTP {status}; {message}")


def print_tracks(base_url: str, token: str) -> None:
    status, payload = api_request("POST", f"{base_url}/edits", token, {})
    if status != 200:
        print(f"edits.insert: HTTP {status}; {error_message(payload)}")
        return

    edit_id = payload.get("id") if isinstance(payload, dict) else None
    print("edits.insert: HTTP 200; temporary edit created")
    try:
        for track in ("internal", "alpha", "beta", "production"):
            status, payload = api_request(
                "GET",
                f"{base_url}/edits/{edit_id}/tracks/{track}",
                token,
            )
            if status != 200:
                print(f"track.{track}: HTTP {status}; {error_message(payload)}")
                continue

            releases = payload.get("releases", []) if isinstance(payload, dict) else []
            versions: list[str] = []
            statuses: list[str] = []
            for release in releases:
                versions.extend(str(version) for version in release.get("versionCodes", []))
                if release.get("status"):
                    statuses.append(release["status"])
            print(
                f"track.{track}: releases={len(releases)}; "
                f"versions={versions}; statuses={statuses}"
            )
    finally:
        status, _ = api_request("DELETE", f"{base_url}/edits/{edit_id}", token)
        print(f"edits.delete: HTTP {status}")


def main() -> int:
    try:
        service_account_path = keychain_password(PACKAGE_NAME, KEYCHAIN_SERVICE)
        token = android_publisher_token(service_account_path)
    except Exception as exc:
        print(f"setup failed: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1

    base_url = (
        "https://androidpublisher.googleapis.com/androidpublisher/v3/"
        f"applications/{PACKAGE_NAME}"
    )
    print(f"package: {PACKAGE_NAME}")
    print_subscriptions(base_url, token)
    print_expected_subscription_details(base_url, token)
    print_tracks(base_url, token)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
