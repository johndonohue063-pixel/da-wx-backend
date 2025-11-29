import asyncio
import time
import csv
import os
from typing import List, Dict, Tuple

import httpx
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime, timezone

# --- Data sources ---
CENPOP_FILE = "CenPop2020_Mean_CO.txt"
PEP_URL = "https://api.census.gov/data/2023/pep/population?get=NAME,POP,STATE,COUNTY&for=county:*"
OM_BASE = "https://api.open-meteo.com/v1/forecast"

# --- Official Census Regions (strict, by state abbreviation) ---
REGION_STATES = {
    "Northeast": ["CT", "ME", "MA", "NH", "RI", "VT", "NJ", "NY", "PA"],
    "Midwest": ["IL", "IN", "MI", "OH", "WI", "IA", "KS", "MN", "MO", "NE", "ND", "SD"],
    "South": [
        "DE", "FL", "GA", "MD", "NC", "SC", "VA", "DC", "WV",
        "AL", "KY", "MS", "TN", "AR", "LA", "OK", "TX",
    ],
    "West": ["AZ", "CO", "ID", "MT", "NV", "NM", "UT", "WY", "AK", "CA", "HI", "OR", "WA"],
}

# Parsed counties: (county_name, state_abbr, lat, lon, population)
COUNTIES: List[Tuple[str, str, float, float, int]] = []
STATE_IDX: Dict[str, List[int]] = {}
FIPS_IDX: Dict[str, int] = {}
CACHE: Dict[str, Tuple[float, List[Dict]]] = {}

STATE_NAME_TO_ABBR = {
    "Alabama": "AL",
    "Alaska": "AK",
    "Arizona": "AZ",
    "Arkansas": "AR",
    "California": "CA",
    "Colorado": "CO",
    "Connecticut": "CT",
    "Delaware": "DE",
    "District of Columbia": "DC",
    "Florida": "FL",
    "Georgia": "GA",
    "Hawaii": "HI",
    "Idaho": "ID",
    "Illinois": "IL",
    "Indiana": "IN",
    "Iowa": "IA",
    "Kansas": "KS",
    "Kentucky": "KY",
    "Louisiana": "LA",
    "Maine": "ME",
    "Maryland": "MD",
    "Massachusetts": "MA",
    "Michigan": "MI",
    "Minnesota": "MN",
    "Mississippi": "MS",
    "Missouri": "MO",
    "Montana": "MT",
    "Nebraska": "NE",
    "Nevada": "NV",
    "New Hampshire": "NH",
    "New Jersey": "NJ",
    "New Mexico": "NM",
    "New York": "NY",
    "North Carolina": "NC",
    "North Dakota": "ND",
    "Ohio": "OH",
    "Oklahoma": "OK",
    "Oregon": "OR",
    "Pennsylvania": "PA",
    "Rhode Island": "RI",
    "South Carolina": "SC",
    "South Dakota": "SD",
    "Tennessee": "TN",
    "Texas": "TX",
    "Utah": "UT",
    "Vermont": "VT",
    "Virginia": "VA",
    "Washington": "WA",
    "West Virginia": "WV",
    "Wisconsin": "WI",
    "Wyoming": "WY",
    "Puerto Rico": "PR",
}

app = FastAPI(title="Wx Live Regions (CenPop+PEP)")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"status": "ok"}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# -------------------------------------------------------------------
# Load counties + PEP overlay
# -------------------------------------------------------------------
async def load_counties_from_cenpop() -> None:
    """Load county name, state, lat, lon, base population from local CenPop file."""
    global COUNTIES, STATE_IDX, FIPS_IDX
    if COUNTIES:
        return

    base_dir = os.path.dirname(__file__)
    local_path = os.path.join(base_dir, CENPOP_FILE)
    if not os.path.exists(local_path):
        print(f"[WARN] CenPop file not found at {local_path}; no counties loaded.")
        COUNTIES = []
        STATE_IDX = {}
        FIPS_IDX = {}
        return

    tmp: List[Tuple[str, str, float, float, int]] = []
    STATE_IDX = {}
    FIPS_IDX = {}

    with open(local_path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                state_fp = row["STATEFP"]
                county_fp = row["COUNTYFP"]
                fips = f"{state_fp}{county_fp}"
                county_name = row["COUNAME"]
                state_full = row["STNAME"]
                state_abbr = STATE_NAME_TO_ABBR.get(state_full)
                if not state_abbr:
                    continue
                lat = float(row["LATITUDE"])
                lon = float(row["LONGITUDE"])
                pop = int(row["POPULATION"])
            except Exception:
                continue

            idx = len(tmp)
            tmp.append((county_name, state_abbr, lat, lon, pop))
            FIPS_IDX[fips] = idx
            STATE_IDX.setdefault(state_abbr, []).append(idx)

    COUNTIES = tmp
    print(f"[INFO] Loaded {len(COUNTIES)} counties from CenPop.")


async def load_populations_from_pep() -> None:
    """Overlay 2023 PEP populations onto existing COUNTIES using FIPS mapping."""
    global COUNTIES
    if not COUNTIES or not FIPS_IDX:
        print("[WARN] load_populations_from_pep called with no base counties; skipping PEP overlay.")
        return

    try:
        async with httpx.AsyncClient(timeout=30) as c:
            r = await c.get(PEP_URL)
            r.raise_for_status()
            data = r.json()
    except Exception as e:
        print(f"[WARN] PEP API load failed: {e}; keeping base populations.")
        return

    if not data or len(data) < 2:
        print("[WARN] PEP API returned no data; keeping base populations.")
        return

    header = data[0]

    def find_index(key: str) -> int:
        for i, h in enumerate(header):
            if h.lower() == key.lower():
                return i
        raise ValueError(f"'{key}' not found in headers: {header}")

    try:
        pop_i = find_index("pop")
        state_i = find_index("state")
        county_i = find_index("county")
    except ValueError as e:
        print(f"[WARN] Unexpected PEP header {header}: {e}; keeping base populations.")
        return

    updated = 0
    for row in data[1:]:
        try:
            state_fips = row[state_i]
            county_fips = row[county_i]
            fips = f"{state_fips}{county_fips}"
            if fips not in FIPS_IDX:
                continue
            pop_val = int(row[pop_i])
        except Exception:
            continue
        idx = FIPS_IDX[fips]
        c, st, la, lo, _old_pop = COUNTIES[idx]
        COUNTIES[idx] = (c, st, la, lo, pop_val)
        updated += 1

    print(f"[INFO] Updated populations from PEP for {updated} counties.")


# -------------------------------------------------------------------
# Live wind fetch (Open-Meteo)
# -------------------------------------------------------------------
async def live_wind(
    lat: float,
    lon: float,
    hours: int,
) -> Tuple[float, float, float, float, float, str]:
    """
    Best-effort live fetch; never raises.
    Returns: (expected_gust, expected_sustained, max_gust, max_sustained, base_probability, upstream_timestamp)
    """
    try:
        params = {
            "latitude": lat,
            "longitude": lon,
            "hourly": "windspeed_10m,windgusts_10m",
            "forecast_days": 3,
            "timezone": "UTC",
        }
        async with httpx.AsyncClient(timeout=20) as c:
            r = await c.get(OM_BASE, params=params)
            r.raise_for_status()
            j = r.json()
        g = j.get("hourly", {}).get("windgusts_10m", []) or []
        w = j.get("hourly", {}).get("windspeed_10m", []) or []
        t = j.get("hourly", {}).get("time", []) or []
        if not g or not w:
            return (0.0, 0.0, 0.0, 0.0, 0.0, now_iso())
        n = max(6, min(hours, len(g)))
        eg = sum(g[:n]) / n
        es = sum(w[:n]) / n
        mg = max(g)
        ms = max(w)
        base_p = max(0.0, min(0.75, mg / 100.0))
        stamp = t[0] if t else now_iso()
        return (eg, es, mg, ms, base_p, stamp)
    except Exception:
        return (0.0, 0.0, 0.0, 0.0, 0.0, now_iso())


# -------------------------------------------------------------------
# Outage prediction & crews (SPP-style, no clusters)
# -------------------------------------------------------------------
def predict_customers_out(pop: int, prob: float) -> int:
    if pop <= 0 or prob <= 0.0:
        return 0

    p = max(0.0, min(0.99, prob))
    raw_out = pop * p

    if pop >= 2_000_000:
        cap_mult = 0.85
    elif pop >= 1_000_000:
        cap_mult = 1.0
    else:
        cap_mult = 1.0

    if p < 0.20:
        prob_scale = p / 0.16 if p > 0 else 0.0
        if pop >= 500_000:
            tier_cap = pop * 0.01 * prob_scale
        elif pop >= 100_000:
            tier_cap = pop * 0.015 * prob_scale
        else:
            tier_cap = pop * 0.02 * prob_scale
    elif p < 0.30:
        if pop < 100_000:
            tier_cap = pop * 0.02
        elif pop < 500_000:
            tier_cap = pop * 0.015
        elif pop < 1_000_000:
            tier_cap = pop * 0.01
        else:
            tier_cap = pop * 0.008
    elif p < 0.45:
        if pop < 100_000:
            tier_cap = pop * 0.03
        elif pop < 500_000:
            tier_cap = pop * 0.022
        elif pop < 1_000_000:
            tier_cap = pop * 0.015
        else:
            tier_cap = pop * 0.01
    else:
        if pop < 100_000:
            tier_cap = pop * 0.04
        elif pop < 500_000:
            tier_cap = pop * 0.03
        elif pop < 1_000_000:
            tier_cap = pop * 0.02
        else:
            tier_cap = pop * 0.013

    tier_cap = tier_cap * cap_mult
    return int(min(raw_out, tier_cap))


def crews_from_predicted(predicted: int, pop: int) -> int:
    if predicted >= 100_000:
        return 10
    if predicted >= 50_000:
        return 7
    if predicted >= 25_000:
        return 4
    if predicted >= 10_000:
        return 2
    if predicted >= 1_000:
        return 1
    return 0


# -------------------------------------------------------------------
# Row builder with Threat Level 0 clamp
# -------------------------------------------------------------------
def mk_row(
    c: str,
    s: str,
    eg: float,
    es: float,
    mg: float,
    ms: float,
    base_p: float,
    pop: int,
    stamp: str,
) -> Dict:
    pop = int(pop or 0)

    if mg >= 65.0 or ms >= 45.0:
        severity = 4
    elif mg >= 50.0 or ms >= 35.0:
        severity = 3
    elif mg >= 35.0 or ms >= 25.0:
        severity = 2
    elif mg >= 25.0 or ms >= 18.0:
        severity = 1
    else:
        severity = 0

    prob = min(0.95, max(0.0, 0.5 + (mg / 100.0)))

    if severity == 0:
        prob = 0.0

    predicted = predict_customers_out(pop, prob)
    crews = crews_from_predicted(predicted, pop)
    confidence = int(min(100, max(0, round(prob * 100))))

    return {
        "county": c,
        "state": s,
        "expectedGust": round(eg, 1),
        "expectedSustained": round(es, 1),
        "maxGust": round(mg, 1),
        "maxSustained": round(ms, 1),
        "probability": round(prob, 2),
        "crews": crews,
        "severity": severity,
        "confidence": confidence,
        "population": pop,
        "predicted_customers_out": predicted,
        "generatedAt": now_iso(),
        "source": "open-meteo",
        "upstreamStamp": stamp,
    }


# -------------------------------------------------------------------
# Core compute + sampling
# -------------------------------------------------------------------
async def compute(indices: List[int], hours: int) -> List[Dict]:
    out: List[Dict] = []
    sem = asyncio.Semaphore(8)

    async def one(i: int) -> None:
        try:
            c, st, la, lo, pop = COUNTIES[i]
            async with sem:
                eg, es, mg, ms, base_p, stamp = await live_wind(la, lo, hours)
            out.append(mk_row(c, st, eg, es, mg, ms, base_p, pop, stamp))
        except Exception:
            pass

    await asyncio.gather(*[one(i) for i in indices])
    out.sort(
        key=lambda r: (
            r.get("severity", 0),
            r.get("predicted_customers_out", 0),
            r.get("maxGust", 0.0),
        ),
        reverse=True,
    )
    return out


def indices_for(mode: str, region: str, state: str, sample: int) -> List[int]:
    mode = (mode or "Nationwide").strip()

    # Normalize state: accept both full names ("Rhode Island") and abbreviations ("RI")
    state_abbr = ""
    if state:
        s = state.strip()
        if len(s) == 2:
            state_abbr = s.upper()
        else:
            state_abbr = STATE_NAME_TO_ABBR.get(s, "")

    if mode in ("Nationwide", "National"):
        idx = list(range(len(COUNTIES)))
    elif mode == "State" and state_abbr:
        idx = STATE_IDX.get(state_abbr, [])
    elif mode in ("Regional", "Region") and region:
        # Case-insensitive region lookup
        region_key = None
        if region:
            for name in REGION_STATES.keys():
                if name.lower() == region.lower():
                    region_key = name
                    break
        if not region_key:
            region_key = region
        allowed = set(REGION_STATES.get(region_key, []))
        base: List[int] = []
        for st in allowed:
            base.extend(STATE_IDX.get(st, []))
        idx = base
    else:
        idx = []

    if not idx:
        return []

    idx_sorted = sorted(idx, key=lambda i: COUNTIES[i][4], reverse=True)
    if sample > 0 and sample < len(idx_sorted):
        return idx_sorted[:sample]
    return idx_sorted


def cache_key(mode: str, region: str, state: str, hours: int, sample: int) -> str:
    return f"{mode}|{region}|{state}|{hours}|{sample}"


async def handle(
    mode: str,
    region: str,
    state: str,
    hours: int,
    sample: int,
    nocache: int,
) -> List[Dict]:
    await load_counties_from_cenpop()
    hours = max(6, min(72, hours or 24))
    sample = max(1, min(10, sample or 10))

    if not COUNTIES:
        return []

    idx = indices_for(mode, region, state, sample)
    if not idx:
        return []

    k = cache_key(mode or "Nationwide", region or "", state or "", hours, sample)
    now = time.time()
    if not nocache:
        hit = CACHE.get(k)
        if hit and (now - hit[0]) < 600:
            return hit[1]

    rows = await compute(idx, hours)
    CACHE[k] = (now, rows)
    return rows


# -------------------------------------------------------------------
# Routes
# -------------------------------------------------------------------
@app.get("/api/wx")
async def api_wx(
    req: Request,
    mode: str = "Nationwide",
    region: str = "",
    state: str = "",
    hours: int = 24,
    sample: int = 25,
    nocache: int = 0,
):
    rows = await handle(mode, region, state, hours, sample, nocache)

    # FINAL SAFETY CLAMP:
    # Threat Level 0 → no outages, no crews, prob 0.
    for r in rows:
        if r.get("severity", 0) == 0:
            r["probability"] = 0.0
            r["predicted_customers_out"] = 0
            r["crews"] = 0

    return rows


@app.get("/wx")
async def wx_alias(
    req: Request,
    mode: str = "Nationwide",
    region: str = "",
    state: str = "",
    hours: int = 24,
    sample: int = 25,
    nocache: int = 0,
):
    return await api_wx(req, mode, region, state, hours, sample, nocache)


@app.get("/{full_path:path}")
async def catch_all(
    req: Request,
    full_path: str,
    mode: str = "Nationwide",
    region: str = "",
    state: str = "",
    hours: int = 24,
    sample: int = 25,
    nocache: int = 0,
):
    return await api_wx(req, mode, region, state, hours, sample, nocache)


@app.on_event("startup")
async def init() -> None:
    await load_counties_from_cenpop()
    await load_populations_from_pep()
