from __future__ import annotations
import base64
import hmac
import json
import os
import re
import sqlite3
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4
import httpx
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, File, Header, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env")
DB_PATH = os.getenv("DATABASE_PATH", str(ROOT / "glowly.db"))
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "")
ADMIN_KEY = os.getenv("ADMIN_KEY", "")
def db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn
@asynccontextmanager
async def lifespan(_: FastAPI):
    with db() as conn:
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS reviews (
                id TEXT PRIMARY KEY, user_id TEXT NOT NULL, product_name TEXT NOT NULL,
                rating INTEGER NOT NULL, skin_type TEXT NOT NULL, duration TEXT NOT NULL,
                reaction TEXT NOT NULL, notes TEXT NOT NULL, created_at TEXT NOT NULL,
                hidden INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS products (
                id TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT NOT NULL,
                price REAL, currency TEXT NOT NULL, image_url TEXT NOT NULL,
                product_url TEXT NOT NULL, skin_types TEXT NOT NULL, category TEXT NOT NULL,
                description TEXT NOT NULL, created_at TEXT NOT NULL
            );
    """)
    yield
app = FastAPI(title="Glowly API", version="1.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restrict to your app domain before production.
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
class ReviewIn(BaseModel):
    client_id: str = Field(min_length=1, max_length=100)
    user_id: str = Field(min_length=1, max_length=100)
    product_name: str = Field(min_length=1, max_length=180)
    rating: int = Field(ge=1, le=5)
    skin_type: str = Field(default="Not specified", max_length=80)
    duration: str = Field(default="", max_length=80)
    reaction: str = Field(default="", max_length=200)
    notes: str = Field(default="", max_length=2000)
class AdminLogin(BaseModel):
    password: str
class CuratedProduct(BaseModel):
    name: str = Field(min_length=2, max_length=180)
    brand: str = Field(default="", max_length=100)
    price: float | None = Field(default=None, ge=0)
    currency: str = Field(default="INR", max_length=8)
    image_url: str = Field(default="", max_length=1000)
    product_url: str = Field(default="", max_length=1000)
    skin_types: str = Field(default="All", max_length=200)
    category: str = Field(default="Skincare", max_length=100)
    description: str = Field(default="", max_length=1000)
def admin_guard(x_admin_key: str | None = Header(default=None)) -> None:
    if not ADMIN_KEY or not x_admin_key or not hmac.compare_digest(x_admin_key, ADMIN_KEY):
        raise HTTPException(status_code=401, detail="Admin access is not configured or the key is invalid.")
def clean_price(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None
def curated_rows() -> list[dict[str, Any]]:
    with db() as conn:
        rows = conn.execute("SELECT * FROM products ORDER BY created_at DESC").fetchall()
    return [{**dict(row), "source": "Glowly curated", "price_verified_at": row["created_at"]} for row in rows]
@app.get("/api/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "ai_configured": bool(os.getenv("GEMINI_API_KEY")),
        "price_api_configured": bool(os.getenv("SERPAPI_API_KEY")),
        "admin_configured": bool(ADMIN_PASSWORD and ADMIN_KEY),
    }
@app.get("/api/products")
async def search_products(
    q: str = Query(default="skincare", min_length=1, max_length=100),
    skin_type: str | None = None,
    category: str | None = None,
    max_price: float | None = Query(default=None, ge=0),
    sort: str = Query(default="relevance", pattern="^(relevance|price_asc|price_desc|rating)$"),
) -> dict[str, Any]:
    """Merge current Google Shopping offers and admin-curated items.
    Shopping prices are third-party listings and can change; the timestamp makes
    this explicit to the client. SerpApi needs a server-side subscription key.
    """
    items: list[dict[str, Any]] = []
    api_key = os.getenv("SERPAPI_API_KEY", "")
    if api_key:
        query_terms = [q.strip()]
        if category and category.casefold() != "all":
            query_terms.append(category)
        if skin_type and skin_type.casefold() != "all":
            query_terms.append(f"for {skin_type} skin")
        query_terms.append("skincare")
        params: dict[str, Any] = {
            "engine": "google_shopping", "q": " ".join(query_terms),
            "api_key": api_key, "gl": os.getenv("SERPAPI_GL", "in"),
            "hl": os.getenv("SERPAPI_HL", "en"),
        }
        if sort == "price_asc":
            params["sort_by"] = "1"
        elif sort == "price_desc":
            params["sort_by"] = "2"
        try:
            async with httpx.AsyncClient(timeout=25) as client:
                response = await client.get("https://serpapi.com/search.json", params=params)
                response.raise_for_status()
                body = response.json()
            fetched = datetime.now(timezone.utc).isoformat()
            for item in body.get("shopping_results", []):
                title = item.get("title", "Skincare product")
                price = clean_price(item.get("extracted_price"))
                items.append({
                    "id": str(item.get("product_id") or uuid4()),
                    "name": title,
                    "brand": item.get("source", "Online retailer"),
                    "price": price,
                    "price_label": item.get("price", "Price unavailable"),
                    "currency": os.getenv("SERPAPI_CURRENCY", "INR"),
                    "image_url": item.get("thumbnail", ""),
                    "product_url": item.get("product_link", ""),
                    "source": item.get("source", "Google Shopping"),
                    "rating": item.get("rating"),
                    "reviews": item.get("reviews"),
                    "category": category or "Skincare",
                    "skin_types": "Varies by product",
                    "description": item.get("snippet", ""),
                    "price_verified_at": fetched,
                })
        except httpx.HTTPError:
            raise HTTPException(status_code=502, detail="Live shopping search failed. Check the SerpApi configuration.") from None
    else:
        # Do not fabricate prices or pretend sample data is current.
        raise HTTPException(status_code=503, detail="Live price search is not configured. Add SERPAPI_API_KEY to backend/.env.")
    items.extend(curated_rows())
    query = q.casefold()
    if query:
        # SerpApi already applies q. Curated items need client-side matching.
        items = [item for item in items if item.get("source") != "Glowly curated" or query in item["name"].casefold() or query in item.get("category", "").casefold()]
    if skin_type and skin_type.casefold() != "all":
        items = [item for item in items if item.get("source") != "Glowly curated" or skin_type.casefold() in item.get("skin_types", "").casefold() or "all" in item.get("skin_types", "").casefold()]
    if category and category.casefold() != "all":
        items = [item for item in items if category.casefold() in item.get("category", "").casefold()]
    if max_price is not None:
        items = [item for item in items if item.get("price") is not None and item["price"] <= max_price]
    if sort in ("price_asc", "price_desc"):
        missing_price = float("inf") if sort == "price_asc" else float("-inf")
        items.sort(key=lambda item: item.get("price") if item.get("price") is not None else missing_price, reverse=(sort == "price_desc"))
    elif sort == "rating":
        items.sort(key=lambda item: (clean_price(item.get("rating")) or 0, clean_price(item.get("reviews")) or 0), reverse=True)
    return {"items": items, "count": len(items), "currency": os.getenv("SERPAPI_CURRENCY", "INR"), "updated_at": datetime.now(timezone.utc).isoformat()}
@app.post("/api/analyze-skin")
async def analyze_skin(image: UploadFile = File(...), goals: str = "") -> dict[str, Any]:
    """Call Gemini image understanding; results are informational, not medical advice."""
    api_key = os.getenv("GEMINI_API_KEY", "")
    if not api_key:
        raise HTTPException(status_code=503, detail="AI image review is not configured. Add GEMINI_API_KEY to backend/.env.")
    # Android image pickers can send a generic or missing MIME type.
    # Normalize it and infer the supported format from the filename if needed.
    content_type = (image.content_type or "").lower().split(";", 1)[0].strip()
    extension = Path(image.filename or "").suffix.lower()
    supported_types = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".webp": "image/webp",
    }
    if content_type not in {"image/jpeg", "image/png", "image/webp"}:
        content_type = supported_types.get(extension, "")
    if not content_type:
        raise HTTPException(
            status_code=415,
            detail="Please upload a JPG, PNG or WebP image.",
        )

    raw = await image.read(8 * 1024 * 1024 + 1)
    if len(raw) > 8 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Image must be 8 MB or smaller.")
    if not raw:
        raise HTTPException(status_code=400, detail="Image is empty.")

    # Validate actual file signatures, not only the extension or MIME header.
    is_jpeg = raw.startswith(b"\xff\xd8\xff")
    is_png = raw.startswith(b"\x89PNG\r\n\x1a\n")
    is_webp = len(raw) >= 12 and raw[:4] == b"RIFF" and raw[8:12] == b"WEBP"
    if is_jpeg:
        content_type = "image/jpeg"
    elif is_png:
        content_type = "image/png"
    elif is_webp:
        content_type = "image/webp"
    else:
        raise HTTPException(
            status_code=415,
            detail="The selected file is not a valid JPG, PNG or WebP image.",
        )
    prompt = f"""You are Glowly, a cautious cosmetic routine assistant. Review only visible, non-diagnostic skin appearance from this selfie. Do not identify a disease, diagnose, infer age/ethnicity/identity, or promise outcomes. Image lighting can mislead; explicitly say this is an approximate cosmetic observation, not medical advice. Avoid certainty. Return valid JSON only with keys: summary (short string), observations (array of short strings), routine_ideas (array of strings, conservative and patch-test advice), ingredients_to_consider (array of strings with gentle wording), product_searches (up to 3 neutral shopping search phrases for gentle, broadly available skincare categories; do not name a brand or claim a product will treat a condition), caution (string), confidence (low/medium). If the image is obscured or unclear, say so and give no specific ingredient suggestions or shopping phrases. User goals: {goals[:400]}"""
    payload = {
        "contents": [{"parts": [
            {"text": prompt},
            {"inline_data": {"mime_type": content_type, "data": base64.b64encode(raw).decode("ascii")}},
        ]}],
        "generationConfig": {"responseMimeType": "application/json", "temperature": 0.2},
        "safetySettings": [
            {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
            {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
        ],
    }
    model = os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
    try:
        async with httpx.AsyncClient(timeout=90) as client:
            response = await client.post(
                f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
                params={"key": api_key}, json=payload,
            )
            response.raise_for_status()
            body = response.json()
        text = body["candidates"][0]["content"]["parts"][0]["text"]
        result = json.loads(re.sub(r"^```(?:json)?|```$", "", text.strip(), flags=re.I).strip())
    except (httpx.HTTPError, KeyError, IndexError, json.JSONDecodeError):
        raise HTTPException(status_code=502, detail="AI review could not be completed. Check the Gemini configuration.") from None
    result["disclaimer"] = "AI skin observations are approximate, not a diagnosis. For a persistent or concerning skin problem, consult a qualified clinician."
    result["created_at"] = datetime.now(timezone.utc).isoformat()
    return result
@app.get("/api/reviews/{user_id}")
def list_user_reviews(user_id: str) -> list[dict[str, Any]]:
    with db() as conn:
        rows = conn.execute("SELECT * FROM reviews WHERE user_id=? ORDER BY created_at DESC", (user_id,)).fetchall()
    return [dict(row) for row in rows]
@app.post("/api/reviews")
def create_review(review: ReviewIn) -> dict[str, Any]:
    review_id = review.client_id
    created_at = datetime.now(timezone.utc).isoformat()
    with db() as conn:
        conn.execute(
            "INSERT INTO reviews (id,user_id,product_name,rating,skin_type,duration,reaction,notes,created_at) VALUES (?,?,?,?,?,?,?,?,?)",
            (review_id, review.user_id, review.product_name, review.rating, review.skin_type, review.duration, review.reaction, review.notes, created_at),
        )
    return {"id": review_id, **review.model_dump(), "created_at": created_at, "hidden": 0}
@app.delete("/api/reviews/{review_id}")
def delete_user_review(review_id: str, user_id: str = Query(min_length=1, max_length=100)) -> dict[str, bool]:
    with db() as conn:
        cursor = conn.execute("DELETE FROM reviews WHERE id=? AND user_id=?", (review_id, user_id))
    if cursor.rowcount == 0:
        raise HTTPException(status_code=404, detail="Review not found.")
    return {"ok": True}
@app.get("/api/admin")
def admin_page() -> FileResponse:
    return FileResponse(ROOT / "admin.html")
@app.post("/api/admin/login")
def admin_login(payload: AdminLogin) -> dict[str, str]:
    if not ADMIN_PASSWORD or not ADMIN_KEY or not hmac.compare_digest(payload.password, ADMIN_PASSWORD):
        raise HTTPException(status_code=401, detail="Invalid admin password or admin credentials are not configured.")
    return {"token": ADMIN_KEY}
@app.get("/api/admin/overview", dependencies=[Depends(admin_guard)])
def admin_overview() -> dict[str, Any]:
    with db() as conn:
        total_reviews = conn.execute("SELECT COUNT(*) FROM reviews").fetchone()[0]
        visible_reviews = conn.execute("SELECT COUNT(*) FROM reviews WHERE hidden=0").fetchone()[0]
        hidden_reviews = conn.execute("SELECT COUNT(*) FROM reviews WHERE hidden=1").fetchone()[0]
        products = conn.execute("SELECT COUNT(*) FROM products").fetchone()[0]
        recent = conn.execute("SELECT * FROM reviews ORDER BY created_at DESC LIMIT 50").fetchall()
        product_rows = conn.execute("SELECT * FROM products ORDER BY created_at DESC LIMIT 100").fetchall()
    return {
        "stats": {"total_reviews": total_reviews, "visible_reviews": visible_reviews, "hidden_reviews": hidden_reviews, "curated_products": products},
        "reviews": [dict(row) for row in recent],
        "products": [dict(row) for row in product_rows],
    }
@app.patch("/api/admin/reviews/{review_id}/visibility", dependencies=[Depends(admin_guard)])
def set_review_visibility(review_id: str, hidden: bool = Query(...)) -> dict[str, bool]:
    with db() as conn:
        cursor = conn.execute("UPDATE reviews SET hidden=? WHERE id=?", (int(hidden), review_id))
    if cursor.rowcount == 0:
        raise HTTPException(status_code=404, detail="Review not found.")
    return {"ok": True, "hidden": hidden}
@app.delete("/api/admin/reviews/{review_id}", dependencies=[Depends(admin_guard)])
def delete_review(review_id: str) -> dict[str, bool]:
    with db() as conn:
        cursor = conn.execute("DELETE FROM reviews WHERE id=?", (review_id,))
    if cursor.rowcount == 0:
        raise HTTPException(status_code=404, detail="Review not found.")
    return {"ok": True}
@app.post("/api/admin/products", dependencies=[Depends(admin_guard)])
def create_curated_product(product: CuratedProduct) -> dict[str, Any]:
    product_id = str(uuid4())
    created_at = datetime.now(timezone.utc).isoformat()
    with db() as conn:
        conn.execute(
            "INSERT INTO products (id,name,brand,price,currency,image_url,product_url,skin_types,category,description,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (product_id, product.name, product.brand, product.price, product.currency, product.image_url, product.product_url, product.skin_types, product.category, product.description, created_at),
        )
    return {"id": product_id, **product.model_dump(), "created_at": created_at}
@app.delete("/api/admin/products/{product_id}", dependencies=[Depends(admin_guard)])
def delete_curated_product(product_id: str) -> dict[str, bool]:
    with db() as conn:
        cursor = conn.execute("DELETE FROM products WHERE id=?", (product_id,))
    if cursor.rowcount == 0:
        raise HTTPException(status_code=404, detail="Product not found.")
    return {"ok": True}
