import { createClient } from "npm:@supabase/supabase-js@2"

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false }
})

const htmlEscape = (value: string) =>
  value.replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;")

const htmlHeaders = () => new Headers({
  "Content-Type": "text/html; charset=utf-8",
  "Cache-Control": "public, max-age=300",
  "X-Content-Type-Options": "nosniff"
})

const formatPrice = (value: unknown): string => {
  if (typeof value === "number" && Number.isFinite(value)) {
    return new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: "USD",
      maximumFractionDigits: 0
    }).format(value)
  }
  if (typeof value === "string") {
    const asNumber = Number(value)
    if (Number.isFinite(asNumber)) {
      return new Intl.NumberFormat("en-US", {
        style: "currency",
        currency: "USD",
        maximumFractionDigits: 0
      }).format(asNumber)
    }
  }
  return ""
}

const renderErrorPage = (title: string, message: string, status: number) => {
  const html = `
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${htmlEscape(title)}</title>
    <style>
      body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: linear-gradient(160deg, #f5f7fb 0%, #eef2f9 100%); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #172033; }
      .card { width: min(92vw, 520px); background: #fff; border: 1px solid #dbe3f0; border-radius: 16px; padding: 28px; box-shadow: 0 12px 32px rgba(18, 34, 66, 0.12); }
      h1 { margin: 0 0 10px; font-size: 24px; line-height: 1.2; }
      p { margin: 0; color: #5a6478; font-size: 16px; line-height: 1.5; }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>${htmlEscape(title)}</h1>
      <p>${htmlEscape(message)}</p>
    </div>
  </body>
</html>`

  return new Response(html, { status, headers: htmlHeaders() })
}

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url)
    const token = url.searchParams.get("token")
    if (!token) {
      return renderErrorPage("Invalid share link", "The token is missing from this link.", 400)
    }

    const { data: link, error: linkError } = await supabase
      .from("vehicle_share_links")
      .select("vehicle_id, dealer_id, contact_phone, contact_whatsapp, is_active")
      .eq("id", token)
      .single()

    if (linkError || !link || !link.is_active) {
      return renderErrorPage("Listing not found", "This listing link is no longer active.", 404)
    }

    const { data: vehicle, error: vehicleError } = await supabase
      .from("crm_vehicles")
      .select("id, dealer_id, make, model, year, asking_price, sale_price, vin, report_url")
      .eq("id", link.vehicle_id)
      .eq("dealer_id", link.dealer_id)
      .single()

    if (vehicleError || !vehicle) {
      return renderErrorPage("Vehicle not found", "This vehicle record is not available anymore.", 404)
    }

    const { data: org } = await supabase
      .from("organizations")
      .select("name")
      .eq("id", link.dealer_id)
      .single()

    const { data: photos, error: photosError } = await supabase
      .from("crm_vehicle_photos")
      .select("storage_path, sort_order, deleted_at")
      .eq("vehicle_id", link.vehicle_id)
      .eq("dealer_id", link.dealer_id)
      .order("sort_order", { ascending: true })

    if (photosError) {
      return renderErrorPage("Unable to load photos", "Please try this listing again in a few minutes.", 500)
    }

    const activePhotos = (photos ?? []).filter((p: { deleted_at: string | null }) => !p.deleted_at)
    const signedUrls: string[] = []

    for (const p of activePhotos) {
      const { data } = await supabase.storage
        .from("vehicle-images")
        .createSignedUrl(p.storage_path, 60 * 60 * 24 * 7)
      if (data?.signedUrl) {
        signedUrls.push(data.signedUrl)
      }
    }

    if (signedUrls.length === 0) {
      const vehicleId = String(link.vehicle_id).toLowerCase()
      const dealerId = String(link.dealer_id).toLowerCase()
      const coverPath = `${dealerId}/vehicles/${vehicleId}.jpg`
      const { data: coverData } = await supabase.storage
        .from("vehicle-images")
        .createSignedUrl(coverPath, 60 * 60 * 24 * 7)
      if (coverData?.signedUrl) {
        signedUrls.push(coverData.signedUrl)
      }
    }

    const title = [vehicle.year, vehicle.make, vehicle.model]
      .filter(Boolean)
      .join(" ")
      .trim() || "Vehicle"
    const pageUrl = `${url.origin}${url.pathname}?token=${encodeURIComponent(token)}`
    const price = vehicle.asking_price ?? vehicle.sale_price
    const formattedPrice = formatPrice(price)
    const dealerName = (org?.name ?? "").trim()
    const vin = (vehicle.vin ?? "").trim()
    const description = [
      formattedPrice ? `Price ${formattedPrice}` : "",
      vin ? `VIN ${vin}` : "",
      dealerName ? `Dealer ${dealerName}` : ""
    ]
      .filter(Boolean)
      .join(" | ")

    const ogImage = signedUrls[0] ?? ""

    const phone = (link.contact_phone ?? "").trim()
    const whatsapp = (link.contact_whatsapp ?? "").trim()
    const phoneDigits = phone.replace(/[^\d+]/g, "")
    const waDigits = whatsapp.replace(/[^\d]/g, "")
    const reportUrl = (vehicle.report_url ?? "").trim()

    if (reportUrl) {
      return Response.redirect(reportUrl, 302)
    }
    if (signedUrls.length > 0) {
      return Response.redirect(signedUrls[0], 302)
    }

    const html = `
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta property="og:type" content="website" />
    <meta property="og:url" content="${htmlEscape(pageUrl)}" />
    <meta property="og:title" content="${htmlEscape(title)}" />
    <meta property="og:description" content="${htmlEscape(description)}" />
    ${ogImage ? `<meta property="og:image" content="${htmlEscape(ogImage)}" />` : ""}
    <meta name="description" content="${htmlEscape(description)}" />
    <meta name="twitter:title" content="${htmlEscape(title)}" />
    <meta name="twitter:description" content="${htmlEscape(description)}" />
    ${ogImage ? `<meta name="twitter:image" content="${htmlEscape(ogImage)}" />` : ""}
    <meta name="twitter:card" content="summary_large_image" />
    <title>${htmlEscape(title)}</title>
    <style>
      * { box-sizing: border-box; }
      body { margin: 0; background: radial-gradient(circle at top right, #eff6ff 0%, #f8f9fc 45%, #eef2fb 100%); color: #111827; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
      .container { width: min(980px, 100% - 32px); margin: 24px auto 40px; }
      .card { background: #fff; border-radius: 20px; border: 1px solid #dce3f1; box-shadow: 0 20px 50px rgba(20, 37, 77, 0.16); overflow: hidden; }
      .hero { width: 100%; aspect-ratio: 16 / 9; background: linear-gradient(130deg, #dbe4f5, #edf2ff); }
      .hero img { width: 100%; height: 100%; object-fit: cover; display: block; }
      .content { padding: 24px; }
      .header { display: flex; gap: 16px; align-items: baseline; flex-wrap: wrap; }
      .title { margin: 0; font-size: clamp(28px, 3vw, 40px); line-height: 1.1; font-weight: 800; letter-spacing: -0.02em; }
      .price { margin-left: auto; font-size: clamp(24px, 2.4vw, 34px); font-weight: 800; color: #2563eb; }
      .meta { margin-top: 10px; color: #4b5563; font-size: 15px; }
      .actions { margin-top: 20px; display: flex; gap: 12px; flex-wrap: wrap; }
      .btn { display: inline-flex; align-items: center; justify-content: center; border-radius: 12px; padding: 12px 16px; text-decoration: none; font-weight: 700; min-width: 140px; }
      .btn.phone { background: #0f172a; color: #fff; }
      .btn.wa { background: #16a34a; color: #fff; }
      .gallery { margin-top: 20px; display: grid; grid-template-columns: repeat(auto-fill, minmax(210px, 1fr)); gap: 12px; }
      .gallery img { width: 100%; height: 170px; border-radius: 12px; object-fit: cover; display: block; border: 1px solid #e2e8f0; }
      .empty { margin-top: 20px; border: 1px dashed #cbd5e1; border-radius: 14px; padding: 18px; color: #64748b; }
      .dealer { margin-top: 14px; font-size: 14px; color: #334155; }
      @media (max-width: 680px) {
        .container { width: min(980px, 100% - 20px); margin: 14px auto 24px; }
        .content { padding: 16px; }
        .hero { aspect-ratio: 4 / 3; }
      }
    </style>
  </head>
  <body>
    <div class="container">
      <div class="card">
        <div class="hero">
          ${ogImage ? `<img src="${htmlEscape(ogImage)}" alt="Vehicle image" />` : ""}
        </div>
        <div class="content">
          <div class="header">
            <h1 class="title">${htmlEscape(title)}</h1>
            ${formattedPrice ? `<div class="price">${htmlEscape(formattedPrice)}</div>` : ""}
          </div>
          <div class="meta">${htmlEscape(description || "Vehicle listing")}</div>
          <div class="actions">
            ${phoneDigits ? `<a class="btn phone" href="tel:${htmlEscape(phoneDigits)}">Call ${htmlEscape(phone)}</a>` : ""}
            ${waDigits ? `<a class="btn wa" href="https://wa.me/${htmlEscape(waDigits)}" target="_blank" rel="noopener noreferrer">WhatsApp</a>` : ""}
          </div>
          ${signedUrls.length > 0 ? `
            <div class="gallery">
              ${signedUrls.map((src) => `<img src="${htmlEscape(src)}" alt="Vehicle photo" loading="lazy" />`).join("")}
            </div>
          ` : `<div class="empty">No photos available yet.</div>`}
          ${dealerName ? `<div class="dealer">Verified dealer: ${htmlEscape(dealerName)}</div>` : ""}
        </div>
      </div>
    </div>
  </body>
</html>`

    return new Response(html, {
      headers: htmlHeaders()
    })
  } catch (_error) {
    return renderErrorPage("Server error", "Unexpected error while loading this listing.", 500)
  }
})
