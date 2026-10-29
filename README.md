# Glowly

Glowly is a Flutter mobile app with a FastAPI backend for skincare reviews, product search, routines, and a product diary.

## Current free API deployment

The Worker is deployed at `https://glowly-api.prynkaydv119.workers.dev`. The health endpoint is `https://glowly-api.prynkaydv119.workers.dev/api/health`.

Run the Android app against this cloud API from the project root:

```powershell
flutter run -d GIEYUOBMXSPFCMJF --dart-define=API_BASE_URL=https://glowly-api.prynkaydv119.workers.dev/api
```

## Free hosting option

`backend/worker.py` adapts the FastAPI backend for Cloudflare Workers, and D1 stores reviews and curated products persistently. Cloudflare Workers Free has no idle server to keep awake and does not bill for idle time; it includes 100,000 requests per day and 10 ms CPU time per request. Free D1 includes up to 5 GB storage, 5 million rows read per day, and 100,000 rows written per day. Exceeding a free quota can temporarily stop requests until it resets. These limits make this a small-project option, not unlimited hosting.

To prepare deployment:

1. Create a free Cloudflare account and install `uv`.
2. In `backend`, run `uv sync`, then `uv run pywrangler login`.
3. The deployed Worker is already bound to D1 database `glowly-db`. For a new Cloudflare account, create its D1 database with `uv run pywrangler d1 create glowly-db` and replace the database ID in `wrangler.toml`.
4. Apply the schema with `uv run pywrangler d1 migrations apply glowly-db --remote` (only needed when creating a new database or applying a new migration).
5. Revoke and replace any provider keys previously pasted into chat, then add the new credentials as secrets using `uv run pywrangler secret put GEMINI_API_KEY` and `uv run pywrangler secret put SERPAPI_API_KEY`. Add `ADMIN_PASSWORD` and `ADMIN_KEY` the same way. Never commit these values or put them in Flutter.
6. Deploy with `uv run pywrangler deploy`. The command prints the HTTPS Worker URL; use it in the Android build as `--dart-define=API_BASE_URL=https://YOUR-WORKER.workers.dev/api`.

The free SerpApi plan currently includes 250 searches per month, so live price search is limited. Gemini 3 Flash Preview currently has a free tier with rate limits; free-tier content may be used to improve Google's products. Do not send selfies until the app clearly explains that processing and obtains the user's informed consent.

`render.yaml` remains a free Render option for a simpler demo, but Render Free services sleep after 15 minutes idle and their local SQLite data is lost when they sleep or restart. Use Cloudflare Workers + D1 if you need a free service that stays reachable and stores reviews.
