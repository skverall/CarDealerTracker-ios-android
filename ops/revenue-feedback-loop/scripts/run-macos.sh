#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${EZCAR24_FEEDBACK_LOOP_DIR:-/Volumes/LexarDev/Developer/Services/ezcar24-feedback-loop}"
MAX_LOG_BYTES="${MAX_LOG_BYTES:-1048576}"
OUT_LOG="$APP_DIR/logs/feedback-loop.out.log"
ERR_LOG="$APP_DIR/logs/feedback-loop.err.log"

mkdir -p "$APP_DIR/logs"

for file in "$OUT_LOG" "$ERR_LOG"; do
  if [ -f "$file" ] && [ "$(wc -c < "$file")" -gt "$MAX_LOG_BYTES" ]; then
    tail -c "$MAX_LOG_BYTES" "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
  fi
done

if [ "${EZCAR24_FEEDBACK_LOOP_LOG_REDIRECTED:-0}" != "1" ]; then
  export EZCAR24_FEEDBACK_LOOP_LOG_REDIRECTED=1
  exec /bin/bash "$0" >> "$OUT_LOG" 2>> "$ERR_LOG"
fi

cd "$APP_DIR"
exec npm run run -- --env "$APP_DIR/.env"
