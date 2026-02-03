import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

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

serve(async (req) => {
  try {
    const url = new URL(req.url)
    const token = url.searchParams.get("token")
    if (!token) {
      return new Response("Missing token", { status: 400 })
    }

    const { data: link, error: linkError } = await supabase
      .from("vehicle_share_links")
      .select("vehicle_id, dealer_id, contact_phone, contact_whatsapp, is_active")
      .eq("id", token)
      .single()

    if (linkError || !link || !link.is_active) {
      return new Response("Link not found", { status: 404 })
    }

    const { data: vehicle, error: vehicleError } = await supabase
      .from("crm_vehicles")
      .select("id, dealer_id, make, model, year, asking_price, sale_price, vin, report_url")
      .eq("id", link.vehicle_id)
      .eq("dealer_id", link.dealer_id)
      .single()

    if (vehicleError || !vehicle) {
      return new Response("Vehicle not found", { status: 404 })
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
      return new Response("Photos not available", { status: 500 })
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

    const title = [vehicle.year, vehicle.make, vehicle.model]
      .filter(Boolean)
      .join(" ")
      .trim() || "Vehicle"
    const price = vehicle.asking_price ?? vehicle.sale_price
    const priceText = price ? `Price: $${price}` : ""
    const dealerName = (org?.name ?? "").trim()
    const description = [
      priceText,
      vehicle.vin ? `VIN: ${vehicle.vin}` : "",
      dealerName ? `Dealer: ${dealerName}` : ""
    ]
      .filter(Boolean)
      .join(" • ")

    const ogImage = signedUrls[0] ?? ""

    const phone = (link.contact_phone ?? "").trim()
    const whatsapp = (link.contact_whatsapp ?? "").trim()
    const waDigits = whatsapp.replace(/[^\d]/g, "")

    const html = `
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <meta property="og:title" content="${htmlEscape(title)}" />
    <meta property="og:description" content="${htmlEscape(description)}" />
    ${ogImage ? `<meta property="og:image" content="${ogImage}" />` : ""}
    <meta name="twitter:card" content="summary_large_image" />
    <title>${htmlEscape(title)}</title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0; background: #f6f7fb; color: #111; }
      .container { max-width: 900px; margin: 0 auto; padding: 24px; }
      .card { background: #fff; border-radius: 16px; box-shadow: 0 6px 24px rgba(0,0,0,0.08); overflow: hidden; }
      .header { padding: 20px 24px; border-bottom: 1px solid #eee; display: flex; gap: 12px; align-items: baseline; flex-wrap: wrap; }
      .title { font-size: 28px; font-weight: 700; }
      .price { font-size: 22px; font-weight: 700; color: #0a7aff; margin-left: auto; }
      .meta { padding: 0 24px 16px; color: #666; font-size: 14px; }
      .gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 12px; padding: 0 24px 24px; }
      .gallery img { width: 100%; height: 180px; object-fit: cover; border-radius: 12px; }
      .actions { display: flex; gap: 12px; padding: 0 24px 24px; flex-wrap: wrap; }
      .btn { display: inline-flex; align-items: center; gap: 8px; padding: 12px 16px; border-radius: 10px; text-decoration: none; font-weight: 600; }
      .btn.phone { background: #111; color: #fff; }
      .btn.wa { background: #25D366; color: #fff; }
      .empty { padding: 24px; color: #777; }
    </style>
  </head>
  <body>
    <div class="container">
      <div class="card">
        <div class="header">
          <div class="title">${htmlEscape(title)}</div>
          ${price ? `<div class="price">$${price}</div>` : ""}
        </div>
        <div class="meta">${htmlEscape(description)}</div>
        ${signedUrls.length > 0 ? `
          <div class="gallery">
            ${signedUrls.map((src) => `<img src="${src}" alt="Vehicle photo" />`).join("")}
          </div>
        ` : `<div class="empty">No photos available.</div>`}
        ${dealerName ? `<div class="meta">Verified Dealer • ${htmlEscape(dealerName)}</div>` : ""}
        <div class="actions">
          ${phone ? `<a class="btn phone" href="tel:${phone}">Call ${htmlEscape(phone)}</a>` : ""}
          ${waDigits ? `<a class="btn wa" href="https://wa.me/${waDigits}">WhatsApp</a>` : ""}
        </div>
      </div>
    </div>
  </body>
</html>`

    return new Response(html, {
      headers: { "content-type": "text/html; charset=utf-8" }
    })
  } catch (_error) {
    return new Response("Server error", { status: 500 })
  }
})
