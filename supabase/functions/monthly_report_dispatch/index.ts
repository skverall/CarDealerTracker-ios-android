import { Buffer } from "node:buffer";
import { createClient } from "npm:@supabase/supabase-js@2";
import { Temporal } from "npm:@js-temporal/polyfill@0.5.0";
import {
  buildDeliverySummary,
  buildMonthlyReportSnapshot,
  buildMonthlyReportSubject,
  createServiceClient,
  formatMoney,
  generateMonthlyReportPdf,
  previousCalendarMonth,
  renderMonthlyReportEmail,
  resolveMonthlyReportRecipients,
  type MonthlyReportRecipient,
  type ReportMonth,
} from "./reporting.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-monthly-report-secret",
};

const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
const resendFromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "Ezcar24 <no-reply@ezcar24.com>";
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const admin = createServiceClient();

type DispatchMode = "scheduled" | "test" | "preview";

type ScheduledDispatchRow = {
  organization_id: string;
  organization_name: string;
  timezone_identifier: string;
  report_year: number;
  report_month: number;
  scheduled_for: string;
};

type ManualDispatchRequest = {
  mode?: DispatchMode;
  organizationId?: string;
  month?: {
    year: number;
    month: number;
  };
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await parseRequestBody(request);
    const mode = normalizeMode(body.mode);

    if (mode === "scheduled") {
      await ensureCronAccess(request);

      const nowIso = new Date().toISOString();
      const { data, error } = await admin.rpc("get_due_monthly_report_dispatches", {
        p_now: nowIso,
        p_window_minutes: 5,
      });

      if (error) {
        throw error;
      }

      const rows = (data ?? []) as ScheduledDispatchRow[];
      const results = [];

      for (const row of rows) {
        try {
          const result = await processEmailDelivery({
            organizationId: row.organization_id,
            organizationName: row.organization_name,
            timezone: row.timezone_identifier,
            reportMonth: {
              year: Number(row.report_year),
              month: Number(row.report_month),
            },
            deliveryType: "scheduled",
            deliveryKey: "scheduled",
            requestedBy: null,
          });
          results.push(result);
        } catch (error) {
          console.error("monthly report scheduled dispatch failed", {
            organizationId: row.organization_id,
            error: errorMessage(error),
          });
          results.push({
            organizationId: row.organization_id,
            status: "failed",
            error: errorMessage(error),
          });
        }
      }

      return jsonResponse({
        success: true,
        mode,
        dueCount: rows.length,
        processedCount: results.filter((result) => result.status === "sent").length,
        results,
      });
    }

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
      global: {
        headers: {
          Authorization: request.headers.get("Authorization") ?? "",
        },
      },
    });

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      return jsonResponse({ success: false, error: "Unauthorized" }, 401);
    }

    const organizationId = sanitizeUuid(body.organizationId);
    if (!organizationId) {
      return jsonResponse({ success: false, error: "organizationId is required" }, 400);
    }

    const { data: role, error: roleError } = await userClient.rpc("get_my_role", {
      _org_id: organizationId,
    });

    if (roleError) {
      throw roleError;
    }

    if (!isManagerRole(role)) {
      return jsonResponse({ success: false, error: "Forbidden" }, 403);
    }

    const organizationName = await loadOrganizationName(organizationId);
    const timezone = await loadOrganizationTimezone(organizationId);
    const reportMonth = resolveRequestedReportMonth(body.month, timezone);

    if (mode === "preview") {
      const recipients = await resolveMonthlyReportRecipients(admin, organizationId);
      const snapshot = await buildMonthlyReportSnapshot(
        admin,
        organizationId,
        organizationName,
        reportMonth,
        timezone,
      );

      return jsonResponse({
        success: true,
        mode,
        organizationId,
        timezone,
        organizationName,
        reportMonth,
        recipients: recipients.map((recipient) => ({
          email: recipient.email,
          role: recipient.role,
          name: recipient.name,
        })),
        summary: buildDeliverySummary(snapshot),
        preview: {
          title: snapshot.title,
          periodLabel: snapshot.periodLabel,
          generatedAt: snapshot.generatedAt,
          metrics: {
            totalRevenue: formatMoney(snapshot.executiveSummary.totalRevenue),
            realizedSalesProfit: formatMoney(snapshot.executiveSummary.realizedSalesProfit),
            monthlyExpenses: formatMoney(snapshot.executiveSummary.monthlyExpenses),
            netCashMovement: formatMoney(snapshot.executiveSummary.netCashMovement),
          },
        },
      });
    }

    const result = await processEmailDelivery({
      organizationId,
      organizationName,
      timezone,
      reportMonth,
      deliveryType: "test",
      deliveryKey: `test:${crypto.randomUUID()}`,
      requestedBy: user.id,
    });

    return jsonResponse({
      success: true,
      mode,
      ...result,
    });
  } catch (error) {
    console.error("monthly report dispatch error", error);
    return jsonResponse(
      {
        success: false,
        error: errorMessage(error),
      },
      500,
    );
  }
});

async function processEmailDelivery(args: {
  organizationId: string;
  organizationName: string;
  timezone: string;
  reportMonth: ReportMonth;
  deliveryType: "scheduled" | "test";
  deliveryKey: string;
  requestedBy: string | null;
}) {
  const { organizationId, organizationName, timezone, reportMonth, deliveryType, deliveryKey, requestedBy } = args;
  const { data: deliveryId, error: claimError } = await admin.rpc("claim_monthly_report_delivery", {
    p_organization_id: organizationId,
    p_report_year: reportMonth.year,
    p_report_month: reportMonth.month,
    p_delivery_type: deliveryType,
    p_delivery_key: deliveryKey,
    p_requested_by: requestedBy,
  });

  if (claimError) {
    throw claimError;
  }

  if (!deliveryId) {
    return {
      organizationId,
      organizationName,
      timezone,
      reportMonth,
      status: "skipped",
      reason: deliveryType === "scheduled" ? "already sent or currently processing" : "delivery could not be claimed",
    };
  }

  try {
    const recipients = await resolveMonthlyReportRecipients(admin, organizationId);
    if (recipients.length === 0) {
      throw new Error("No owner or admin email address is available for delivery.");
    }

    const snapshot = await buildMonthlyReportSnapshot(admin, organizationId, organizationName, reportMonth, timezone);
    const subject = buildMonthlyReportSubject(snapshot);
    const html = renderMonthlyReportEmail(snapshot, recipients);
    const pdf = await generateMonthlyReportPdf(snapshot);
    const filename = `monthly-report-${reportMonth.year}-${String(reportMonth.month).padStart(2, "0")}.pdf`;
    const messageId = await sendEmail({
      idempotencyKey: `monthly-report:${organizationId}:${reportMonth.year}-${String(reportMonth.month).padStart(2, "0")}:${deliveryKey}`,
      recipients,
      subject,
      html,
      pdf,
      filename,
    });

    const summary = buildDeliverySummary(snapshot);

    const { error: completeError } = await admin.rpc("mark_monthly_report_delivery_sent", {
      p_delivery_id: deliveryId,
      p_recipient_count: recipients.length,
      p_recipients: recipients.map((recipient) => ({
        email: recipient.email,
        role: recipient.role,
        name: recipient.name,
      })),
      p_subject: subject,
      p_report_title: snapshot.title,
      p_report_summary: summary,
      p_provider_message_id: messageId,
    });

    if (completeError) {
      throw completeError;
    }

    return {
      organizationId,
      organizationName,
      timezone,
      reportMonth,
      status: "sent",
      deliveryId,
      recipients: recipients.map((recipient) => recipient.email),
      subject,
      summary,
    };
  } catch (error) {
    const { error: failError } = await admin.rpc("mark_monthly_report_delivery_failed", {
      p_delivery_id: deliveryId,
      p_error_message: errorMessage(error),
    });

    if (failError) {
      console.error("mark_monthly_report_delivery_failed error", failError);
    }

    throw error;
  }
}

async function sendEmail(args: {
  idempotencyKey: string;
  recipients: MonthlyReportRecipient[];
  subject: string;
  html: string;
  pdf: Uint8Array;
  filename: string;
}) {
  if (!resendApiKey) {
    throw new Error("Missing RESEND_API_KEY");
  }

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
      "Idempotency-Key": args.idempotencyKey,
    },
    body: JSON.stringify({
      from: resendFromEmail,
      to: args.recipients.map((recipient) => recipient.email),
      subject: args.subject,
      html: args.html,
      attachments: [
        {
          filename: args.filename,
          content: Buffer.from(args.pdf).toString("base64"),
        },
      ],
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Resend error (${response.status}): ${errorText}`);
  }

  const payload = await response.json() as { id?: string };
  return payload.id ?? null;
}

async function loadOrganizationName(organizationId: string) {
  const { data, error } = await admin
    .from("organizations")
    .select("name")
    .eq("id", organizationId)
    .single();

  if (error) {
    throw error;
  }

  return data.name as string;
}

async function loadOrganizationTimezone(organizationId: string) {
  const { data, error } = await admin
    .from("monthly_report_preferences")
    .select("timezone_identifier")
    .eq("organization_id", organizationId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return normalizeTimezone(data?.timezone_identifier ?? "UTC");
}

function resolveRequestedReportMonth(month: ManualDispatchRequest["month"], timezone: string): ReportMonth {
  if (month && Number.isInteger(month.year) && Number.isInteger(month.month) && month.month >= 1 && month.month <= 12) {
    return {
      year: Number(month.year),
      month: Number(month.month),
    };
  }

  return previousCalendarMonth(Temporal.Now.instant().toString(), timezone);
}

async function ensureCronAccess(request: Request) {
  const secret = request.headers.get("x-monthly-report-secret")?.trim() ?? "";
  if (!secret) {
    throw new Error("Missing x-monthly-report-secret");
  }

  const { data, error } = await admin.rpc("is_valid_monthly_report_cron_secret", {
    p_secret: secret,
  });

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error("Invalid monthly report cron secret");
  }
}

function normalizeMode(value: string | undefined): DispatchMode {
  if (value === "test" || value === "preview") {
    return value;
  }
  return "scheduled";
}

function isManagerRole(value: unknown) {
  const role = String(value ?? "").trim().toLowerCase();
  return role === "owner" || role === "admin";
}

function sanitizeUuid(value: string | undefined) {
  const trimmed = (value ?? "").trim();
  return trimmed.length > 0 ? trimmed : "";
}

function normalizeTimezone(value: string | null | undefined) {
  const trimmed = (value ?? "").trim();
  return trimmed.length > 0 ? trimmed : "UTC";
}

async function parseRequestBody(request: Request): Promise<ManualDispatchRequest> {
  try {
    return await request.json() as ManualDispatchRequest;
  } catch {
    return {};
  }
}

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function errorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}
