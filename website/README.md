# Car Dealer Tracker Website

Small static landing page for the Car Dealer Tracker app.

## Run locally

```bash
cd website
python3 -m http.server 4173
```

Then open:

```text
http://localhost:4173
```

## Deploy preview to Vercel

```bash
cd website
npx --yes vercel@latest deploy . --target preview -y
```

Vercel will return a preview URL. Use production deploy only when the domain is ready:

```bash
npx --yes vercel@latest deploy . --prod -y
```
