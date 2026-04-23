import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from "npm:pdf-lib@1.17.1";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { Temporal } from "npm:@js-temporal/polyfill@0.5.0";

export interface ReportMonth {
  year: number;
  month: number;
}

export interface MonthlyReportRecipient {
  email: string;
  role: string;
  name: string;
}

export interface MonthlyReportSnapshot {
  organizationName: string;
  timezone: string;
  reportMonth: ReportMonth;
  title: string;
  periodLabel: string;
  generatedAt: string;
  executiveSummary: ExecutiveSummary;
  vehicleSales: VehicleSaleRow[];
  partSales: PartSaleRow[];
  expenseActivity: ExpenseRow[];
  expenseCategories: ExpenseCategoryRow[];
  cashMovement: CashMovementSummary;
  inventorySnapshot: InventoryVehicleRow[];
  partsSnapshot: PartsInventoryRow[];
  topProfitableVehicles: VehicleSaleRow[];
  lossMakingVehicles: VehicleSaleRow[];
  topExpenseCategories: ExpenseCategoryRow[];
}

export interface ExecutiveSummary {
  totalRevenue: number;
  vehicleRevenue: number;
  partRevenue: number;
  realizedSalesProfit: number;
  vehicleProfit: number;
  partProfit: number;
  monthlyExpenses: number;
  netCashMovement: number;
  depositsTotal: number;
  withdrawalsTotal: number;
  vehicleSalesCount: number;
  partSalesCount: number;
  inventoryCount: number;
  inventoryCapital: number;
  partsUnitsInStock: number;
  partsInventoryCost: number;
}

export interface VehicleSaleRow {
  id: string;
  title: string;
  buyerName: string;
  soldAt: string;
  revenue: number;
  purchasePrice: number;
  vehicleExpenses: number;
  holdingCost: number;
  vatRefund: number;
  realizedProfit: number;
}

export interface PartSaleRow {
  id: string;
  soldAt: string;
  buyerName: string;
  summary: string;
  revenue: number;
  costOfGoodsSold: number;
  realizedProfit: number;
}

export interface ExpenseRow {
  id: string;
  title: string;
  categoryTitle: string;
  vehicleTitle?: string;
  date: string;
  amount: number;
}

export interface ExpenseCategoryRow {
  key: string;
  title: string;
  amount: number;
  count: number;
  share: number;
}

export interface CashMovementRow {
  id: string;
  title: string;
  note: string;
  transactionType: "deposit" | "withdrawal";
  date: string;
  signedAmount: number;
}

export interface CashMovementSummary {
  depositsTotal: number;
  withdrawalsTotal: number;
  netMovement: number;
  transactionCount: number;
  rows: CashMovementRow[];
}

export interface InventoryVehicleRow {
  id: string;
  title: string;
  status: string;
  purchaseDate?: string;
  purchasePrice: number;
  totalExpenses: number;
  costBasis: number;
}

export interface PartsInventoryRow {
  id: string;
  name: string;
  code: string;
  quantityOnHand: number;
  inventoryCost: number;
}

interface OrganizationHoldingCostSettings {
  isEnabled: boolean;
  annualRatePercent: number;
}

interface SaleRecord {
  id: string;
  vehicle_id: string | null;
  amount: string | number | null;
  date: string;
  buyer_name: string | null;
  vat_refund_amount: string | number | null;
}

interface VehicleRecord {
  id: string;
  make: string | null;
  model: string | null;
  purchase_price: string | number | null;
  purchase_date: string | null;
  status: string | null;
  sale_date: string | null;
}

interface ExpenseRecord {
  id: string;
  amount: string | number | null;
  date: string | null;
  expense_description: string | null;
  category: string | null;
  expense_type: string | null;
  vehicle_id: string | null;
}

interface FinancialAccountRecord {
  id: string;
  account_type: string | null;
}

interface AccountTransactionRecord {
  id: string;
  account_id: string | null;
  transaction_type: string | null;
  amount: string | number | null;
  date: string | null;
  note: string | null;
}

interface PartRecord {
  id: string;
  name: string | null;
  code: string | null;
}

interface PartBatchRecord {
  id: string;
  part_id: string;
  quantity_remaining: string | number | null;
  unit_cost: string | number | null;
}

interface PartSaleRecord {
  id: string;
  amount: string | number | null;
  date: string;
  buyer_name: string | null;
}

interface PartSaleLineItemRecord {
  id: string;
  sale_id: string;
  part_id: string;
  quantity: string | number | null;
  unit_cost: string | number | null;
}

type PdfChartItem = {
  label: string;
  value: number;
  color: ReturnType<typeof rgb>;
};

type PdfMetricCard = {
  label: string;
  value: string;
  tint: ReturnType<typeof rgb>;
};

const moneyFormatter = new Intl.NumberFormat("en-AE", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

const compactNumberFormatter = new Intl.NumberFormat("en-AE", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});

const pdfPalette = {
  ink: rgb(0.11, 0.12, 0.14),
  muted: rgb(0.45, 0.48, 0.53),
  border: rgb(0.86, 0.87, 0.89),
  panel: rgb(0.97, 0.97, 0.98),
  accent: rgb(0.78, 0.54, 0.21),
  accentSoft: rgb(0.95, 0.9, 0.81),
  positive: rgb(0.18, 0.58, 0.36),
  negative: rgb(0.78, 0.28, 0.24),
  warning: rgb(0.78, 0.54, 0.21),
  revenue: rgb(0.2, 0.42, 0.76),
  parts: rgb(0.12, 0.63, 0.64),
  expenses: rgb(0.76, 0.33, 0.28),
  cash: rgb(0.21, 0.58, 0.44),
};

export function createServiceClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });
}

export async function resolveMonthlyReportRecipients(
  admin: SupabaseClient,
  organizationId: string,
): Promise<MonthlyReportRecipient[]> {
  const { data: members, error: memberError } = await admin
    .from("dealer_team_members")
    .select("user_id, role, status")
    .eq("organization_id", organizationId)
    .in("role", ["owner", "admin"])
    .or("status.eq.active,status.is.null");

  if (memberError) {
    throw memberError;
  }

  const memberRows = (members ?? []) as Array<{ user_id: string; role: string; status: string | null }>;
  const userIds = memberRows.map((row) => row.user_id);

  if (userIds.length === 0) {
    return [];
  }

  const { data: profiles, error: profileError } = await admin
    .from("profiles")
    .select("user_id, email, full_name")
    .in("user_id", userIds);

  if (profileError) {
    throw profileError;
  }

  const profileByUserId = new Map<string, { email: string | null; full_name: string | null }>();
  for (const profile of (profiles ?? []) as Array<{ user_id: string; email: string | null; full_name: string | null }>) {
    profileByUserId.set(profile.user_id, profile);
  }

  const recipients: MonthlyReportRecipient[] = [];

  for (const member of memberRows) {
    const profile = profileByUserId.get(member.user_id);
    let email = sanitizeEmail(profile?.email ?? null);

    if (!email) {
      const { data: userData, error: userError } = await admin.auth.admin.getUserById(member.user_id);
      if (userError) {
        throw userError;
      }
      email = sanitizeEmail(userData.user?.email ?? null);
    }

    if (!email) {
      continue;
    }

    recipients.push({
      email,
      role: member.role,
      name: sanitizeName(profile?.full_name) || email,
    });
  }

  recipients.sort((left, right) => {
    if (left.role !== right.role) {
      return left.role === "owner" ? -1 : 1;
    }
    return left.email.localeCompare(right.email);
  });

  return recipients;
}

export async function buildMonthlyReportSnapshot(
  admin: SupabaseClient,
  organizationId: string,
  organizationName: string,
  reportMonth: ReportMonth,
  timezone: string,
): Promise<MonthlyReportSnapshot> {
  const monthRange = monthBounds(reportMonth, timezone);
  const reportTitle = reportMonthTitle(reportMonth, timezone);
  const generatedAt = Temporal.Now.instant().toString();

  const [
    holdingCostSettings,
    sales,
    vehicles,
    expenses,
    accounts,
    accountTransactions,
    parts,
    partBatches,
    partSales,
  ] = await Promise.all([
    loadHoldingCostSettings(admin, organizationId),
    loadSales(admin, organizationId, monthRange),
    loadVehicles(admin, organizationId),
    loadExpenses(admin, organizationId, monthRange),
    loadFinancialAccounts(admin, organizationId),
    loadAccountTransactions(admin, organizationId, monthRange),
    loadParts(admin, organizationId),
    loadPartBatches(admin, organizationId),
    loadPartSales(admin, organizationId, monthRange),
  ]);

  const soldVehicleIds = Array.from(new Set(
    sales
      .map((sale) => sale.vehicle_id)
      .filter((vehicleId): vehicleId is string => Boolean(vehicleId)),
  ));
  const vehicleSaleExpenses = soldVehicleIds.length > 0
    ? await loadVehicleSaleExpenses(admin, organizationId, soldVehicleIds, monthRange)
    : [];

  const partSaleIds = partSales.map((sale) => sale.id);
  const partSaleLineItems = partSaleIds.length > 0
    ? await loadPartSaleLineItems(admin, organizationId, partSaleIds)
    : [];

  const vehiclesById = new Map(vehicles.map((vehicle) => [vehicle.id, vehicle]));
  const accountsById = new Map(accounts.map((account) => [account.id, account]));
  const partsById = new Map(parts.map((part) => [part.id, part]));
  const partBatchesById = new Map(partBatches.map((batch) => [batch.id, batch]));

  const vehicleExpenseMap = new Map<string, ExpenseRecord[]>();
  for (const expense of vehicleSaleExpenses) {
    if (!expense.vehicle_id) {
      continue;
    }
    const rows = vehicleExpenseMap.get(expense.vehicle_id) ?? [];
    rows.push(expense);
    vehicleExpenseMap.set(expense.vehicle_id, rows);
  }

  const partLineItemsBySaleId = new Map<string, PartSaleLineItemRecord[]>();
  for (const item of partSaleLineItems) {
    const rows = partLineItemsBySaleId.get(item.sale_id) ?? [];
    rows.push(item);
    partLineItemsBySaleId.set(item.sale_id, rows);
  }

  const vehicleSales = sales
    .filter((sale) => {
      if (!sale.vehicle_id) {
        return false;
      }
      return vehiclesById.has(sale.vehicle_id);
    })
    .map((sale) => {
      const vehicle = sale.vehicle_id ? vehiclesById.get(sale.vehicle_id) ?? null : null;
      const saleDate = sale.date;
      const vehicleExpenses = relevantVehicleExpenses(vehicleExpenseMap.get(sale.vehicle_id ?? ""), saleDate, timezone)
        .reduce((total, expense) => total + numberValue(expense.amount), 0);
      const holdingCost = calculateHoldingCost({
        vehicle,
        expenses: relevantVehicleExpenses(vehicleExpenseMap.get(sale.vehicle_id ?? ""), saleDate, timezone),
        saleDate,
        settings: holdingCostSettings,
      });
      const revenue = numberValue(sale.amount);
      const purchasePrice = vehicle ? numberValue(vehicle.purchase_price) : 0;
      const vatRefund = numberValue(sale.vat_refund_amount);
      return {
        id: sale.id,
        title: vehicleTitle(vehicle),
        buyerName: sanitizeName(sale.buyer_name) || "Walk-in buyer",
        soldAt: saleDate,
        revenue,
        purchasePrice,
        vehicleExpenses,
        holdingCost,
        vatRefund,
        realizedProfit: revenue - purchasePrice - vehicleExpenses - holdingCost + vatRefund,
      } satisfies VehicleSaleRow;
    })
    .sort((left, right) => right.soldAt.localeCompare(left.soldAt));

  const expenseActivity = expenses
    .filter((expense) => isDateWithinMonth(expense.date, monthRange))
    .map((expense) => ({
      id: expense.id,
      title: sanitizeName(expense.expense_description) || "Expense",
      categoryTitle: expenseCategoryTitle(expense.category),
      vehicleTitle: expense.vehicle_id ? vehicleTitle(vehiclesById.get(expense.vehicle_id) ?? null) : undefined,
      date: expense.date ?? monthRange.startDate,
      amount: numberValue(expense.amount),
    } satisfies ExpenseRow))
    .sort((left, right) => compareDateish(right.date, left.date, monthRange.timezone));

  const expenseCategories = buildExpenseCategories(expenseActivity);

  const cashMovementRows = accountTransactions
    .map((transaction) => ({
      id: transaction.id,
      title: accountDisplayTitle(accountsById.get(transaction.account_id ?? "") ?? null),
      note: sanitizeName(transaction.note) || transactionTitle(transaction.transaction_type),
      transactionType: transaction.transaction_type === "withdrawal" ? "withdrawal" : "deposit",
      date: transaction.date ?? monthRange.startInstant.toString(),
      signedAmount: signedTransactionAmount(transaction),
    } satisfies CashMovementRow))
    .sort((left, right) => right.date.localeCompare(left.date));

  const cashMovement = buildCashMovementSummary(cashMovementRows);

  const inventorySnapshot = vehicles
    .filter((vehicle) => normalizeStatus(vehicle.status) !== "sold")
    .map((vehicle) => {
      const relatedExpenses = vehicleExpenseMap.get(vehicle.id) ?? [];
      const totalExpenses = relatedExpenses.reduce((total, expense) => total + numberValue(expense.amount), 0);
      const purchasePrice = numberValue(vehicle.purchase_price);
      return {
        id: vehicle.id,
        title: vehicleTitle(vehicle),
        status: sanitizeName(vehicle.status) || "owned",
        purchaseDate: vehicle.purchase_date ?? undefined,
        purchasePrice,
        totalExpenses,
        costBasis: purchasePrice + totalExpenses,
      } satisfies InventoryVehicleRow;
    })
    .sort((left, right) => left.title.localeCompare(right.title));

  const partsSnapshot = parts
    .map((part) => {
      const activeBatches = partBatches
        .filter((batch) => batch.part_id === part.id)
        .filter((batch) => numberValue(batch.quantity_remaining) > 0);
      const quantityOnHand = activeBatches.reduce((total, batch) => total + numberValue(batch.quantity_remaining), 0);
      const inventoryCost = activeBatches.reduce(
        (total, batch) => total + (numberValue(batch.quantity_remaining) * numberValue(batch.unit_cost)),
        0,
      );
      return {
        id: part.id,
        name: partDisplayName(part),
        code: sanitizeCode(part.code),
        quantityOnHand,
        inventoryCost,
      } satisfies PartsInventoryRow;
    })
    .filter((part) => part.quantityOnHand > 0)
    .sort((left, right) => left.name.localeCompare(right.name));

  const partSalesRows = partSales
    .map((sale) => {
      const lineItems = partLineItemsBySaleId.get(sale.id) ?? [];
      const uniquePartNames = Array.from(
        new Set(
          lineItems
            .map((item) => partDisplayName(partsById.get(item.part_id) ?? null))
            .filter((value) => value.length > 0),
        ),
      );
      const costOfGoodsSold = lineItems.reduce((total, item) => total + (numberValue(item.unit_cost) * numberValue(item.quantity)), 0);
      return {
        id: sale.id,
        soldAt: sale.date,
        buyerName: sanitizeName(sale.buyer_name) || "Walk-in buyer",
        summary: partSaleSummary(uniquePartNames),
        revenue: numberValue(sale.amount),
        costOfGoodsSold,
        realizedProfit: numberValue(sale.amount) - costOfGoodsSold,
      } satisfies PartSaleRow;
    })
    .sort((left, right) => right.soldAt.localeCompare(left.soldAt));

  const vehicleRevenue = vehicleSales.reduce((total, row) => total + row.revenue, 0);
  const partRevenue = partSalesRows.reduce((total, row) => total + row.revenue, 0);
  const vehicleProfit = vehicleSales.reduce((total, row) => total + row.realizedProfit, 0);
  const partProfit = partSalesRows.reduce((total, row) => total + row.realizedProfit, 0);
  const monthlyExpenses = expenseActivity.reduce((total, row) => total + row.amount, 0);
  const inventoryCapital = inventorySnapshot.reduce((total, row) => total + row.costBasis, 0);
  const partsUnitsInStock = partsSnapshot.reduce((total, row) => total + row.quantityOnHand, 0);
  const partsInventoryCost = partsSnapshot.reduce((total, row) => total + row.inventoryCost, 0);

  const sortedByProfit = [...vehicleSales].sort((left, right) => {
    if (left.realizedProfit !== right.realizedProfit) {
      return right.realizedProfit - left.realizedProfit;
    }
    return right.soldAt.localeCompare(left.soldAt);
  });

  return {
    organizationName,
    timezone,
    reportMonth,
    title: reportTitle,
    periodLabel: `${monthRange.startDate} - ${previousDate(monthRange.endDate)}`,
    generatedAt,
    executiveSummary: {
      totalRevenue: vehicleRevenue + partRevenue,
      vehicleRevenue,
      partRevenue,
      realizedSalesProfit: vehicleProfit + partProfit,
      vehicleProfit,
      partProfit,
      monthlyExpenses,
      netCashMovement: cashMovement.netMovement,
      depositsTotal: cashMovement.depositsTotal,
      withdrawalsTotal: cashMovement.withdrawalsTotal,
      vehicleSalesCount: vehicleSales.length,
      partSalesCount: partSalesRows.length,
      inventoryCount: inventorySnapshot.length,
      inventoryCapital,
      partsUnitsInStock,
      partsInventoryCost,
    },
    vehicleSales,
    partSales: partSalesRows,
    expenseActivity,
    expenseCategories,
    cashMovement,
    inventorySnapshot,
    partsSnapshot,
    topProfitableVehicles: sortedByProfit.filter((row) => row.realizedProfit > 0).slice(0, 5),
    lossMakingVehicles: [...sortedByProfit].reverse().filter((row) => row.realizedProfit < 0).slice(0, 5),
    topExpenseCategories: expenseCategories.slice(0, 5),
  };
}

export function buildDeliverySummary(snapshot: MonthlyReportSnapshot) {
  return {
    title: snapshot.title,
    totalRevenue: roundMoney(snapshot.executiveSummary.totalRevenue),
    realizedSalesProfit: roundMoney(snapshot.executiveSummary.realizedSalesProfit),
    monthlyExpenses: roundMoney(snapshot.executiveSummary.monthlyExpenses),
    netCashMovement: roundMoney(snapshot.executiveSummary.netCashMovement),
    vehicleSalesCount: snapshot.executiveSummary.vehicleSalesCount,
    partSalesCount: snapshot.executiveSummary.partSalesCount,
    inventoryCount: snapshot.executiveSummary.inventoryCount,
    generatedAt: snapshot.generatedAt,
  };
}

export function buildMonthlyReportSubject(snapshot: MonthlyReportSnapshot) {
  return `${snapshot.organizationName} monthly report · ${snapshot.title}`;
}

export function renderMonthlyReportEmail(snapshot: MonthlyReportSnapshot, recipients: MonthlyReportRecipient[]) {
  const health = reportHealthSignal(snapshot);
  const highlightCards = reportHighlightCards(snapshot);
  const revenueBars = [
    {
      label: "Vehicle revenue",
      value: snapshot.executiveSummary.vehicleRevenue,
      color: "#2F5EC2",
    },
    {
      label: "Part revenue",
      value: snapshot.executiveSummary.partRevenue,
      color: "#159E9E",
    },
    {
      label: "Monthly expenses",
      value: snapshot.executiveSummary.monthlyExpenses,
      color: "#C35748",
    },
    {
      label: "Net cash movement",
      value: Math.abs(snapshot.executiveSummary.netCashMovement),
      color: "#2D8B5B",
    },
  ];
  const expenseBars = snapshot.topExpenseCategories.length > 0
    ? snapshot.topExpenseCategories.map((category, index) => ({
      label: category.title,
      value: category.amount,
      color: expensePalette(index),
    }))
    : [];
  const recipientsLabel = recipients.map((recipient) => recipient.email).join(", ");
  const partsHighlights = snapshot.partsSnapshot.slice(0, 4);
  const vehicleHighlights = snapshot.vehicleSales.slice(0, 4);

  return `
  <html>
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <style>
        body { margin: 0; padding: 0; background: #f3efe8; color: #15181d; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
        .shell { width: 100%; padding: 28px 0; }
        .card { max-width: 760px; margin: 0 auto; background: #ffffff; border-radius: 22px; overflow: hidden; box-shadow: 0 18px 42px rgba(13, 17, 23, 0.08); }
        .hero { padding: 36px 36px 28px; background: linear-gradient(135deg, #161a1f 0%, #273445 55%, #8f6a29 100%); color: #f7f4ef; }
        .eyebrow { display: inline-block; padding: 6px 12px; border-radius: 999px; background: rgba(255,255,255,0.14); font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase; }
        .hero h1 { margin: 14px 0 10px; font-size: 34px; line-height: 1.1; }
        .hero p { margin: 0; font-size: 15px; line-height: 1.6; color: rgba(247,244,239,0.82); }
        .meta { margin-top: 20px; display: grid; gap: 8px; font-size: 13px; color: rgba(247,244,239,0.78); }
        .body { padding: 28px 28px 34px; }
        .signal { border-radius: 18px; padding: 18px 18px 16px; margin-bottom: 18px; }
        .signal.good { background: #edf7f1; border: 1px solid #d8ebdf; }
        .signal.warn { background: #f8f2e8; border: 1px solid #ebdcc4; }
        .signal.bad { background: #fbefed; border: 1px solid #efd5cf; }
        .signal-title { font-size: 18px; font-weight: 700; margin-bottom: 8px; }
        .signal-copy { font-size: 14px; color: #505862; line-height: 1.6; }
        .grid { width: 100%; border-collapse: separate; border-spacing: 12px; margin: 0 -12px 8px; }
        .metric { width: 50%; border-radius: 18px; background: #f8f7f4; border: 1px solid #ece7dd; padding: 16px; vertical-align: top; }
        .metric-label { font-size: 12px; text-transform: uppercase; letter-spacing: 0.08em; color: #7b7f85; margin-bottom: 8px; }
        .metric-value { font-size: 22px; font-weight: 700; color: #11161c; margin-bottom: 6px; }
        .metric-copy { font-size: 13px; line-height: 1.5; color: #57606b; }
        .section { margin-top: 22px; border-radius: 20px; border: 1px solid #ece7dd; padding: 20px; background: #fffdfa; }
        .section h2 { margin: 0 0 6px; font-size: 20px; }
        .section p { margin: 0 0 14px; font-size: 14px; line-height: 1.6; color: #5b626d; }
        .bar-row { margin-bottom: 12px; }
        .bar-head { display: flex; justify-content: space-between; gap: 12px; margin-bottom: 6px; font-size: 13px; color: #48505b; }
        .bar-track { width: 100%; height: 12px; background: #ece7dd; border-radius: 999px; overflow: hidden; }
        .bar-fill { height: 100%; border-radius: 999px; }
        .list { width: 100%; border-collapse: collapse; }
        .list td { padding: 10px 0; border-top: 1px solid #eee8df; font-size: 14px; vertical-align: top; }
        .list tr:first-child td { border-top: none; }
        .list .primary { font-weight: 600; color: #15181d; }
        .list .secondary { color: #5b626d; font-size: 13px; line-height: 1.5; }
        .value { text-align: right; white-space: nowrap; padding-left: 16px; font-weight: 600; }
        .pill { display: inline-block; padding: 5px 10px; border-radius: 999px; background: #f1ead8; color: #7c5a17; font-size: 12px; font-weight: 600; margin: 0 6px 6px 0; }
        .footer { padding: 0 28px 30px; font-size: 12px; line-height: 1.6; color: #727983; }
        @media only screen and (max-width: 640px) {
          .hero { padding: 28px 22px 24px; }
          .hero h1 { font-size: 28px; }
          .body { padding: 18px; }
          .grid { border-spacing: 0; margin: 0; }
          .metric { display: block; width: auto; margin-bottom: 12px; }
        }
      </style>
    </head>
    <body>
      <div class="shell">
        <div class="card">
          <div class="hero">
            <span class="eyebrow">Monthly report</span>
            <h1>${escapeHtml(snapshot.organizationName)}</h1>
            <p>${escapeHtml(snapshot.title)} · ${escapeHtml(snapshot.periodLabel)} · generated ${escapeHtml(formatDateTime(snapshot.generatedAt, snapshot.timezone))}</p>
            <div class="meta">
              <div>Recipients: ${escapeHtml(recipientsLabel || "No recipients resolved")}</div>
              <div>Report logic: realized sales profit, monthly expenses, and net cash movement</div>
            </div>
          </div>
          <div class="body">
            <div class="signal ${health.tone}">
              <div class="signal-title">${escapeHtml(health.title)}</div>
              <div class="signal-copy">${escapeHtml(health.copy)}</div>
            </div>
            <table class="grid" role="presentation">
              <tr>
                ${highlightCards.map((card) => `
                  <td class="metric">
                    <div class="metric-label">${escapeHtml(card.label)}</div>
                    <div class="metric-value">${escapeHtml(card.value)}</div>
                    <div class="metric-copy">${escapeHtml(card.copy)}</div>
                  </td>
                `).join("")}
              </tr>
            </table>
            <div class="section">
              <h2>Executive summary</h2>
              <p>Revenue and profitability stay separated on purpose so the monthly email remains accurate instead of collapsing everything into one synthetic net number.</p>
              ${metricPills(snapshot)}
            </div>
            <div class="section">
              <h2>Financial overview</h2>
              <p>A quick visual of the main monetary drivers for the month.</p>
              ${barChartHtml(revenueBars)}
            </div>
            <div class="section">
              <h2>Expense mix</h2>
              <p>The top expense categories for the period.</p>
              ${expenseBars.length > 0 ? barChartHtml(expenseBars) : "<p>No expenses recorded in this period.</p>"}
            </div>
            <div class="section">
              <h2>Recent vehicle sales</h2>
              <p>The first sales on the PDF are mirrored here so owners can read the headline moves directly from email.</p>
              ${vehicleHighlights.length > 0 ? listHtml(vehicleHighlights.map((row) => ({
                primary: `${formatDate(row.soldAt, snapshot.timezone)} · ${row.title}`,
                secondary: `${row.buyerName} · revenue ${formatMoney(row.revenue)} · profit ${formatMoney(row.realizedProfit)}`,
                value: formatMoney(row.realizedProfit),
                valueColor: row.realizedProfit >= 0 ? "#2D8B5B" : "#C35748",
              }))) : "<p>No vehicle sales recorded in this period.</p>"}
            </div>
            <div class="section">
              <h2>Parts snapshot</h2>
              <p>Current stock units and cost still parked in parts inventory.</p>
              ${partsHighlights.length > 0 ? listHtml(partsHighlights.map((row) => ({
                primary: row.code ? `${row.name} · ${row.code}` : row.name,
                secondary: `On hand ${formatQuantity(row.quantityOnHand)} · inventory cost ${formatMoney(row.inventoryCost)}`,
                value: formatQuantity(row.quantityOnHand),
                valueColor: "#15181D",
              }))) : "<p>No active parts inventory found.</p>"}
            </div>
          </div>
          <div class="footer">
            This email is generated automatically from the shared monthly report snapshot pipeline. The attached PDF contains the full section-by-section report for archive and forwarding.
          </div>
        </div>
      </div>
    </body>
  </html>
  `;
}

export async function generateMonthlyReportPdf(snapshot: MonthlyReportSnapshot) {
  const document = await PDFDocument.create();
  const regular = await document.embedFont(StandardFonts.Helvetica);
  const bold = await document.embedFont(StandardFonts.HelveticaBold);
  const renderer = new PdfRenderer(document, regular, bold);

  renderer.drawHero(snapshot);
  renderer.drawMetricGrid([
    { label: "Total revenue", value: formatMoney(snapshot.executiveSummary.totalRevenue), tint: pdfPalette.revenue },
    { label: "Realized sales profit", value: formatMoney(snapshot.executiveSummary.realizedSalesProfit), tint: pdfPalette.positive },
    { label: "Monthly expenses", value: formatMoney(snapshot.executiveSummary.monthlyExpenses), tint: pdfPalette.expenses },
    { label: "Net cash movement", value: formatMoney(snapshot.executiveSummary.netCashMovement), tint: snapshot.executiveSummary.netCashMovement >= 0 ? pdfPalette.cash : pdfPalette.negative },
    { label: "Inventory capital", value: formatMoney(snapshot.executiveSummary.inventoryCapital), tint: pdfPalette.warning },
    { label: "Parts inventory", value: formatMoney(snapshot.executiveSummary.partsInventoryCost), tint: pdfPalette.parts },
  ]);
  renderer.drawChart("Financial overview", [
    { label: "Vehicle revenue", value: snapshot.executiveSummary.vehicleRevenue, color: pdfPalette.revenue },
    { label: "Part revenue", value: snapshot.executiveSummary.partRevenue, color: pdfPalette.parts },
    { label: "Monthly expenses", value: snapshot.executiveSummary.monthlyExpenses, color: pdfPalette.expenses },
    { label: "Net cash movement", value: Math.abs(snapshot.executiveSummary.netCashMovement), color: snapshot.executiveSummary.netCashMovement >= 0 ? pdfPalette.cash : pdfPalette.negative },
  ]);
  renderer.drawChart(
    "Expense mix",
    snapshot.topExpenseCategories.map((row, index) => ({
      label: row.title,
      value: row.amount,
      color: pdfColorForExpenseIndex(index),
    })),
  );
  renderer.drawSection("Vehicle sales", snapshot.vehicleSales.map((row) =>
    `${formatDate(row.soldAt, snapshot.timezone)} · ${row.title} · ${row.buyerName} · revenue ${formatMoney(row.revenue)} · purchase ${formatMoney(row.purchasePrice)} · expenses ${formatMoney(row.vehicleExpenses)} · holding ${formatMoney(row.holdingCost)} · VAT ${formatMoney(row.vatRefund)} · profit ${formatMoney(row.realizedProfit)}`
  ), "No vehicle sales recorded in this period.");
  renderer.drawSection("Part sales", snapshot.partSales.map((row) =>
    `${formatDate(row.soldAt, snapshot.timezone)} · ${row.summary} · ${row.buyerName} · revenue ${formatMoney(row.revenue)} · COGS ${formatMoney(row.costOfGoodsSold)} · profit ${formatMoney(row.realizedProfit)}`
  ), "No part sales recorded in this period.");
  renderer.drawSection("Expense activity", snapshot.expenseActivity.map((row) =>
    `${formatDate(row.date, snapshot.timezone)} · ${row.title} · ${row.categoryTitle}${row.vehicleTitle ? ` · ${row.vehicleTitle}` : ""} · ${formatMoney(row.amount)}`
  ), "No expenses recorded in this period.");
  renderer.drawSection("Account transaction cash movement", [
    `Deposits total · ${formatMoney(snapshot.cashMovement.depositsTotal)}`,
    `Withdrawals total · ${formatMoney(snapshot.cashMovement.withdrawalsTotal)}`,
    `Net movement · ${formatMoney(snapshot.cashMovement.netMovement)}`,
    ...snapshot.cashMovement.rows.map((row) =>
      `${formatDateTime(row.date, snapshot.timezone)} · ${row.title} · ${row.note} · ${formatMoney(row.signedAmount)}`
    ),
  ], "No account transactions recorded in this period.");
  renderer.drawSection("Inventory snapshot", snapshot.inventorySnapshot.map((row) =>
    `${row.title} · ${row.status} · purchase ${formatMoney(row.purchasePrice)} · expenses ${formatMoney(row.totalExpenses)} · cost basis ${formatMoney(row.costBasis)}`
  ), "No vehicles currently in stock.");
  renderer.drawSection("Parts snapshot", snapshot.partsSnapshot.map((row) =>
    `${row.code ? `${row.name} · ${row.code}` : row.name} · on hand ${formatQuantity(row.quantityOnHand)} · inventory cost ${formatMoney(row.inventoryCost)}`
  ), "No parts inventory currently in stock.");
  renderer.drawSection("Top profitable vehicles", snapshot.topProfitableVehicles.map((row) =>
    `${row.title} · ${formatMoney(row.realizedProfit)}`
  ), "No profitable vehicle sales in this period.");
  renderer.drawSection("Loss-making vehicles", snapshot.lossMakingVehicles.map((row) =>
    `${row.title} · ${formatMoney(row.realizedProfit)}`
  ), "No loss-making vehicle sales in this period.");
  renderer.drawSection("Top expense categories", snapshot.topExpenseCategories.map((row) =>
    `${row.title} · ${formatMoney(row.amount)} · ${compactNumberFormatter.format(row.count)} entries`
  ), "No expense categories recorded in this period.");
  renderer.addPageNumbers();

  return await document.save();
}

function monthBounds(reportMonth: ReportMonth, timezone: string) {
  const start = Temporal.ZonedDateTime.from({
    timeZone: timezone,
    year: reportMonth.year,
    month: reportMonth.month,
    day: 1,
    hour: 0,
    minute: 0,
    second: 0,
    millisecond: 0,
  });
  const end = start.add({ months: 1 });
  return {
    start,
    end,
    timezone,
    startDate: start.toPlainDate().toString(),
    endDate: end.toPlainDate().toString(),
    startInstant: start.toInstant(),
    endInstant: end.toInstant(),
  };
}

function dateishInstant(value: string | null, timezone: string) {
  if (!value) {
    return null;
  }

  try {
    return Temporal.Instant.from(value);
  } catch (_error) {
  }

  try {
    return Temporal.PlainDate.from(value)
      .toZonedDateTime({
        timeZone: timezone,
        plainTime: Temporal.PlainTime.from("00:00"),
      })
      .toInstant();
  } catch (_error) {
  }

  return null;
}

function compareDateish(left: string | null, right: string | null, timezone: string) {
  const leftInstant = dateishInstant(left, timezone);
  const rightInstant = dateishInstant(right, timezone);

  if (!leftInstant && !rightInstant) {
    return 0;
  }
  if (!leftInstant) {
    return -1;
  }
  if (!rightInstant) {
    return 1;
  }

  return Temporal.Instant.compare(leftInstant, rightInstant);
}

export function previousCalendarMonth(referenceInstant: string, timezone: string) {
  const zoned = Temporal.Instant.from(referenceInstant).toZonedDateTimeISO(timezone);
  const currentMonthStart = Temporal.ZonedDateTime.from({
    timeZone: timezone,
    year: zoned.year,
    month: zoned.month,
    day: 1,
    hour: 0,
    minute: 0,
    second: 0,
    millisecond: 0,
  });
  const previous = currentMonthStart.subtract({ months: 1 });
  return {
    year: previous.year,
    month: previous.month,
  } satisfies ReportMonth;
}

function reportMonthTitle(reportMonth: ReportMonth, timezone: string) {
  const date = new Date(monthBounds(reportMonth, timezone).startInstant.epochMilliseconds);
  return new Intl.DateTimeFormat("en-US", {
    month: "long",
    year: "numeric",
    timeZone: timezone,
  }).format(date);
}

async function loadHoldingCostSettings(admin: SupabaseClient, organizationId: string): Promise<OrganizationHoldingCostSettings> {
  const { data, error } = await admin
    .from("organization_holding_cost_settings")
    .select("is_enabled, annual_rate_percent")
    .eq("organization_id", organizationId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return {
    isEnabled: Boolean(data?.is_enabled ?? false),
    annualRatePercent: numberValue(data?.annual_rate_percent ?? 15),
  };
}

async function loadSales(admin: SupabaseClient, organizationId: string, range: ReturnType<typeof monthBounds>) {
  const { data, error } = await admin
    .from("crm_sales")
    .select("id, vehicle_id, amount, date, buyer_name, vat_refund_amount")
    .eq("dealer_id", organizationId)
    .is("deleted_at", null)
    .gte("date", range.startDate)
    .lt("date", range.endDate);

  if (error) {
    throw error;
  }

  return (data ?? []) as SaleRecord[];
}

async function loadVehicles(admin: SupabaseClient, organizationId: string) {
  const { data, error } = await admin
    .from("crm_vehicles")
    .select("id, make, model, purchase_price, purchase_date, status, sale_date")
    .eq("dealer_id", organizationId)
    .is("deleted_at", null);

  if (error) {
    throw error;
  }

  return (data ?? []) as VehicleRecord[];
}

async function loadExpenses(admin: SupabaseClient, organizationId: string, range: ReturnType<typeof monthBounds>) {
  const { data, error } = await admin
    .from("crm_expenses")
    .select("id, amount, date, expense_description, category, expense_type, vehicle_id")
    .eq("dealer_id", organizationId)
    .is("deleted_at", null)
    .gte("date", range.startInstant.toString())
    .lt("date", range.endInstant.toString());

  if (error) {
    throw error;
  }

  return (data ?? []) as ExpenseRecord[];
}

async function loadVehicleSaleExpenses(
  admin: SupabaseClient,
  organizationId: string,
  vehicleIds: string[],
  range: ReturnType<typeof monthBounds>,
) {
  const { data, error } = await admin
    .from("crm_expenses")
    .select("id, amount, date, expense_description, category, expense_type, vehicle_id")
    .eq("dealer_id", organizationId)
    .is("deleted_at", null)
    .in("vehicle_id", vehicleIds)
    .lt("date", range.endInstant.toString());

  if (error) {
    throw error;
  }

  return (data ?? []) as ExpenseRecord[];
}

async function loadFinancialAccounts(admin: SupabaseClient, organizationId: string) {
  const { data, error } = await admin
    .from("crm_financial_accounts")
    .select("id, account_type")
    .eq("dealer_id", organizationId)
    .is("deleted_at", null);

  if (error) {
    throw error;
  }

  return (data ?? []) as FinancialAccountRecord[];
}

async function loadAccountTransactions(admin: SupabaseClient, organizationId: string, range: ReturnType<typeof monthBounds>) {
  const { data, error } = await admin
    .from("crm_account_transactions")
    .select("id, account_id, transaction_type, amount, date, note")
    .eq("dealer_id", organizationId)
    .is("deleted_at", null)
    .gte("date", range.startInstant.toString())
    .lt("date", range.endInstant.toString());

  if (error) {
    throw error;
  }

  return (data ?? []) as AccountTransactionRecord[];
}

async function loadParts(admin: SupabaseClient, organizationId: string) {
  const { data, error } = await admin
    .from("crm_parts")
    .select("id, name, code")
    .eq("dealer_id", organizationId)
    .is("deleted_at", null);

  if (error) {
    throw error;
  }

  return (data ?? []) as PartRecord[];
}

async function loadPartBatches(admin: SupabaseClient, organizationId: string) {
  const { data, error } = await admin
    .from("crm_part_batches")
    .select("id, part_id, quantity_remaining, unit_cost")
    .eq("dealer_id", organizationId)
    .is("deleted_at", null);

  if (error) {
    throw error;
  }

  return (data ?? []) as PartBatchRecord[];
}

async function loadPartSales(admin: SupabaseClient, organizationId: string, range: ReturnType<typeof monthBounds>) {
  const { data, error } = await admin
    .from("crm_part_sales")
    .select("id, amount, date, buyer_name")
    .eq("dealer_id", organizationId)
    .is("deleted_at", null)
    .gte("date", range.startDate)
    .lt("date", range.endDate);

  if (error) {
    throw error;
  }

  return (data ?? []) as PartSaleRecord[];
}

async function loadPartSaleLineItems(admin: SupabaseClient, organizationId: string, saleIds: string[]) {
  const { data, error } = await admin
    .from("crm_part_sale_line_items")
    .select("id, sale_id, part_id, quantity, unit_cost")
    .eq("dealer_id", organizationId)
    .is("deleted_at", null)
    .in("sale_id", saleIds);

  if (error) {
    throw error;
  }

  return (data ?? []) as PartSaleLineItemRecord[];
}

function relevantVehicleExpenses(
  expenses: ExpenseRecord[] | undefined,
  throughDate: string,
  timezone: string,
) {
  const throughInstant = dateishInstant(throughDate, timezone);
  if (!throughInstant) {
    return [];
  }

  return (expenses ?? []).filter((expense) => {
    const expenseInstant = dateishInstant(expense.date, timezone);
    if (!expenseInstant) {
      return false;
    }
    return Temporal.Instant.compare(expenseInstant, throughInstant) <= 0;
  });
}

function calculateHoldingCost(args: {
  vehicle: VehicleRecord | null;
  expenses: ExpenseRecord[];
  saleDate: string;
  settings: OrganizationHoldingCostSettings;
}) {
  if (!args.vehicle || !args.settings.isEnabled) {
    return 0;
  }

  const purchaseDate = args.vehicle.purchase_date ?? args.saleDate;
  const purchasePrice = numberValue(args.vehicle.purchase_price);
  const baseExpenses = args.expenses
    .filter((expense) => normalizeExpenseType(expense.expense_type) !== "holding_cost")
    .reduce((total, expense) => total + numberValue(expense.amount), 0);
  const purchase = Temporal.PlainDate.from(purchaseDate);
  const sale = Temporal.PlainDate.from(args.saleDate);
  const days = Math.max(0, purchase.until(sale, { largestUnit: "day" }).days);
  const dailyRate = args.settings.annualRatePercent / 365 / 100;
  return roundMoney(days * dailyRate * (purchasePrice + baseExpenses));
}

function buildExpenseCategories(expenses: ExpenseRow[]) {
  const total = expenses.reduce((sum, expense) => sum + expense.amount, 0);
  const grouped = new Map<string, ExpenseRow[]>();

  for (const expense of expenses) {
    const rows = grouped.get(expense.categoryTitle) ?? [];
    rows.push(expense);
    grouped.set(expense.categoryTitle, rows);
  }

  return Array.from(grouped.entries())
    .map(([title, rows]) => {
      const amount = rows.reduce((sum, row) => sum + row.amount, 0);
      return {
        key: title.toLowerCase(),
        title,
        amount,
        count: rows.length,
        share: total > 0 ? amount / total : 0,
      } satisfies ExpenseCategoryRow;
    })
    .sort((left, right) => {
      if (left.amount !== right.amount) {
        return right.amount - left.amount;
      }
      return left.title.localeCompare(right.title);
    });
}

function buildCashMovementSummary(rows: CashMovementRow[]): CashMovementSummary {
  const depositsTotal = rows
    .filter((row) => row.transactionType === "deposit")
    .reduce((sum, row) => sum + row.signedAmount, 0);
  const withdrawalsTotal = rows
    .filter((row) => row.transactionType === "withdrawal")
    .reduce((sum, row) => sum + Math.abs(row.signedAmount), 0);
  const netMovement = rows.reduce((sum, row) => sum + row.signedAmount, 0);

  return {
    depositsTotal: roundMoney(depositsTotal),
    withdrawalsTotal: roundMoney(withdrawalsTotal),
    netMovement: roundMoney(netMovement),
    transactionCount: rows.length,
    rows,
  };
}

function numberValue(value: string | number | null | undefined) {
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : 0;
  }
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function signedTransactionAmount(transaction: AccountTransactionRecord) {
  const amount = numberValue(transaction.amount);
  return transaction.transaction_type === "withdrawal" ? -amount : amount;
}

function accountDisplayTitle(account: FinancialAccountRecord | null) {
  const raw = sanitizeName(account?.account_type) || "Account";
  const separator = " - ";
  if (!raw.includes(separator)) {
    const normalized = raw.trim().toLowerCase();
    if (normalized === "cash") {
      return "Cash";
    }
    if (normalized === "bank") {
      return "Bank";
    }
    if (normalized === "card" || normalized === "credit card" || normalized === "creditcard") {
      return "Credit Card";
    }
    return raw;
  }
  const [prefix, suffix] = raw.split(separator, 2);
  const normalized = prefix.trim().toLowerCase();
  const kind = normalized === "cash"
    ? "Cash"
    : normalized === "bank"
    ? "Bank"
    : normalized === "card" || normalized === "credit card" || normalized === "creditcard"
    ? "Credit Card"
    : prefix.trim();
  return suffix?.trim() ? `${kind}${separator}${suffix.trim()}` : kind;
}

function transactionTitle(value: string | null) {
  return value === "withdrawal" ? "Withdrawal" : "Deposit";
}

function expenseCategoryTitle(value: string | null) {
  switch ((value ?? "").trim().toLowerCase()) {
    case "vehicle":
      return "Vehicle";
    case "personal":
      return "Personal";
    case "employee":
      return "Employee";
    default:
      return "Other";
  }
}

function normalizeExpenseType(value: string | null) {
  return (value ?? "").trim().toLowerCase();
}

function vehicleTitle(vehicle: VehicleRecord | null) {
  const parts = [vehicle?.make, vehicle?.model]
    .map((value) => sanitizeName(value))
    .filter((value) => value.length > 0);
  return parts.length > 0 ? parts.join(" ") : "Vehicle";
}

function partDisplayName(part: PartRecord | null) {
  return sanitizeName(part?.name) || "Part";
}

function partSaleSummary(partNames: string[]) {
  if (partNames.length === 0) {
    return "Parts sale";
  }
  if (partNames.length === 1) {
    return partNames[0];
  }
  return `${partNames[0]} + ${partNames.length - 1} more`;
}

function sanitizeName(value: string | null | undefined) {
  return (value ?? "").trim();
}

function sanitizeCode(value: string | null | undefined) {
  return (value ?? "").trim();
}

function sanitizeEmail(value: string | null | undefined) {
  const email = (value ?? "").trim().toLowerCase();
  return email.includes("@") ? email : "";
}

function normalizeStatus(value: string | null) {
  return (value ?? "").trim().toLowerCase();
}

function previousDate(nextDate: string) {
  return Temporal.PlainDate.from(nextDate).subtract({ days: 1 }).toString();
}

function isDateWithinMonth(date: string | null, range: ReturnType<typeof monthBounds>) {
  const instant = dateishInstant(date, range.timezone);
  if (!instant) {
    return false;
  }
  return Temporal.Instant.compare(instant, range.startInstant) >= 0 &&
    Temporal.Instant.compare(instant, range.endInstant) < 0;
}

function reportHealthSignal(snapshot: MonthlyReportSnapshot) {
  if (snapshot.executiveSummary.realizedSalesProfit > snapshot.executiveSummary.monthlyExpenses && snapshot.executiveSummary.netCashMovement >= 0) {
    return {
      tone: "good",
      title: "Healthy month",
      copy: "Realized profit covered expenses and cash stayed positive. This is the clearest sign that commercial activity translated into actual operating strength.",
    };
  }
  if (snapshot.executiveSummary.realizedSalesProfit <= 0 && snapshot.executiveSummary.monthlyExpenses > 0) {
    return {
      tone: "bad",
      title: "Pressure month",
      copy: "Profitability stayed weak while expenses still moved. Review slow stock, underpriced deals, and discretionary spend before the next cycle closes.",
    };
  }
  return {
    tone: "warn",
    title: "Mixed month",
    copy: "The month had movement, but either profits or cash conversion stayed uneven. The detailed sections below show where the pressure sits.",
  };
}

function reportHighlightCards(snapshot: MonthlyReportSnapshot) {
  const bestVehicle = snapshot.topProfitableVehicles[0];
  const heaviestExpense = snapshot.topExpenseCategories[0];
  const biggestInventory = [...snapshot.inventorySnapshot].sort((left, right) => right.costBasis - left.costBasis)[0];
  return [
    {
      label: "Sales closed",
      value: compactNumberFormatter.format(snapshot.executiveSummary.vehicleSalesCount + snapshot.executiveSummary.partSalesCount),
      copy: `${compactNumberFormatter.format(snapshot.executiveSummary.vehicleSalesCount)} vehicle deals and ${compactNumberFormatter.format(snapshot.executiveSummary.partSalesCount)} part sales landed in this report month.`,
    },
    {
      label: "Best close",
      value: bestVehicle ? formatMoney(bestVehicle.realizedProfit) : "No sale",
      copy: bestVehicle ? `${bestVehicle.title} was the strongest vehicle contribution this month.` : "No profitable vehicle sale was recorded in the period.",
    },
    {
      label: "Expense pressure",
      value: formatMoney(snapshot.executiveSummary.monthlyExpenses),
      copy: heaviestExpense ? `${heaviestExpense.title} drove the largest expense block at ${formatMoney(heaviestExpense.amount)}.` : "No expenses were posted in this period.",
    },
    {
      label: "Inventory exposure",
      value: formatMoney(snapshot.executiveSummary.inventoryCapital),
      copy: biggestInventory ? `${biggestInventory.title} is the heaviest single stock position at ${formatMoney(biggestInventory.costBasis)}.` : "There are no active vehicles in stock right now.",
    },
  ];
}

function metricPills(snapshot: MonthlyReportSnapshot) {
  const pills = [
    `Total revenue ${formatMoney(snapshot.executiveSummary.totalRevenue)}`,
    `Vehicle profit ${formatMoney(snapshot.executiveSummary.vehicleProfit)}`,
    `Part profit ${formatMoney(snapshot.executiveSummary.partProfit)}`,
    `Monthly expenses ${formatMoney(snapshot.executiveSummary.monthlyExpenses)}`,
    `Net cash movement ${formatMoney(snapshot.executiveSummary.netCashMovement)}`,
    `Inventory ${compactNumberFormatter.format(snapshot.executiveSummary.inventoryCount)} vehicles`,
    `Parts stock ${formatQuantity(snapshot.executiveSummary.partsUnitsInStock)} units`,
  ];
  return pills.map((pill) => `<span class="pill">${escapeHtml(pill)}</span>`).join("");
}

function barChartHtml(items: Array<{ label: string; value: number; color: string }>) {
  if (items.length === 0) {
    return "";
  }
  const max = Math.max(...items.map((item) => item.value), 1);
  return items.map((item) => {
    const width = Math.max(8, Math.min(100, (item.value / max) * 100));
    return `
      <div class="bar-row">
        <div class="bar-head">
          <span>${escapeHtml(item.label)}</span>
          <span>${escapeHtml(formatMoney(item.value))}</span>
        </div>
        <div class="bar-track">
          <div class="bar-fill" style="width:${width}%; background:${item.color};"></div>
        </div>
      </div>
    `;
  }).join("");
}

function listHtml(rows: Array<{ primary: string; secondary: string; value: string; valueColor: string }>) {
  return `
    <table class="list" role="presentation">
      ${rows.map((row) => `
        <tr>
          <td>
            <div class="primary">${escapeHtml(row.primary)}</div>
            <div class="secondary">${escapeHtml(row.secondary)}</div>
          </td>
          <td class="value" style="color:${row.valueColor};">${escapeHtml(row.value)}</td>
        </tr>
      `).join("")}
    </table>
  `;
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&#39;");
}

function expensePalette(index: number) {
  const colors = ["#C35748", "#2F5EC2", "#159E9E", "#8C6A1F", "#2D8B5B"];
  return colors[index % colors.length];
}

function pdfColorForExpenseIndex(index: number) {
  const colors = [pdfPalette.expenses, pdfPalette.revenue, pdfPalette.parts, pdfPalette.warning, pdfPalette.cash];
  return colors[index % colors.length];
}

export function formatMoney(value: number) {
  const rounded = roundMoney(value);
  return `AED ${moneyFormatter.format(rounded)}`;
}

export function formatQuantity(value: number) {
  const rounded = Math.abs(value % 1) < 0.0001 ? compactNumberFormatter.format(value) : value.toFixed(2);
  return rounded;
}

export function formatDate(value: string, timezone: string) {
  if (value.length === 10) {
    const plainDate = Temporal.PlainDate.from(value);
    const zoned = plainDate.toZonedDateTime({
      timeZone: timezone,
      plainTime: Temporal.PlainTime.from("12:00"),
    });
    return new Intl.DateTimeFormat("en-GB", {
      day: "numeric",
      month: "short",
      year: "numeric",
      timeZone: timezone,
    }).format(new Date(zoned.epochMilliseconds));
  }
  return new Intl.DateTimeFormat("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    timeZone: timezone,
  }).format(new Date(value.length === 10 ? `${value}T00:00:00Z` : value));
}

export function formatDateTime(value: string, timezone: string) {
  return new Intl.DateTimeFormat("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZone: timezone,
  }).format(new Date(value));
}

function roundMoney(value: number) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

class PdfRenderer {
  private readonly pageWidth = 595.28;
  private readonly pageHeight = 841.89;
  private readonly margin = 42;
  private readonly bottomMargin = 48;
  private readonly lineGap = 6;
  private page: PDFPage;
  private cursorY = 0;

  constructor(
    private readonly document: PDFDocument,
    private readonly regular: PDFFont,
    private readonly bold: PDFFont,
  ) {
    this.page = this.document.addPage([this.pageWidth, this.pageHeight]);
    this.cursorY = this.pageHeight - this.margin;
  }

  drawHero(snapshot: MonthlyReportSnapshot) {
    this.page.drawRectangle({
      x: 0,
      y: this.pageHeight - 170,
      width: this.pageWidth,
      height: 170,
      color: rgb(0.11, 0.13, 0.17),
    });
    this.page.drawRectangle({
      x: 0,
      y: this.pageHeight - 170,
      width: this.pageWidth,
      height: 170,
      color: rgb(0.15, 0.22, 0.31),
      opacity: 0.68,
    });
    this.cursorY = this.pageHeight - 48;
    this.drawText("MONTHLY REPORT", this.margin, this.cursorY, 11, this.bold, rgb(0.92, 0.87, 0.76));
    this.cursorY -= 24;
    this.drawText(snapshot.organizationName, this.margin, this.cursorY, 28, this.bold, rgb(0.98, 0.97, 0.94));
    this.cursorY -= 30;
    this.drawText(snapshot.title, this.margin, this.cursorY, 16, this.bold, rgb(0.98, 0.97, 0.94));
    this.cursorY -= 20;
    this.drawText(`${snapshot.periodLabel} · generated ${formatDateTime(snapshot.generatedAt, snapshot.timezone)}`, this.margin, this.cursorY, 11, this.regular, rgb(0.87, 0.88, 0.9));
    this.cursorY = this.pageHeight - 196;
  }

  drawMetricGrid(cards: PdfMetricCard[]) {
    const columnWidth = (this.pageWidth - (this.margin * 2) - 14) / 2;
    const cardHeight = 68;
    const rowCount = Math.ceil(cards.length / 2);
    this.ensureSpace((rowCount * (cardHeight + 14)) + 8);

    let index = 0;
    for (let row = 0; row < rowCount; row += 1) {
      for (let column = 0; column < 2; column += 1) {
        const card = cards[index];
        if (!card) {
          continue;
        }
        const x = this.margin + (column * (columnWidth + 14));
        const y = this.cursorY - cardHeight;
        this.page.drawRectangle({
          x,
          y,
          width: columnWidth,
          height: cardHeight,
          color: pdfPalette.panel,
          borderColor: pdfPalette.border,
          borderWidth: 1,
        });
        this.page.drawRectangle({
          x,
          y: y + cardHeight - 6,
          width: columnWidth,
          height: 6,
          color: card.tint,
        });
        this.drawText(card.label.toUpperCase(), x + 14, y + cardHeight - 20, 9, this.regular, pdfPalette.muted);
        this.drawText(card.value, x + 14, y + 26, 18, this.bold, pdfPalette.ink);
        index += 1;
      }
      this.cursorY -= cardHeight + 14;
    }
    this.cursorY -= 6;
  }

  drawChart(title: string, items: PdfChartItem[]) {
    if (items.length === 0) {
      return;
    }
    const blockHeight = 42 + (items.length * 28);
    this.ensureSpace(blockHeight);
    this.drawSectionHeader(title);
    const max = Math.max(...items.map((item) => item.value), 1);
    const labelWidth = 130;
    const valueWidth = 90;
    const trackWidth = this.pageWidth - (this.margin * 2) - labelWidth - valueWidth - 18;

    for (const item of items) {
      const y = this.cursorY;
      this.drawText(item.label, this.margin, y, 10, this.regular, pdfPalette.ink);
      this.drawText(formatMoney(item.value), this.pageWidth - this.margin - valueWidth, y, 10, this.bold, pdfPalette.ink);
      this.page.drawRectangle({
        x: this.margin + labelWidth,
        y: y - 2,
        width: trackWidth,
        height: 10,
        color: pdfPalette.border,
      });
      this.page.drawRectangle({
        x: this.margin + labelWidth,
        y: y - 2,
        width: Math.max(8, (item.value / max) * trackWidth),
        height: 10,
        color: item.color,
      });
      this.cursorY -= 24;
    }

    this.cursorY -= 12;
  }

  drawSection(title: string, rows: string[], emptyText: string) {
    this.drawSectionHeader(title);
    const content = rows.length > 0 ? rows : [emptyText];
    for (const row of content) {
      this.ensureSpace(28);
      this.drawWrappedText(row, this.margin, this.pageWidth - (this.margin * 2), 10, this.regular, pdfPalette.ink);
      this.cursorY -= 10;
    }
    this.cursorY -= 8;
  }

  addPageNumbers() {
    const pages = this.document.getPages();
    pages.forEach((page, index) => {
      const label = `Page ${index + 1}`;
      const width = this.regular.widthOfTextAtSize(label, 9);
      page.drawText(label, {
        x: this.pageWidth - this.margin - width,
        y: 18,
        size: 9,
        font: this.regular,
        color: pdfPalette.muted,
      });
    });
  }

  private drawSectionHeader(title: string) {
    this.ensureSpace(28);
    this.drawText(title, this.margin, this.cursorY, 16, this.bold, pdfPalette.ink);
    this.cursorY -= 18;
    this.page.drawLine({
      start: { x: this.margin, y: this.cursorY },
      end: { x: this.pageWidth - this.margin, y: this.cursorY },
      thickness: 1,
      color: pdfPalette.border,
    });
    this.cursorY -= 16;
  }

  private drawWrappedText(
    text: string,
    x: number,
    maxWidth: number,
    size: number,
    font: PDFFont,
    color: ReturnType<typeof rgb>,
  ) {
    const lines = wrapText(text, font, size, maxWidth);
    for (const line of lines) {
      this.ensureSpace(size + this.lineGap);
      this.drawText(line, x, this.cursorY, size, font, color);
      this.cursorY -= size + this.lineGap;
    }
  }

  private drawText(
    text: string,
    x: number,
    y: number,
    size: number,
    font: PDFFont,
    color: ReturnType<typeof rgb>,
  ) {
    this.page.drawText(text, {
      x,
      y,
      size,
      font,
      color,
    });
  }

  private ensureSpace(height: number) {
    if (this.cursorY - height < this.bottomMargin) {
      this.page = this.document.addPage([this.pageWidth, this.pageHeight]);
      this.cursorY = this.pageHeight - this.margin;
    }
  }
}

function wrapText(text: string, font: PDFFont, size: number, maxWidth: number) {
  const words = text.split(/\s+/).filter((word) => word.length > 0);
  if (words.length === 0) {
    return [""];
  }
  const lines: string[] = [];
  let currentLine = words[0];

  for (const word of words.slice(1)) {
    const candidate = `${currentLine} ${word}`;
    if (font.widthOfTextAtSize(candidate, size) <= maxWidth) {
      currentLine = candidate;
      continue;
    }
    lines.push(currentLine);
    currentLine = word;
  }

  lines.push(currentLine);
  return lines;
}
