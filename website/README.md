# Car Dealer Tracker Website

Small static landing page for the Car Dealer Tracker app.

## Production setup

The landing page is deployed on Vercel:

- Project: `ezcar24-business`
- Temporary URL: `https://ezcar24-business.vercel.app/`
- Production URL: `https://business.ezcar24.com/`
- DNS provider: GoDaddy
- DNS record: `A business 216.198.79.1`
- Vercel certificate: `business.ezcar24.com`

The SEO files currently target:

```text
https://business.ezcar24.com/
```

Current indexing setup:

- `robots.txt` allows crawlers and points to `https://business.ezcar24.com/sitemap.xml`
- `sitemap.xml` lists the canonical homepage and important app images
- `index.html` includes canonical, robots meta, Open Graph, Twitter card, and JSON-LD structured data
- Vercel headers include `X-Robots-Tag: index, follow`

After deployment, submit `https://business.ezcar24.com/sitemap.xml` in Google Search Console and request indexing for `https://business.ezcar24.com/`.

Keep the main `ezcar24.com` and `www.ezcar24.com` records untouched. They are used by the existing public EzCar24 site.

## Run locally

```bash
cd website
python3 -m http.server 4173
```

Then open:

```text
http://localhost:4173
```

## Deploy free to Cloudflare Pages

Create a free Cloudflare account, then run:

```bash
cd website
NPM_CONFIG_CACHE=/Volumes/LexarDev/Developer/Caches/npm npx --yes wrangler@latest pages deploy . --project-name ezcar24-business
```

Cloudflare will return a free `https://ezcar24-business.pages.dev` URL. After DNS access is ready, attach `business.ezcar24.com` in Cloudflare Pages custom domains.

## Deploy to Vercel

Vercel is already used by `ezcar24.com`, but its free Hobby plan is limited to personal/non-commercial use. Use this only if the account plan is appropriate for a business landing page.

```bash
cd website
vercel deploy . --target preview --yes --project ezcar24-business
```

Vercel will return a preview URL. Use production deploy only when the domain is ready:

```bash
vercel deploy . --prod --yes --project ezcar24-business
```

If Vercel does not automatically issue the subdomain certificate after DNS propagation, issue it manually:

```bash
vercel certs issue business.ezcar24.com
```
