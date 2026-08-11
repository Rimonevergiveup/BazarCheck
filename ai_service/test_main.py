"""Tests for the Porokh price service.

These exercise the analysis logic directly (no network) plus the HTTP surface
via FastAPI's TestClient. Run with:  pytest ai_service/test_main.py -v
"""

from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from main import DealsResponse, PriceInsight, analyse_offers, app

NOW = datetime.now(timezone.utc)


def offer(price, *, in_stock=True, hours_old=1.0, seller="Shop"):
    return {
        "seller_name": seller,
        "price": price,
        "in_stock": in_stock,
        "collected_at": (NOW - timedelta(hours=hours_old)).isoformat(),
    }


def history_point(days_ago, min_price):
    return {
        "day": (NOW - timedelta(days=days_ago)).date().isoformat(),
        "min_price": min_price,
    }


# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------

def test_no_offers_says_so_instead_of_guessing():
    result = analyse_offers("p1", [], [])
    assert result.seller_count == 0
    assert result.cheapest is None
    assert result.average is None
    assert "No seller" in result.notes[0]


def test_basic_statistics_across_three_sellers():
    result = analyse_offers("p1", [offer(72), offer(78), offer(85.5)], [])
    assert result.seller_count == 3
    assert result.cheapest == 72.0
    assert result.dearest == 85.5
    assert result.median == 78.0
    assert result.average == pytest.approx(78.5, abs=0.01)


def test_spread_percent_is_relative_to_dearest():
    result = analyse_offers("p1", [offer(72), offer(90)], [])
    # (90 - 72) / 90 = 20%
    assert result.spread_percent == pytest.approx(20.0, abs=0.1)
    assert any("worth comparing" in n for n in result.notes)


def test_out_of_stock_offers_excluded_from_statistics():
    result = analyse_offers(
        "p1", [offer(72, in_stock=False), offer(85), offer(90)], []
    )
    assert result.seller_count == 2
    assert result.cheapest == 85.0  # not the out-of-stock 72


def test_single_seller_has_no_spread_and_says_so():
    result = analyse_offers("p1", [offer(72)], [])
    assert result.spread_percent is None
    assert any("Only one seller" in n for n in result.notes)


def test_identical_prices_note_no_difference():
    result = analyse_offers("p1", [offer(80), offer(80), offer(80)], [])
    assert result.spread_percent == 0.0
    assert any("about the same" in n for n in result.notes)


def test_stale_prices_are_counted_and_flagged():
    result = analyse_offers(
        "p1",
        [offer(72, hours_old=24 * 30), offer(78, hours_old=2)],
        [],
    )
    assert result.stale_seller_count == 1
    assert any("have not been checked" in n for n in result.notes)
    assert result.freshest_hours == pytest.approx(2.0, abs=0.2)


def test_falling_trend_detected():
    history = [history_point(d, p) for d, p in
               [(25, 100), (20, 98), (15, 95), (10, 88), (5, 85), (1, 84)]]
    result = analyse_offers("p1", [offer(84)], history)
    assert result.trend == "falling"
    assert result.trend_percent is not None and result.trend_percent < 0


def test_rising_trend_detected():
    history = [history_point(d, p) for d, p in
               [(25, 70), (20, 72), (15, 75), (10, 80), (5, 84), (1, 88)]]
    result = analyse_offers("p1", [offer(88)], history)
    assert result.trend == "rising"
    assert result.trend_percent is not None and result.trend_percent > 0


def test_stable_trend_detected():
    history = [history_point(d, 80) for d in (25, 20, 15, 10, 5, 1)]
    result = analyse_offers("p1", [offer(80)], history)
    assert result.trend == "stable"


def test_trend_unknown_without_enough_history():
    result = analyse_offers("p1", [offer(80)], [history_point(1, 80)])
    assert result.trend == "unknown"


def test_good_time_to_buy_at_recorded_low():
    history = [history_point(d, p) for d, p in
               [(25, 100), (20, 95), (15, 92), (10, 90), (5, 88), (1, 84)]]
    result = analyse_offers("p1", [offer(84)], history)
    assert result.is_good_time_to_buy is True


def test_not_good_time_when_well_above_low():
    history = [history_point(d, p) for d, p in
               [(25, 70), (20, 72), (15, 74), (10, 76), (5, 78), (1, 80)]]
    result = analyse_offers("p1", [offer(120)], history)
    assert result.is_good_time_to_buy is False


def test_never_invents_data():
    """Regression guard for the original service, which returned
    'Electronics / excellent camera / 95% confidence' for every product."""
    result = analyse_offers("some-tshirt-id", [offer(250)], [])
    blob = " ".join(result.notes).lower()
    for invented in ("camera", "battery", "electronics", "confidence"):
        assert invented not in blob
    assert result.cheapest == 250.0


def test_malformed_timestamp_does_not_crash():
    bad = {"price": 50, "in_stock": True, "collected_at": "not-a-date"}
    result = analyse_offers("p1", [bad], [])
    assert result.cheapest == 50.0
    assert result.freshest_hours is None


def test_missing_price_field_is_skipped():
    result = analyse_offers("p1", [{"in_stock": True}, offer(60)], [])
    assert result.cheapest == 60.0


# ---------------------------------------------------------------------------
# HTTP surface
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def test_health_is_public_and_leaks_nothing(client):
    res = client.get("/health")
    assert res.status_code == 200
    body = res.json()
    assert body["status"] == "healthy"
    assert set(body) == {"status", "supabase_configured"}
    assert isinstance(body["supabase_configured"], bool)


def test_root_reports_config_without_secrets(client):
    body = client.get("/").json()
    assert "key" not in str(body).lower()
    assert body["version"] == "2.0.0"


def test_insights_returns_503_when_supabase_unconfigured(client):
    # No SUPABASE_URL in the test environment, so this must fail loudly
    # rather than fabricating a response.
    res = client.get("/api/v1/products/abc/insights")
    assert res.status_code == 503


def test_rejects_oversized_product_id(client):
    res = client.get(f"/api/v1/products/{'x' * 100}/insights")
    assert res.status_code == 400


def test_deals_limit_is_validated(client):
    assert client.get("/api/v1/deals?limit=0").status_code == 422
    assert client.get("/api/v1/deals?limit=999").status_code == 422


def test_cors_is_not_wildcard_by_default():
    from main import CORS_ORIGINS
    assert "*" not in CORS_ORIGINS


def test_models_are_wired():
    assert PriceInsight(product_id="x").trend == "unknown"
    assert DealsResponse(deals=[], generated_at=NOW).deals == []
