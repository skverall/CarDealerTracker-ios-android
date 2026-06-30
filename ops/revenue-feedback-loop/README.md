# EzCar24 Revenue Feedback Loop

Small read-only worker for the Apple Ads feedback loop.

It reads RevenueCat Scheduled Data Exports from Cloudflare R2, optionally reads Apple Ads CSV exports, and writes daily markdown/JSON reports with bid and keyword recommendations. It does not mutate Apple Ads campaigns.

## What It Uses

- RevenueCat export bucket: `ezcar24-revenuecat-exports`
- RevenueCat folder: `revenuecat/transactions_v2`
- Cloudflare R2 S3-compatible endpoint: `https://677b373460621c1d9ac6dc7ffb4de2f3.r2.cloudflarestorage.com`
- Optional Apple Ads CSV directory: `./data/apple-ads`

## Local Smoke Run

```bash
cd ops/revenue-feedback-loop
cp .env.example .env
npm install
npm run check
npm run once -- --env .env
```

The `.env` file must contain a bucket-scoped R2 access key. Use a separate key for this worker. `Object Read only` is enough unless `REPORT_R2_PREFIX` is configured.

## Apple Ads Data

RevenueCat revenue is pulled automatically from R2. For spend, export Apple Ads Search Results data as CSV and put it in:

```text
ops/revenue-feedback-loop/data/apple-ads/
```

The parser accepts common Apple Ads columns such as `Campaign`, `Ad Group`, `Keyword`, `Spend`, `Taps`, `Impressions`, `Installs`, and `Date`.

## Recommended: Mac Mini Install

This is the cleanest setup when the Mac mini is always on. Runtime files stay on the external disk:

```text
/Volumes/LexarDev/Developer/Services/ezcar24-feedback-loop/
```

Install:

```bash
cd ops/revenue-feedback-loop
bash scripts/install-macos-cron.sh
```

The installer creates the app directory and `.env`, but it does not install the cron schedule until R2 credentials are filled. Add a separate bucket-scoped read key:

```bash
nano /Volumes/LexarDev/Developer/Services/ezcar24-feedback-loop/.env
```

Then rerun the installer to load the LaunchAgent:

```bash
bash scripts/install-macos-cron.sh
```

Run once:

```bash
/bin/bash /Volumes/LexarDev/Developer/Services/ezcar24-feedback-loop/scripts/run-macos.sh
```

View logs:

```bash
tail -n 120 /Volumes/LexarDev/Developer/Services/ezcar24-feedback-loop/logs/feedback-loop.out.log
tail -n 120 /Volumes/LexarDev/Developer/Services/ezcar24-feedback-loop/logs/feedback-loop.err.log
```

The cron schedule runs daily at 10:30 local time. Reports older than `REPORT_RETENTION_DAYS` and local Apple Ads CSVs older than `APPLE_ADS_CSV_RETENTION_DAYS` are deleted automatically. Logs are trimmed to about 1 MB per file before each run.

## VPS Install

On the VPS:

```bash
cd /tmp/ezcar24-feedback-loop
sudo bash scripts/install-vps.sh
sudo nano /etc/ezcar24-feedback-loop.env
sudo systemctl start ezcar24-feedback-loop.service
sudo journalctl -u ezcar24-feedback-loop.service -n 80 --no-pager
```

The timer runs daily:

```bash
systemctl list-timers ezcar24-feedback-loop.timer
```

Reports are written to `/var/lib/ezcar24-feedback-loop/reports` on the VPS.
