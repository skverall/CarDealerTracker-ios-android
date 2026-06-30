#!/usr/bin/env node

import { GetObjectCommand, ListObjectsV2Command, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { parse as parseCsv } from "csv-parse/sync";
import { gunzipSync } from "node:zlib";
import fs from "node:fs/promises";
import path from "node:path";

const DEFAULT_ENV_FILE = ".env";

async function main() {
  const args = process.argv.slice(2);
  const command = args[0] || "run";
  const envPath = readArg(args, "--env") || DEFAULT_ENV_FILE;
  await loadEnv(envPath);

  if (command !== "run") {
    throw new Error(`Unknown command: ${command}`);
  }

  const config = getConfig();
  await ensureDir(config.stateDir);
  await ensureDir(config.reportDir);
  await ensureDir(config.appleAdsCsvDir);

  const s3 = createR2Client(config);
  const state = await readState(config.statePath);

  const revenueLoad = await loadRevenueCatExports(s3, config, state);
  const appleAdsLoad = await loadAppleAdsExports(s3, config);
  const analysis = analyze(revenueLoad.rows, appleAdsLoad.rows, config);

  const reportDate = today();
  const report = renderReport(reportDate, revenueLoad, appleAdsLoad, analysis, config);
  const reportPath = path.join(config.reportDir, `${reportDate}.md`);
  const jsonPath = path.join(config.reportDir, `${reportDate}.json`);

  await fs.writeFile(reportPath, report, "utf8");
  await fs.writeFile(jsonPath, `${JSON.stringify(analysis, null, 2)}\n`, "utf8");
  await writeState(config.statePath, state);
  await cleanupReports(config.reportDir, config.reportRetentionDays);
  await cleanupCsvInputs(config.appleAdsCsvDir, config.appleAdsCsvRetentionDays);

  if (config.reportR2Prefix) {
    await uploadReport(s3, config, reportDate, report, analysis);
  }

  console.log(`report=${reportPath}`);
  console.log(`json=${jsonPath}`);
  console.log(`revenue_rows=${revenueLoad.rows.length}`);
  console.log(`apple_ads_rows=${appleAdsLoad.rows.length}`);
  console.log(`recommendations=${analysis.recommendations.length}`);
}

function readArg(args, name) {
  const index = args.indexOf(name);
  if (index === -1) return null;
  return args[index + 1] || null;
}

async function loadEnv(envPath) {
  let text;
  try {
    text = await fs.readFile(envPath, "utf8");
  } catch (error) {
    if (envPath === DEFAULT_ENV_FILE && error.code === "ENOENT") return;
    throw error;
  }

  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match) continue;
    const [, key, rawValue] = match;
    if (process.env[key] !== undefined) continue;
    process.env[key] = stripQuotes(rawValue.trim());
  }
}

function stripQuotes(value) {
  if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
    return value.slice(1, -1);
  }
  return value;
}

function getConfig() {
  const accountId = env("R2_ACCOUNT_ID", "");
  const endpointUrl = env("R2_ENDPOINT_URL", accountId ? `https://${accountId}.r2.cloudflarestorage.com` : "");
  const stateDir = env("STATE_DIR", "./state");
  const reportDir = env("REPORT_DIR", "./reports");

  return {
    r2EndpointUrl: required("R2_ENDPOINT_URL", endpointUrl),
    r2AccessKeyId: required("R2_ACCESS_KEY_ID"),
    r2SecretAccessKey: required("R2_SECRET_ACCESS_KEY"),
    r2Bucket: env("R2_BUCKET", "ezcar24-revenuecat-exports"),
    revenueCatPrefix: normalizePrefix(env("R2_REVENUECAT_PREFIX", "revenuecat/transactions_v2/")),
    appleAdsCsvDir: env("APPLE_ADS_CSV_DIR", "./data/apple-ads"),
    appleAdsR2Prefix: normalizePrefix(env("APPLE_ADS_R2_PREFIX", "")),
    reportR2Prefix: normalizePrefix(env("REPORT_R2_PREFIX", "")),
    stateDir,
    statePath: path.join(stateDir, "processed.json"),
    reportDir,
    reportRetentionDays: Number(env("REPORT_RETENTION_DAYS", "90")),
    appleAdsCsvRetentionDays: Number(env("APPLE_ADS_CSV_RETENTION_DAYS", "180")),
    lookbackDays: Number(env("LOOKBACK_DAYS", "30")),
    minSpendForAction: Number(env("MIN_SPEND_FOR_ACTION", "10")),
    scaleRoasThreshold: Number(env("SCALE_ROAS_THRESHOLD", "1.25")),
    cutRoasThreshold: Number(env("CUT_ROAS_THRESHOLD", "0.35")),
    minRevenueForScale: Number(env("MIN_REVENUE_FOR_SCALE", "5"))
  };
}

function env(name, fallback) {
  const value = process.env[name];
  return value === undefined || value === "" ? fallback : value;
}

function required(name, fallback = undefined) {
  const value = env(name, fallback);
  if (!value) throw new Error(`Missing required env: ${name}`);
  return value;
}

function normalizePrefix(prefix) {
  if (!prefix) return "";
  return prefix.endsWith("/") ? prefix : `${prefix}/`;
}

function createR2Client(config) {
  return new S3Client({
    region: "auto",
    endpoint: config.r2EndpointUrl,
    forcePathStyle: true,
    credentials: {
      accessKeyId: config.r2AccessKeyId,
      secretAccessKey: config.r2SecretAccessKey
    }
  });
}

async function loadRevenueCatExports(s3, config, state) {
  const objects = await listObjects(s3, config.r2Bucket, config.revenueCatPrefix);
  const eligible = objects
    .filter((object) => isCsvKey(object.Key))
    .filter((object) => shouldReadObject(object, state));

  const rows = [];
  const processed = [];
  for (const object of eligible) {
    const buffer = await getObjectBuffer(s3, config.r2Bucket, object.Key);
    const fileRows = parseCsvBuffer(buffer, object.Key);
    rows.push(...fileRows.map((row) => ({ ...row, __source_key: object.Key })));
    state.objects[object.Key] = {
      etag: object.ETag || null,
      lastModified: object.LastModified ? object.LastModified.toISOString() : null,
      rows: fileRows.length,
      processedAt: new Date().toISOString()
    };
    processed.push({ key: object.Key, rows: fileRows.length });
  }

  if (rows.length === 0 && objects.length > 0) {
    const recentObjects = objects.filter((object) => isCsvKey(object.Key)).slice(-5);
    for (const object of recentObjects) {
      const buffer = await getObjectBuffer(s3, config.r2Bucket, object.Key);
      rows.push(...parseCsvBuffer(buffer, object.Key).map((row) => ({ ...row, __source_key: object.Key })));
    }
  }

  return {
    objectsSeen: objects.length,
    objectsProcessed: processed,
    rows
  };
}

async function loadAppleAdsExports(s3, config) {
  const rows = [];
  const sources = [];

  try {
    const localFiles = await listLocalCsvFiles(config.appleAdsCsvDir);
    for (const filePath of localFiles) {
      const buffer = await fs.readFile(filePath);
      const fileRows = parseCsvBuffer(buffer, filePath);
      rows.push(...fileRows.map((row) => ({ ...row, __source_key: filePath })));
      sources.push({ source: filePath, rows: fileRows.length });
    }
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }

  if (config.appleAdsR2Prefix) {
    const objects = await listObjects(s3, config.r2Bucket, config.appleAdsR2Prefix);
    for (const object of objects.filter((candidate) => isCsvKey(candidate.Key))) {
      const buffer = await getObjectBuffer(s3, config.r2Bucket, object.Key);
      const fileRows = parseCsvBuffer(buffer, object.Key);
      rows.push(...fileRows.map((row) => ({ ...row, __source_key: object.Key })));
      sources.push({ source: object.Key, rows: fileRows.length });
    }
  }

  return { rows, sources };
}

async function listObjects(s3, bucket, prefix) {
  const objects = [];
  let ContinuationToken;
  do {
    const response = await s3.send(new ListObjectsV2Command({ Bucket: bucket, Prefix: prefix, ContinuationToken }));
    objects.push(...(response.Contents || []));
    ContinuationToken = response.NextContinuationToken;
  } while (ContinuationToken);
  return objects.sort((a, b) => String(a.Key).localeCompare(String(b.Key)));
}

async function getObjectBuffer(s3, bucket, key) {
  const response = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  const bytes = await response.Body.transformToByteArray();
  return Buffer.from(bytes);
}

async function uploadReport(s3, config, reportDate, markdown, analysis) {
  const prefix = config.reportR2Prefix;
  await s3.send(new PutObjectCommand({
    Bucket: config.r2Bucket,
    Key: `${prefix}${reportDate}.md`,
    Body: markdown,
    ContentType: "text/markdown; charset=utf-8"
  }));
  await s3.send(new PutObjectCommand({
    Bucket: config.r2Bucket,
    Key: `${prefix}${reportDate}.json`,
    Body: JSON.stringify(analysis, null, 2),
    ContentType: "application/json; charset=utf-8"
  }));
}

async function listLocalCsvFiles(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  return entries
    .filter((entry) => entry.isFile() && isCsvKey(entry.name))
    .map((entry) => path.join(dir, entry.name))
    .sort();
}

function isCsvKey(key = "") {
  return key.endsWith(".csv") || key.endsWith(".csv.gz");
}

function parseCsvBuffer(buffer, key) {
  const data = key.endsWith(".gz") ? gunzipSync(buffer) : buffer;
  return parseCsv(data.toString("utf8"), {
    bom: true,
    columns: true,
    relax_column_count: true,
    skip_empty_lines: true,
    trim: true
  });
}

function shouldReadObject(object, state) {
  const existing = state.objects[object.Key];
  if (!existing) return true;
  if (existing.etag && object.ETag && existing.etag !== object.ETag) return true;
  return false;
}

async function readState(statePath) {
  try {
    const parsed = JSON.parse(await fs.readFile(statePath, "utf8"));
    return { objects: parsed.objects || {} };
  } catch (error) {
    if (error.code === "ENOENT") return { objects: {} };
    throw error;
  }
}

async function writeState(statePath, state) {
  await ensureDir(path.dirname(statePath));
  await fs.writeFile(statePath, `${JSON.stringify(state, null, 2)}\n`, "utf8");
}

async function cleanupReports(reportDir, retentionDays) {
  await cleanupFiles(reportDir, retentionDays, [".md", ".json"]);
}

async function cleanupCsvInputs(csvDir, retentionDays) {
  await cleanupFiles(csvDir, retentionDays, [".csv", ".csv.gz"]);
}

async function cleanupFiles(dir, retentionDays, extensions) {
  if (!Number.isFinite(retentionDays) || retentionDays <= 0) return;
  const cutoffMs = Date.now() - retentionDays * 24 * 60 * 60 * 1000;
  let entries;
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch (error) {
    if (error.code === "ENOENT") return;
    throw error;
  }

  for (const entry of entries) {
    if (!entry.isFile()) continue;
    if (!extensions.some((extension) => entry.name.endsWith(extension))) continue;
    const filePath = path.join(dir, entry.name);
    const stat = await fs.stat(filePath);
    if (stat.mtimeMs < cutoffMs) {
      await fs.unlink(filePath);
    }
  }
}

async function ensureDir(dir) {
  await fs.mkdir(dir, { recursive: true });
}

function analyze(revenueRows, appleAdsRows, config) {
  const cutoff = daysAgo(config.lookbackDays);
  const revenue = aggregateRevenue(revenueRows, cutoff);
  const spend = aggregateAppleAds(appleAdsRows, cutoff);
  const keys = new Set([...revenue.byDimension.keys(), ...spend.byDimension.keys()]);
  const metrics = [...keys].map((key) => {
    const revenueItem = revenue.byDimension.get(key) || emptyMetric(key);
    const spendItem = spend.byDimension.get(key) || emptyMetric(key);
    const merged = {
      key,
      dimensions: revenueItem.dimensions || spendItem.dimensions,
      revenue: round2(revenueItem.revenue || 0),
      transactions: revenueItem.transactions || 0,
      spend: round2(spendItem.spend || 0),
      installs: spendItem.installs || 0,
      taps: spendItem.taps || 0,
      impressions: spendItem.impressions || 0
    };
    merged.roas = merged.spend > 0 ? round2(merged.revenue / merged.spend) : null;
    merged.cpa = merged.installs > 0 ? round2(merged.spend / merged.installs) : null;
    return merged;
  }).sort((a, b) => (b.spend + b.revenue) - (a.spend + a.revenue));

  return {
    generatedAt: new Date().toISOString(),
    lookbackDays: config.lookbackDays,
    totals: totals(metrics),
    metrics,
    recommendations: recommendations(metrics, config),
    dataQuality: dataQuality(revenueRows, appleAdsRows, revenue, spend)
  };
}

function aggregateRevenue(rows, cutoff) {
  const byDimension = new Map();
  let unattributedRows = 0;

  for (const row of rows) {
    const date = rowDate(row);
    if (date && date < cutoff) continue;
    const dims = revenueDimensions(row);
    if (dims.isUnattributed) unattributedRows += 1;
    const key = dimensionKey(dims);
    const metric = byDimension.get(key) || emptyMetric(key, dims);
    metric.revenue += revenueAmount(row);
    metric.transactions += 1;
    byDimension.set(key, metric);
  }

  return { byDimension, unattributedRows };
}

function aggregateAppleAds(rows, cutoff) {
  const byDimension = new Map();

  for (const row of rows) {
    const date = rowDate(row);
    if (date && date < cutoff) continue;
    const dims = appleAdsDimensions(row);
    const key = dimensionKey(dims);
    const metric = byDimension.get(key) || emptyMetric(key, dims);
    metric.spend += money(row, ["spend", "Spend", "Amount Spent", "Local Spend", "Spend (USD)"]);
    metric.installs += numberField(row, ["installs", "Installs", "Downloads", "New Downloads", "Total Downloads"]);
    metric.taps += numberField(row, ["taps", "Taps", "Clicks"]);
    metric.impressions += numberField(row, ["impressions", "Impressions"]);
    byDimension.set(key, metric);
  }

  return { byDimension };
}

function emptyMetric(key, dimensions = parseDimensionKey(key)) {
  return {
    key,
    dimensions,
    revenue: 0,
    transactions: 0,
    spend: 0,
    installs: 0,
    taps: 0,
    impressions: 0
  };
}

function revenueDimensions(row) {
  const dimensions = {
    campaignId: findField(row, ["campaign_id", "ad_campaign_id", "iad_campaign_id"], [["campaign", "id"]]),
    campaign: findField(row, ["campaign", "campaign_name", "ad_campaign", "iad_campaign_name"], [["campaign"], ["ad", "campaign"]]),
    adGroup: findField(row, ["ad_group", "ad_group_name", "adgroup", "iad_adgroup_name"], [["ad", "group"], ["adgroup"]]),
    keyword: findField(row, ["keyword", "keyword_text", "search_term", "iad_keyword"], [["keyword"], ["search", "term"]]),
    country: findField(row, ["country", "storefront", "subscriber_country"], [["country"], ["storefront"]])
  };
  dimensions.isUnattributed = !dimensions.campaignId && !dimensions.campaign && !dimensions.adGroup && !dimensions.keyword;
  return normalizeDimensions(dimensions);
}

function appleAdsDimensions(row) {
  return normalizeDimensions({
    campaignId: findField(row, ["Campaign ID", "campaign_id", "Campaign Id"], [["campaign", "id"]]),
    campaign: findField(row, ["Campaign", "Campaign Name", "campaign_name"], [["campaign"]]),
    adGroup: findField(row, ["Ad Group", "Ad Group Name", "ad_group_name"], [["ad", "group"], ["adgroup"]]),
    keyword: findField(row, ["Keyword", "Search Term", "keyword_text"], [["keyword"], ["search", "term"]]),
    country: findField(row, ["Country", "Storefront", "Territory"], [["country"], ["storefront"], ["territory"]])
  });
}

function normalizeDimensions(dimensions) {
  return {
    campaignId: cleanDimension(dimensions.campaignId),
    campaign: cleanDimension(dimensions.campaign),
    adGroup: cleanDimension(dimensions.adGroup),
    keyword: cleanDimension(dimensions.keyword),
    country: cleanDimension(dimensions.country),
    isUnattributed: Boolean(dimensions.isUnattributed)
  };
}

function cleanDimension(value) {
  const cleaned = String(value || "").trim();
  if (!cleaned || cleaned === "-" || cleaned.toLowerCase() === "unknown") return "";
  return cleaned;
}

function dimensionKey(dimensions) {
  const parts = [
    dimensions.campaignId || "",
    dimensions.campaign || "",
    dimensions.adGroup || "",
    dimensions.keyword || "",
    dimensions.country || ""
  ];
  return parts.every((part) => !part) ? "unattributed||||" : parts.join("|");
}

function parseDimensionKey(key) {
  const [campaignId = "", campaign = "", adGroup = "", keyword = "", country = ""] = key.split("|");
  return { campaignId, campaign, adGroup, keyword, country, isUnattributed: key.startsWith("unattributed") };
}

function findField(row, aliases, patternGroups = []) {
  for (const alias of aliases) {
    if (row[alias] !== undefined && String(row[alias]).trim() !== "") return row[alias];
  }
  const entries = Object.entries(row);
  for (const patterns of patternGroups) {
    const match = entries.find(([key, value]) => {
      const normalized = normalizeKey(key);
      return String(value || "").trim() !== "" && patterns.every((pattern) => normalized.includes(pattern));
    });
    if (match) return match[1];
  }
  return "";
}

function normalizeKey(key) {
  return String(key).toLowerCase().replace(/[^a-z0-9]+/g, "_");
}

function revenueAmount(row) {
  const amount = money(row, [
    "proceeds_usd",
    "proceeds",
    "net_revenue",
    "revenue",
    "revenue_usd",
    "price_in_usd",
    "price_in_purchased_currency",
    "price"
  ]);
  const eventType = String(findField(row, ["event_type", "Event Type", "type"], [["event", "type"]])).toLowerCase();
  if (amount > 0 && /refund|chargeback/.test(eventType)) return -amount;
  return amount;
}

function money(row, aliases) {
  return parseMoney(findField(row, aliases, aliases.map((alias) => [normalizeKey(alias)])));
}

function numberField(row, aliases) {
  return parseMoney(findField(row, aliases, aliases.map((alias) => [normalizeKey(alias)])));
}

function parseMoney(value) {
  if (value === undefined || value === null || value === "") return 0;
  let text = String(value).trim();
  const isNegative = /^\(.*\)$/.test(text) || text.startsWith("-");
  text = text.replace(/[(),$€£AEDBRLUSD\s]/gi, "").replace(/,/g, "");
  const parsed = Number(text);
  if (!Number.isFinite(parsed)) return 0;
  return isNegative ? -Math.abs(parsed) : parsed;
}

function rowDate(row) {
  const value = findField(row, [
    "date",
    "Date",
    "event_timestamp",
    "event_timestamp_ms",
    "purchased_at",
    "purchase_date",
    "transaction_date",
    "start_time"
  ], [["date"], ["timestamp"], ["purchased"]]);
  if (!value) return null;
  const text = String(value).trim();
  const date = /^\d{13}$/.test(text) ? new Date(Number(text)) : new Date(text);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString().slice(0, 10);
}

function totals(metrics) {
  const total = metrics.reduce((acc, item) => {
    acc.revenue += item.revenue;
    acc.spend += item.spend;
    acc.transactions += item.transactions;
    acc.installs += item.installs;
    acc.taps += item.taps;
    acc.impressions += item.impressions;
    return acc;
  }, { revenue: 0, spend: 0, transactions: 0, installs: 0, taps: 0, impressions: 0 });
  total.revenue = round2(total.revenue);
  total.spend = round2(total.spend);
  total.roas = total.spend > 0 ? round2(total.revenue / total.spend) : null;
  total.cpa = total.installs > 0 ? round2(total.spend / total.installs) : null;
  return total;
}

function recommendations(metrics, config) {
  return metrics
    .filter((item) => item.spend >= config.minSpendForAction || item.revenue >= config.minRevenueForScale)
    .map((item) => {
      if (item.spend >= config.minSpendForAction && item.revenue <= 0) {
        return recommendation("cut", item, "Spend is above the action threshold with no matched RevenueCat revenue.");
      }
      if (item.roas !== null && item.roas <= config.cutRoasThreshold && item.spend >= config.minSpendForAction) {
        return recommendation("reduce_or_pause", item, `ROAS ${item.roas} is below ${config.cutRoasThreshold}.`);
      }
      if (item.roas !== null && item.roas >= config.scaleRoasThreshold && item.revenue >= config.minRevenueForScale) {
        return recommendation("scale_carefully", item, `ROAS ${item.roas} is above ${config.scaleRoasThreshold}.`);
      }
      return recommendation("watch", item, "Enough data to monitor, but no strong bid action yet.");
    })
    .sort((a, b) => actionPriority(a.action) - actionPriority(b.action) || (b.metric.spend + b.metric.revenue) - (a.metric.spend + a.metric.revenue));
}

function recommendation(action, metric, reason) {
  return { action, reason, metric };
}

function actionPriority(action) {
  return { cut: 1, reduce_or_pause: 2, scale_carefully: 3, watch: 4 }[action] || 9;
}

function dataQuality(revenueRows, appleAdsRows, revenue, spend) {
  return {
    revenueRows: revenueRows.length,
    appleAdsRows: appleAdsRows.length,
    unattributedRevenueRows: revenue.unattributedRows,
    hasAppleAdsRows: appleAdsRows.length > 0,
    hasAppleAdsSpend: appleAdsRows.length > 0 && [...spend.byDimension.values()].some((item) => item.spend > 0)
  };
}

function renderReport(reportDate, revenueLoad, appleAdsLoad, analysis, config) {
  const topMetrics = analysis.metrics.slice(0, 20);
  const topRecommendations = analysis.recommendations.slice(0, 20);
  return [
    `# EzCar24 Revenue Feedback Loop - ${reportDate}`,
    "",
    `Generated at: ${analysis.generatedAt}`,
    `Lookback: ${analysis.lookbackDays} days`,
    "",
    "## Summary",
    "",
    table(
      ["Metric", "Value"],
      [
        ["Revenue rows", String(analysis.dataQuality.revenueRows)],
        ["Apple Ads rows", String(analysis.dataQuality.appleAdsRows)],
        ["RevenueCat objects seen", String(revenueLoad.objectsSeen)],
        ["RevenueCat objects processed", String(revenueLoad.objectsProcessed.length)],
        ["Total revenue", moneyText(analysis.totals.revenue)],
        ["Total spend", moneyText(analysis.totals.spend)],
        ["ROAS", analysis.totals.roas === null ? "n/a" : String(analysis.totals.roas)],
        ["Installs", String(analysis.totals.installs)]
      ]
    ),
    "",
    "## Top Recommendations",
    "",
    topRecommendations.length
      ? table(["Action", "Campaign", "Ad Group", "Keyword", "Spend", "Revenue", "ROAS", "Reason"], topRecommendations.map((item) => [
          item.action,
          item.metric.dimensions.campaign || item.metric.dimensions.campaignId || "unattributed",
          item.metric.dimensions.adGroup || "",
          item.metric.dimensions.keyword || "",
          moneyText(item.metric.spend),
          moneyText(item.metric.revenue),
          item.metric.roas === null ? "n/a" : String(item.metric.roas),
          item.reason
        ]))
      : "No bid actions yet. Add Apple Ads CSV spend data or wait for more RevenueCat exports.",
    "",
    "## Top Metrics",
    "",
    topMetrics.length
      ? table(["Campaign", "Ad Group", "Keyword", "Spend", "Revenue", "ROAS", "Transactions", "Installs"], topMetrics.map((item) => [
          item.dimensions.campaign || item.dimensions.campaignId || "unattributed",
          item.dimensions.adGroup || "",
          item.dimensions.keyword || "",
          moneyText(item.spend),
          moneyText(item.revenue),
          item.roas === null ? "n/a" : String(item.roas),
          String(item.transactions),
          String(item.installs)
        ]))
      : "No metrics yet.",
    "",
    "## Data Gaps",
    "",
    ...dataGapLines(analysis, appleAdsLoad, config),
    ""
  ].join("\n");
}

function dataGapLines(analysis, appleAdsLoad, config) {
  const lines = [];
  if (!analysis.dataQuality.hasAppleAdsRows) {
    lines.push(`- No Apple Ads spend rows found. Put CSV exports into \`${config.appleAdsCsvDir}\` or configure \`APPLE_ADS_R2_PREFIX\`.`);
  } else if (!analysis.dataQuality.hasAppleAdsSpend) {
    lines.push("- Apple Ads rows were loaded, but spend is still $0.00 in the current lookback window.");
  }
  if (analysis.dataQuality.unattributedRevenueRows > 0) {
    lines.push(`- ${analysis.dataQuality.unattributedRevenueRows} RevenueCat rows had no campaign/ad group/keyword attribution fields.`);
  }
  if (appleAdsLoad.sources.length > 0) {
    lines.push(`- Apple Ads sources loaded: ${appleAdsLoad.sources.map((source) => `${source.source} (${source.rows})`).join(", ")}`);
  }
  return lines.length ? lines : ["- No major data gaps detected."];
}

function table(headers, rows) {
  const escapedRows = rows.map((row) => row.map(markdownCell));
  return [
    `| ${headers.map(markdownCell).join(" | ")} |`,
    `| ${headers.map(() => "---").join(" | ")} |`,
    ...escapedRows.map((row) => `| ${row.join(" | ")} |`)
  ].join("\n");
}

function markdownCell(value) {
  return String(value ?? "").replace(/\|/g, "\\|").replace(/\n/g, " ");
}

function moneyText(value) {
  return `$${round2(value).toFixed(2)}`;
}

function round2(value) {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
}

function daysAgo(days) {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() - days);
  return date.toISOString().slice(0, 10);
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
