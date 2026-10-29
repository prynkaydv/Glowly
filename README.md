
## Cloud deployment (Render)

To keep the API working while your laptop is off, deploy it as an always-on cloud web service. `render.yaml` configures the Glowly API in Singapore and preserves SQLite data on a 1 GB disk.

1. Put this project in a private GitHub repository. Do not upload `backend/.env`; `.gitignore` excludes it.
2. In Render, create a Blueprint from that repository. Enter rotated `GEMINI_API_KEY` and `SERPAPI_API_KEY` values and private `ADMIN_PASSWORD` and `ADMIN_KEY` values when prompted.
3. After the service is live, visit `https://YOUR-SERVICE.onrender.com/api/health`. The `ok`, `ai_configured`, and `price_api_configured` fields should be true.
4. Build the phone app with the deployed service URL:

```powershell
flutter run -d GIEYUOBMXSPFCMJF --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com/api
```

The Render Blueprint uses its paid Starter plan and a 1 GB persistent disk. Current listed cost is about $6.25/month before taxes and other usage. Confirm the price shown in Render before creating the service.
