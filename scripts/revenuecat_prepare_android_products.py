#!/usr/bin/env python3
import argparse
import hashlib
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path


ENV_PATH = Path.home() / ".hermes" / "secrets" / "revenuecat" / "credentials.env"
EXPECTED_PRODUCTS = [
    {
        "period": "weekly",
        "storeIdentifier": "com.ezcar24.business.weekly:weekly",
        "displayName": "Weekly",
        "packageLookupKey": "$rc_weekly",
        "packageDisplayName": "Weekly",
        "packagePosition": 0,
    },
    {
        "period": "monthly",
        "storeIdentifier": "com.ezcar24.business.monthly:monthly",
        "displayName": "Monthly",
        "packageLookupKey": "$rc_monthly",
        "packageDisplayName": "Monthly",
        "packagePosition": 1,
    },
    {
        "period": "quarterly",
        "storeIdentifier": "com.ezcar24.business.quarterly:quarterly",
        "displayName": "Quarterly",
        "packageLookupKey": "$rc_three_month",
        "packageDisplayName": "Quarterly",
        "packagePosition": 3,
    },
    {
        "period": "yearly",
        "storeIdentifier": "com.ezcar24.business.yearly:yearly",
        "displayName": "Yearly",
        "packageLookupKey": "$rc_annual",
        "packageDisplayName": "Yearly",
        "packagePosition": 2,
    },
]


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.removeprefix("export ").strip()
        values[key] = value.strip().strip('"').strip("'")
    return values


def api_request(method: str, url: str, token: str, body: dict | None = None):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
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
            payload = {"raw": raw[:1000]}
        return error.code, payload


def error_message(payload) -> str:
    if isinstance(payload, dict):
        return payload.get("message") or payload.get("error", {}).get("message") or payload.get("raw") or ""
    return "" if payload is None else str(payload)


def list_items(base_url: str, token: str, path: str) -> list[dict]:
    status, payload = api_request("GET", f"{base_url}{path}", token)
    if status != 200 or not isinstance(payload, dict):
        raise RuntimeError(f"GET {path} HTTP {status}: {error_message(payload)}")
    return payload.get("items", [])


def public_sdk_key() -> str:
    props_path = Path.home() / ".gradle" / "gradle.properties"
    if not props_path.exists():
        return ""
    for raw in props_path.read_text().splitlines():
        line = raw.strip()
        if line.startswith("REVENUECAT_ANDROID_API_KEY="):
            return line.split("=", 1)[1].strip()
    return ""


def key_summary(key: str) -> str:
    if not key:
        return "missing"
    digest = hashlib.sha256(key.encode()).hexdigest()[:12]
    return f"prefix={key[:5]}; len={len(key)}; sha256_12={digest}"


def safe_public_key_match(base_url: str, token: str, app_id: str, local_key: str) -> bool | None:
    status, payload = api_request("GET", f"{base_url}/apps/{app_id}/public_api_keys", token)
    if status != 200 or not isinstance(payload, dict):
        print(f"android_public_api_keys: HTTP {status}; {error_message(payload)}")
        return None

    keys = [item.get("key", "") for item in payload.get("items", []) if isinstance(item, dict)]
    matches_local = bool(local_key) and any(key == local_key for key in keys)
    key_summaries = [
        key_summary(key)
        for key in keys
    ]
    print(f"android_public_api_keys: count={len(keys)}; local_match={matches_local}; keys={key_summaries}")
    return matches_local


def check_public_offerings(sdk_key: str) -> tuple[int, str | None, list[str]]:
    request = urllib.request.Request(
        "https://api.revenuecat.com/v1/subscribers/codex-android-offering-check/offerings",
        headers={
            "Authorization": f"Bearer {sdk_key}",
            "X-Platform": "android",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.loads(response.read().decode())
    value = payload.get("value") if isinstance(payload.get("value"), dict) else payload
    products: list[str] = []
    for offering in value.get("offerings", []):
        for package in offering.get("packages", []):
            identifier = package.get("platform_product_identifier")
            if identifier:
                products.append(identifier)
    return len(value.get("offerings", [])), value.get("current_offering_id"), sorted(set(products))


def product_from_association(item: dict) -> dict:
    product = item.get("product")
    return product if isinstance(product, dict) else item


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prepare RevenueCat Android products, entitlement links, and default offering packages."
    )
    parser.add_argument("--apply", action="store_true", help="Create and attach missing RevenueCat objects")
    args = parser.parse_args()

    if not ENV_PATH.exists():
        print(f"Missing RevenueCat credentials env: {ENV_PATH}", file=sys.stderr)
        return 1

    env = load_env(ENV_PATH)
    project_id = env.get("REVENUECAT_PROJECT_ID_CARDEALERTRACKER", "")
    token = env.get("REVENUECAT_PRIVATE_API_KEY_CARDEALERTRACKER", "")
    if not project_id or not token:
        print("Missing CarDealerTracker RevenueCat project id or private API key", file=sys.stderr)
        return 1

    base_url = f"https://api.revenuecat.com/v2/projects/{project_id}"
    print(f"mode: {'apply' if args.apply else 'dry-run'}")

    apps = list_items(base_url, token, "/apps?limit=20")
    android_app = next((item for item in apps if item.get("type") == "play_store"), None)
    if not android_app:
        print("RevenueCat Android play_store app not found", file=sys.stderr)
        return 1
    android_app_id = android_app["id"]
    print(f"android_app: {android_app.get('name')} ({android_app_id})")

    offerings = list_items(base_url, token, "/offerings?limit=20")
    default_offering = next((item for item in offerings if item.get("lookup_key") == "default"), None)
    if not default_offering:
        print("RevenueCat default offering not found", file=sys.stderr)
        return 1
    offering_id = default_offering["id"]
    print(f"default_offering: {offering_id}; is_current={default_offering.get('is_current')}")

    entitlements = list_items(base_url, token, "/entitlements?limit=20")
    entitlement = next((item for item in entitlements if item.get("state") == "active"), None)
    if not entitlement:
        print("RevenueCat active entitlement not found", file=sys.stderr)
        return 1
    entitlement_id = entitlement["id"]
    print(f"entitlement: {entitlement.get('lookup_key')} ({entitlement_id})")

    products = list_items(base_url, token, "/products?limit=100")
    product_by_store_id = {
        product.get("store_identifier"): product
        for product in products
        if product.get("app_id") == android_app_id and product.get("state") == "active"
    }

    failures = 0
    for expected in EXPECTED_PRODUCTS:
        store_identifier = expected["storeIdentifier"]
        product = product_by_store_id.get(store_identifier)
        if product:
            print(f"{store_identifier}: product exists ({product['id']})")
            continue
        print(f"{store_identifier}: product missing")
        if not args.apply:
            continue
        status, payload = api_request(
            "POST",
            f"{base_url}/products",
            token,
            {
                "store_identifier": store_identifier,
                "app_id": android_app_id,
                "type": "subscription",
                "display_name": expected["displayName"],
            },
        )
        if status not in (200, 201) or not isinstance(payload, dict):
            print(f"{store_identifier}: create HTTP {status}; {error_message(payload)}")
            failures += 1
            continue
        product_by_store_id[store_identifier] = payload
        print(f"{store_identifier}: create HTTP {status}; product={payload.get('id')}")

    if failures:
        return 1

    entitlement_products = [
        product_from_association(item)
        for item in list_items(base_url, token, f"/entitlements/{entitlement_id}/products?limit=100")
    ]
    entitlement_product_ids = {item.get("id") for item in entitlement_products}
    missing_entitlement_ids = [
        product_by_store_id[expected["storeIdentifier"]]["id"]
        for expected in EXPECTED_PRODUCTS
        if expected["storeIdentifier"] in product_by_store_id
        and product_by_store_id[expected["storeIdentifier"]]["id"] not in entitlement_product_ids
    ]
    print(f"entitlement_missing_android_products={len(missing_entitlement_ids)}")
    if args.apply and missing_entitlement_ids:
        status, payload = api_request(
            "POST",
            f"{base_url}/entitlements/{entitlement_id}/actions/attach_products",
            token,
            {"product_ids": missing_entitlement_ids},
        )
        print(f"entitlement.attach_products: HTTP {status}; {error_message(payload)}")
        if status != 200:
            failures += 1

    packages = list_items(base_url, token, f"/offerings/{offering_id}/packages?limit=100&expand=items.product")
    package_by_lookup = {package.get("lookup_key"): package for package in packages}
    for expected in EXPECTED_PRODUCTS:
        package = package_by_lookup.get(expected["packageLookupKey"])
        if package:
            print(f"{expected['packageLookupKey']}: package exists ({package['id']})")
            continue
        print(f"{expected['packageLookupKey']}: package missing")
        if not args.apply:
            continue
        status, payload = api_request(
            "POST",
            f"{base_url}/offerings/{offering_id}/packages",
            token,
            {
                "lookup_key": expected["packageLookupKey"],
                "display_name": expected["packageDisplayName"],
                "position": expected["packagePosition"],
            },
        )
        if status not in (200, 201) or not isinstance(payload, dict):
            print(f"{expected['packageLookupKey']}: create HTTP {status}; {error_message(payload)}")
            failures += 1
            continue
        package_by_lookup[expected["packageLookupKey"]] = payload
        print(f"{expected['packageLookupKey']}: create HTTP {status}; package={payload.get('id')}")

    if failures:
        return 1

    for expected in EXPECTED_PRODUCTS:
        product = product_by_store_id.get(expected["storeIdentifier"])
        package = package_by_lookup.get(expected["packageLookupKey"])
        if not product or not package:
            continue
        product_ids = {
            product_from_association(item).get("id")
            for item in package.get("products", {}).get("items", [])
        }
        if product["id"] in product_ids:
            print(f"{expected['packageLookupKey']}: android product attached")
            continue
        print(f"{expected['packageLookupKey']}: android product missing")
        if not args.apply:
            continue
        status, payload = api_request(
            "POST",
            f"{base_url}/packages/{package['id']}/actions/attach_products",
            token,
            {"products": [{"product_id": product["id"], "eligibility_criteria": "all"}]},
        )
        print(f"{expected['packageLookupKey']}: attach_products HTTP {status}; {error_message(payload)}")
        if status != 200:
            failures += 1

    sdk_key = public_sdk_key()
    if sdk_key:
        print(f"local_revenuecat_sdk_key: {key_summary(sdk_key)}")
        safe_public_key_match(base_url, token, android_app_id, sdk_key)
        try:
            count, current, public_products = check_public_offerings(sdk_key)
            public_product_keys = {
                product
                for product in public_products
            } | {
                product.split(":", 1)[0]
                for product in public_products
            }
            missing_public = sorted(
                expected["storeIdentifier"] for expected in EXPECTED_PRODUCTS
                if expected["storeIdentifier"] not in public_product_keys
                and expected["storeIdentifier"].split(":", 1)[0] not in public_product_keys
            )
            print(f"public_offerings: count={count}; current={current}; products={public_products}; missing={missing_public}")
            if missing_public:
                print(
                    "public_offerings_note: Management API objects are present, but the SDK-facing "
                    "v1 endpoint has not returned Android packages yet. If RevenueCat Google Play "
                    "service credentials were just changed, wait for store sync and verify on a "
                    "Play-installed tester build."
                )
        except Exception as exc:
            print(f"public_offerings: check failed: {type(exc).__name__}: {exc}")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
