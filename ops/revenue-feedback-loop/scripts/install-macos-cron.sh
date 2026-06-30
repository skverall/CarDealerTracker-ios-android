#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="/Volumes/LexarDev/Developer/Services/ezcar24-feedback-loop"
NODE_BIN="$(command -v node || true)"
NPM_BIN="$(command -v npm || true)"
CRON_TAG="ezcar24-feedback-loop"
CRON_LINE="30 10 * * * /bin/bash $APP_DIR/scripts/run-macos.sh # $CRON_TAG"

if [ -z "$NODE_BIN" ] || [ -z "$NPM_BIN" ]; then
  echo "Node.js and npm are required." >&2
  exit 1
fi

NODE_MAJOR="$("$NODE_BIN" -p 'Number(process.versions.node.split(".")[0])')"
if [ "$NODE_MAJOR" -lt 20 ]; then
  echo "Node.js 20+ is required. Current version: $("$NODE_BIN" -v)" >&2
  exit 1
fi

mkdir -p "$APP_DIR" "$APP_DIR/data/apple-ads" "$APP_DIR/logs" "$APP_DIR/reports" "$APP_DIR/state"
rsync -a --delete \
  --exclude ".env" \
  --exclude "CREDENTIALS.md" \
  --exclude "data" \
  --exclude "logs" \
  --exclude "node_modules" \
  --exclude "reports" \
  --exclude "state" \
  "$SOURCE_DIR/" "$APP_DIR/"

if [ ! -f "$APP_DIR/.env" ]; then
  cp "$SOURCE_DIR/.env.example" "$APP_DIR/.env"
  chmod 600 "$APP_DIR/.env"
  sed -i '' "s|^STATE_DIR=.*|STATE_DIR=$APP_DIR/state|" "$APP_DIR/.env"
  sed -i '' "s|^REPORT_DIR=.*|REPORT_DIR=$APP_DIR/reports|" "$APP_DIR/.env"
  sed -i '' "s|^APPLE_ADS_CSV_DIR=.*|APPLE_ADS_CSV_DIR=$APP_DIR/data/apple-ads|" "$APP_DIR/.env"
fi

cd "$APP_DIR"
npm install --omit=dev

if grep -Eq '^R2_ACCESS_KEY_ID=.+$' "$APP_DIR/.env" && grep -Eq '^R2_SECRET_ACCESS_KEY=.+$' "$APP_DIR/.env"; then
  CURRENT_CRON="$(crontab -l 2>/dev/null || true)"
  if printf '%s\n' "$CURRENT_CRON" | grep -Fqx "$CRON_LINE"; then
    true
  else
    CRON_TMP="$(mktemp)"
    printf '%s\n' "$CURRENT_CRON" | grep -v "$CRON_TAG" > "$CRON_TMP" || true
    echo "$CRON_LINE" >> "$CRON_TMP"
    crontab "$CRON_TMP"
    rm -f "$CRON_TMP"
  fi
  echo "Installed local feedback loop cron."
  echo "App dir: $APP_DIR"
  echo "Env file: $APP_DIR/.env"
  echo "Cron: $CRON_LINE"
  echo
  echo "Run once:"
  echo "  /bin/bash $APP_DIR/scripts/run-macos.sh"
else
  echo "Installed files, but R2 credentials are not filled yet."
  echo "Fill R2 credentials in $APP_DIR/.env, then run this installer again."
fi
