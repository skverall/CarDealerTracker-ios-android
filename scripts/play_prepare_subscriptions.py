#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from decimal import Decimal

from google.auth.transport.requests import Request
from google.oauth2 import service_account


PACKAGE_NAME = os.environ.get("PLAY_PACKAGE_NAME", "com.ezcar24.business")
KEYCHAIN_SERVICE = os.environ.get(
    "PLAY_SERVICE_ACCOUNT_KEYCHAIN_SERVICE",
    f"googleplay.{PACKAGE_NAME}.service_account_json_path",
)

PLANS = [
    {
        "period": "weekly",
        "productId": "com.ezcar24.business.weekly",
        "basePlanId": "weekly",
        "billingPeriodDuration": "P1W",
        "title": "Weekly Plan",
        "usdPrice": "3.99",
    },
    {
        "period": "monthly",
        "productId": "com.ezcar24.business.monthly",
        "basePlanId": "monthly",
        "billingPeriodDuration": "P1M",
        "title": "Monthly Plan",
        "usdPrice": "14.99",
    },
    {
        "period": "quarterly",
        "productId": "com.ezcar24.business.quarterly",
        "basePlanId": "quarterly",
        "billingPeriodDuration": "P3M",
        "title": "Quarterly Plan",
        "usdPrice": "24.99",
    },
    {
        "period": "yearly",
        "productId": "com.ezcar24.business.yearly",
        "basePlanId": "yearly",
        "billingPeriodDuration": "P1Y",
        "title": "Yearly Plan",
        "usdPrice": "119.99",
    },
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


def money(value: str, currency: str = "USD") -> dict:
    amount = Decimal(value)
    units = int(amount)
    nanos = int((amount - Decimal(units)) * Decimal(1_000_000_000))
    return {
        "currencyCode": currency,
        "units": str(units),
        "nanos": nanos,
    }


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
        with urllib.request.urlopen(request, timeout=60) as response:
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


def convert_region_prices(base_url: str, token: str, usd_price: str) -> tuple[dict, dict]:
    status, payload = api_request(
        "POST",
        f"{base_url}/pricing:convertRegionPrices",
        token,
        {"price": money(usd_price)},
    )
    if status != 200 or not isinstance(payload, dict):
        raise RuntimeError(f"convertRegionPrices HTTP {status}: {error_message(payload)}")
    region_version = payload.get("regionVersion")
    if not isinstance(region_version, dict) or not region_version.get("version"):
        raise RuntimeError("convertRegionPrices returned no regionVersion")
    return payload, region_version


def subscription_payload(plan: dict, converted: dict) -> dict:
    regional_configs = [
        {
            "regionCode": region_code,
            "newSubscriberAvailability": True,
            "price": region_price["price"],
        }
        for region_code, region_price in sorted(
            converted.get("convertedRegionPrices", {}).items()
        )
        if isinstance(region_price, dict) and region_price.get("price")
    ]
    other_regions_price = converted.get("convertedOtherRegionsPrice")
    if not regional_configs:
        raise RuntimeError(f"{plan['productId']}: no converted regional prices")
    if not isinstance(other_regions_price, dict):
        raise RuntimeError(f"{plan['productId']}: no converted other regions price")

    return {
        "packageName": PACKAGE_NAME,
        "productId": plan["productId"],
        "basePlans": [
            {
                "basePlanId": plan["basePlanId"],
                "regionalConfigs": regional_configs,
                "otherRegionsConfig": {
                    "usdPrice": other_regions_price["usdPrice"],
                    "eurPrice": other_regions_price["eurPrice"],
                    "newSubscriberAvailability": True,
                },
                "autoRenewingBasePlanType": {
                    "billingPeriodDuration": plan["billingPeriodDuration"],
                    "resubscribeState": "RESUBSCRIBE_STATE_ACTIVE",
                    "prorationMode": "SUBSCRIPTION_PRORATION_MODE_CHARGE_ON_NEXT_BILLING_DATE",
                },
            }
        ],
        "listings": [
            {
                "languageCode": "en-US",
                "title": plan["title"],
                "benefits": [
                    "Unlimited vehicle inventory",
                    "AI insights and analytics",
                    "Cloud sync and team tools",
                ],
                "description": "Pro access for Car Dealer Tracker.",
            }
        ],
    }


def get_subscription(base_url: str, token: str, product_id: str):
    encoded_id = urllib.parse.quote(product_id, safe="")
    return api_request("GET", f"{base_url}/subscriptions/{encoded_id}", token)


def create_subscription(base_url: str, token: str, payload: dict, region_version: dict):
    query = urllib.parse.urlencode(
        {
            "productId": payload["productId"],
            "regionsVersion.version": region_version["version"],
        }
    )
    return api_request("POST", f"{base_url}/subscriptions?{query}", token, payload)


def activate_base_plan(base_url: str, token: str, plan: dict):
    product_id = urllib.parse.quote(plan["productId"], safe="")
    base_plan_id = urllib.parse.quote(plan["basePlanId"], safe="")
    return api_request(
        "POST",
        f"{base_url}/subscriptions/{product_id}/basePlans/{base_plan_id}:activate",
        token,
        {},
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prepare Google Play subscription products for EzCar24 Business."
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Create missing subscription products as draft products in Google Play.",
    )
    parser.add_argument(
        "--activate",
        action="store_true",
        help="Activate base plans after creating or finding them.",
    )
    args = parser.parse_args()

    if args.activate and not args.apply:
        print("--activate requires --apply", file=sys.stderr)
        return 2

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
    mode = "apply" if args.apply else "dry-run"
    print(f"package: {PACKAGE_NAME}")
    print(f"mode: {mode}")

    failures = 0
    for plan in PLANS:
        product_id = plan["productId"]
        status, payload = get_subscription(base_url, token, product_id)
        if status == 200:
            base_plans = payload.get("basePlans", []) if isinstance(payload, dict) else []
            states = [item.get("state") for item in base_plans if item.get("state")]
            print(f"{product_id}: exists; basePlans={len(base_plans)}; states={states}")
            if args.apply and args.activate:
                activate_status, activate_payload = activate_base_plan(base_url, token, plan)
                print(
                    f"{product_id}: activate HTTP {activate_status}; "
                    f"{error_message(activate_payload)}"
                )
            continue
        if status != 404:
            print(f"{product_id}: get HTTP {status}; {error_message(payload)}")
            failures += 1
            continue

        try:
            converted, region_version = convert_region_prices(
                base_url,
                token,
                plan["usdPrice"],
            )
            payload = subscription_payload(plan, converted)
        except Exception as exc:
            print(f"{product_id}: prepare failed: {exc}")
            failures += 1
            continue

        region_count = len(payload["basePlans"][0]["regionalConfigs"])
        print(
            f"{product_id}: missing; usd={plan['usdPrice']}; "
            f"duration={plan['billingPeriodDuration']}; "
            f"regions={region_count}; regionVersion={region_version['version']}"
        )
        if not args.apply:
            continue

        create_status, create_payload = create_subscription(
            base_url,
            token,
            payload,
            region_version,
        )
        print(f"{product_id}: create HTTP {create_status}; {error_message(create_payload)}")
        if create_status not in (200, 201):
            failures += 1
            continue
        if args.activate:
            activate_status, activate_payload = activate_base_plan(base_url, token, plan)
            print(
                f"{product_id}: activate HTTP {activate_status}; "
                f"{error_message(activate_payload)}"
            )
            if activate_status not in (200, 204):
                failures += 1

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
