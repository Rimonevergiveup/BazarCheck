"""BazarCheck Price Service.

Statistical analysis over the REAL price data in Supabase.

This replaces the previous service, which returned the same hardcoded dict for
every request ("category: Electronics, excellent camera, 95% confidence") no
matter what product was asked about — including clothing. Nothing here is
invented: every number is computed from rows in `prices` and `price_history`.

What it provides that Postgres does not already do in the RPC functions:
  * median and standard deviation across sellers (outlier-resistant)
  * trend detection from price history
  * "is this a good time to buy" against the recorded low
  * stale-price detection per seller

Endpoints
  GET /health                              liveness
  GET /api/v1/products/{id}/insights       per-product analysis
  GET /api/v1/deals                        products with the widest spread
"""

from __future__ import annotations

import logging
import os
import statistics
import time
from collections import defaultdict, deque
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Any, Deque, Dict, List, Optional

import httpx
from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Configuration - everything from the environment, nothing hardcoded
# ---------------------------------------------------------------------------

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")

# Comma-separated list. Defaults to localhost only - never "*" by default,
# because a permissive default is the kind of thing that ships to production.
CORS_ORIGINS = [
    o.strip()
    for o in os.getenv("CORS_ORIGINS", "http://localhost:3000,http://localhost:8080").split(",")
    if o.strip()
]

STALE_AFTER_DAYS = int(os.getenv("STALE_AFTER_DAYS", "7"))
RATE_LIMIT_PER_MINUTE = int(os.getenv("RATE_LIMIT_PER_MINUTE", "60"))
HISTORY_WINDOW_DAYS = int(os.getenv("HISTORY_WINDOW_DAYS", "30"))

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
log = logging.getLogger("bazarcheck.price_service")


# ---------------------------------------------------------------------------
# Supabase access
# ---------------------------------------------------------------------------

class SupabaseClient:
    """Thin PostgREST client.

    Uses the ANON key and therefore reads exactly what an anonymous app user can
    read, enforced by the same RLS policies. The service-role key is
    deliberately NOT used: this service only ever reads public price data, so
    holding an all-powerful key would be unnecessary risk.
    """

    def __init__(self, url: str, key: str) -> None:
        self.url = url
        self.key = key
        self._client: Optional[httpx.AsyncClient] = None

    @property
    def configured(self) -> bool:
        return bool(self.url and self.key)

    async def start(self) -> None:
        if self.configured:
            self._client = httpx.AsyncClient(
                base_url=self.url,
                headers={
                    "apikey": self.key,
                    "Authorization": f"Bearer {self.key}",
                    "Accept": "application/json",
                },
                timeout=httpx.Timeout(10.0),
            )

    async def stop(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    async def rpc(self, fn: str, payload: Dict[str, Any]) -> List[Dict[str, Any]]:
        if self._client is None:
            raise HTTPException(
                status_code=503,
                detail="Price service is not configured with Supabase credentials",
            )
        try:
            res = await self._client.post(f"/rest/v1/rpc/{fn}", json=payload)
        except httpx.RequestError as exc:
            log.warning("Supabase unreachable calling %s: %s", fn, exc)
            raise HTTPException(status_code=503, detail="Database unreachable") from exc

        if res.status_code != 200:
            log.warning("RPC %s failed: %s %s", fn, res.status_code, res.text[:200])
            raise HTTPException(status_code=502, detail="Database query failed")

        data = res.json()
        return data if isinstance(data, list) else []


supabase = SupabaseClient(SUPABASE_URL, SUPABASE_ANON_KEY)


@asynccontextmanager
async def lifespan(_: FastAPI):
    await supabase.start()
    if not supabase.configured:
        log.warning(
            "SUPABASE_URL / SUPABASE_ANON_KEY are unset. The service will start "
            "and report healthy, but insight endpoints will return 503. Set them "
            "in ai_service/.env"
        )
    yield
    await supabase.stop()


app = FastAPI(
    title="BazarCheck Price Service",
    description="Statistical price analysis over real Supabase data",
    version="2.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET"],
    allow_headers=["Authorization", "Content-Type"],
)


# ---------------------------------------------------------------------------
# Rate limiting - simple in-process sliding window
# ---------------------------------------------------------------------------

_hits: Dict[str, Deque[float]] = defaultdict(deque)


async def rate_limit(request: Request) -> None:
    """Cap requests per client IP per minute.

    In-process, so it resets on restart and is per-instance. That is enough to
    stop casual abuse of a public read API; put a real limiter at the edge
    (nginx / Cloudflare / API gateway) before scaling out.
    """
    client_ip = request.client.host if request.client else "unknown"
    now = time.monotonic()
    window = _hits[client_ip]

    while window and now - window[0] > 60:
        window.popleft()

    if len(window) >= RATE_LIMIT_PER_MINUTE:
        raise HTTPException(status_code=429, detail="Too many requests")

    window.append(now)

    if len(_hits) > 10_000:  # crude memory guard
        for ip in [k for k, v in _hits.items() if not v]:
            del _hits[ip]


# ---------------------------------------------------------------------------
# Response models
# ---------------------------------------------------------------------------

class PriceInsight(BaseModel):
    product_id: str
    seller_count: int = 0
    cheapest: Optional[float] = None
    average: Optional[float] = None
    median: Optional[float] = None
    dearest: Optional[float] = None
    spread_percent: Optional[float] = None
    trend: str = Field("unknown", description="falling | rising | stable | unknown")
    trend_percent: Optional[float] = None
    is_good_time_to_buy: bool = False
    stale_seller_count: int = 0
    freshest_hours: Optional[float] = None
    notes: List[str] = []


class DealItem(BaseModel):
    product_id: str
    name: str
    min_price: float
    max_price: float
    savings: float
    savings_percent: float
    seller_count: int


class DealsResponse(BaseModel):
    deals: List[DealItem]
    generated_at: datetime


# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------

def _parse_ts(value: Any) -> Optional[datetime]:
    if not value:
        return None
    text = str(value).replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def analyse_offers(product_id: str, offers: List[Dict[str, Any]],
                   history: List[Dict[str, Any]]) -> PriceInsight:
    """Turn raw rows into an honest summary.

    Every branch degrades gracefully: with one seller there is no spread, with
    no history there is no trend, and both cases say so rather than guessing.
    """
    now = datetime.now(timezone.utc)
    in_stock = [o for o in offers if o.get("in_stock")]
    prices = [float(o["price"]) for o in in_stock if o.get("price") is not None]

    insight = PriceInsight(product_id=product_id, seller_count=len(in_stock))
    notes: List[str] = []

    if not prices:
        insight.notes = ["No seller currently lists a price for this product."]
        return insight

    insight.cheapest = round(min(prices), 2)
    insight.dearest = round(max(prices), 2)
    insight.average = round(statistics.fmean(prices), 2)
    insight.median = round(statistics.median(prices), 2)

    if insight.dearest and insight.dearest > 0 and len(prices) > 1:
        spread = (insight.dearest - insight.cheapest) / insight.dearest * 100
        insight.spread_percent = round(spread, 1)
        if spread >= 20:
            notes.append(
                f"Prices vary by {spread:.0f}% between sellers — worth comparing."
            )
        elif spread <= 2:
            notes.append("All sellers charge about the same.")

    # --- freshness --------------------------------------------------------
    timestamps = [t for t in (_parse_ts(o.get("collected_at")) for o in offers) if t]
    if timestamps:
        newest = max(timestamps)
        insight.freshest_hours = round((now - newest).total_seconds() / 3600, 1)

    stale_cutoff = now - timedelta(days=STALE_AFTER_DAYS)
    insight.stale_seller_count = sum(1 for t in timestamps if t < stale_cutoff)
    if insight.stale_seller_count:
        notes.append(
            f"{insight.stale_seller_count} of {len(offers)} prices "
            f"have not been checked in over {STALE_AFTER_DAYS} days."
        )

    # --- trend from history ----------------------------------------------
    window_start = now - timedelta(days=HISTORY_WINDOW_DAYS)
    recent = [
        (ts, float(h["min_price"]))
        for h in history
        if (ts := _parse_ts(h.get("day"))) is not None
        and ts >= window_start
        and h.get("min_price") is not None
    ]

    if len(recent) >= 3:
        recent.sort(key=lambda pair: pair[0])
        values = [v for _, v in recent]
        midpoint = len(values) // 2
        earlier = statistics.fmean(values[:midpoint]) if midpoint else values[0]
        later = statistics.fmean(values[midpoint:])

        if earlier > 0:
            change = (later - earlier) / earlier * 100
            insight.trend_percent = round(change, 1)
            if change <= -3:
                insight.trend = "falling"
                notes.append(f"Prices are down about {abs(change):.0f}% recently.")
            elif change >= 3:
                insight.trend = "rising"
                notes.append(f"Prices are up about {change:.0f}% recently.")
            else:
                insight.trend = "stable"

        recorded_low = min(values)
        if recorded_low > 0 and insight.cheapest <= recorded_low * 1.02:
            insight.is_good_time_to_buy = True
            notes.append("The cheapest price is at or near its recorded low.")
    else:
        insight.trend = "unknown"

    if len(in_stock) == 1:
        notes.append("Only one seller — no comparison available yet.")

    insight.notes = notes
    return insight


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get("/")
async def root() -> Dict[str, Any]:
    return {
        "service": "BazarCheck Price Service",
        "version": "2.0.0",
        "supabase_configured": supabase.configured,
    }


@app.get("/health")
async def health() -> Dict[str, Any]:
    """Liveness. Reports configuration state without leaking any secret."""
    return {"status": "healthy", "supabase_configured": supabase.configured}


@app.get(
    "/api/v1/products/{product_id}/insights",
    response_model=PriceInsight,
    dependencies=[Depends(rate_limit)],
)
async def product_insights(product_id: str) -> PriceInsight:
    if not product_id or len(product_id) > 64:
        raise HTTPException(status_code=400, detail="Invalid product id")

    offers = await supabase.rpc("get_product_offers", {"p_product_id": product_id})
    history = await supabase.rpc(
        "get_price_history", {"p_product_id": product_id, "p_days": HISTORY_WINDOW_DAYS}
    )
    return analyse_offers(product_id, offers, history)


@app.get(
    "/api/v1/deals",
    response_model=DealsResponse,
    dependencies=[Depends(rate_limit)],
)
async def deals(limit: int = Query(10, ge=1, le=50)) -> DealsResponse:
    rows = await supabase.rpc("get_best_deals", {"p_limit": limit})
    return DealsResponse(
        deals=[
            DealItem(
                product_id=str(r.get("id", "")),
                name=str(r.get("name", "")),
                min_price=float(r.get("min_price") or 0),
                max_price=float(r.get("max_price") or 0),
                savings=float(r.get("savings") or 0),
                savings_percent=float(r.get("savings_pct") or 0),
                seller_count=int(r.get("seller_count") or 0),
            )
            for r in rows
        ],
        generated_at=datetime.now(timezone.utc),
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host=os.getenv("API_HOST", "0.0.0.0"),
        port=int(os.getenv("API_PORT", "8000")),
        reload=os.getenv("API_RELOAD", "false").lower() == "true",
    )
