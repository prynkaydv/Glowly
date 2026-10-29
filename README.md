# Glowly

Glowly is a Flutter mobile app with a FastAPI backend for skincare reviews, product search, routines, and a product diary.

## Free hosting note

The included `render.yaml` uses Render's free web service plan. Free services may sleep while idle, so requests can have a cold start. The local SQLite database is on ephemeral storage and can be lost when the service restarts or redeploys. This setup does not provide an always-awake backend or durable user data. No paid service has been created.

AI review and live price search require provider API keys. Set `GEMINI_API_KEY` and `SERPAPI_API_KEY` as server-side environment variables. Keep secrets out of Flutter and GitHub; `.gitignore` excludes `.env` files and database files.
