#!/usr/bin/env bash
set -euo pipefail

echo "macOS may block LaunchAgents from reading scripts on external volumes."
echo "Installing the local feedback loop with user cron instead."
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-macos-cron.sh"
