#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/ezcar24-feedback-loop"
STATE_DIR="/var/lib/ezcar24-feedback-loop"
ENV_FILE="/etc/ezcar24-feedback-loop.env"
SERVICE_USER="ezcar24"

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js 20+ is required. Install Node first, then re-run this script." >&2
  exit 1
fi

NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])')"
if [ "$NODE_MAJOR" -lt 20 ]; then
  echo "Node.js 20+ is required. Current version: $(node -v)" >&2
  exit 1
fi

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir "$STATE_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
fi

mkdir -p "$APP_DIR" "$STATE_DIR/state" "$STATE_DIR/reports" "$STATE_DIR/data/apple-ads"
cp -R package.json package-lock.json src systemd "$APP_DIR"/

if [ ! -f "$ENV_FILE" ]; then
  cp .env.example "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "Created $ENV_FILE. Fill in R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY before starting the service."
fi

chown -R root:root "$APP_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" "$STATE_DIR"

cd "$APP_DIR"
npm ci --omit=dev

cp "$APP_DIR/systemd/ezcar24-feedback-loop.service" /etc/systemd/system/
cp "$APP_DIR/systemd/ezcar24-feedback-loop.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable ezcar24-feedback-loop.timer

echo "Installed. Edit $ENV_FILE, then run:"
echo "  sudo systemctl start ezcar24-feedback-loop.service"
echo "  sudo journalctl -u ezcar24-feedback-loop.service -n 80 --no-pager"
