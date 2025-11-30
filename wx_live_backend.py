"""
Divergent Wx Backend (NWS + CenPop + PEP)

- Uses US Census CenPop + PEP populations for county centroids and populations.
- Uses NWS / NOAA (api.weather.gov) hourly forecast for wind.
- Does NOT use Open-Meteo anywhere.
- Exposes /api/wx with a "State" mode (Nationwide / Regional kept for compatibility).
- Outage and crew numbers are intentionally conservative.

Key requirement from user:
  "If there's an error or no data, the function returns default values. = NEVER"

We implement that as:
  * The low–level NWS fetch (live_wind) NEVER returns fabricated "calm" values.
  * If NWS data cannot be obtained or parsed for a county, a NoDataError is raised.
  * The higher-level compute() catches NoDataError per-county and simply SKIPS that
    county from the result list instead of inventing zeros.

So: you either get real NWS-derived numbers, or that county is omitted.
"""

import asyncio
import csv
import os
import time
from datetime import datetime, timezone
from typing import Dict, List, Tuple

import httpx
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

# -------------------------------------------------------------------
# Data sources / constants
# -------------------------------------------------------------------

CENPOP_FILE = "CenPop2020_Mean_CO.txt"
PEP_URL = (
    "https://api.census.gov/data/2023/pep/population"
    "?get=NAME,POP,STATE,COUNTY&for=county:*"
)

# Small page-size constant so backend + frontend can stay in sync.
# Your Flutter code can use the same value (e.g., const int kPageSize = 15;).
PAGE_SIZE = 15

# Official Census Regions (for optional "Nationwide" / "Regional" modes)
REGION_STATES: Dict[str, List[str]] = {
    "Northeast": ["CT", "ME", "MA", "NH", "RI", "VT", "NJ", "NY", "PA"],
    "Midwest": ["IL", "IN", "MI", "OH", "WI", "IA", "KS", "MN", "MO", "NE", "ND", "SD"],
    "South": [
        "DE",
        "FL",
        "GA",
        "MD",
        "NC",
        "SC",
        "VA",
        "DC",
        "WV",
        "AL",
        "KY",
        "MS",
        "TN",
        "AR",
        "LA",
        "OK",
        "TX",
    ],
    "West": ["AZ", "CO", "ID", "MT", "NV", "NM", "UT", "WY", "AK", "CA", "HI", "OR", "WA"],
}

# Parsed counties: (county_name, state_abbr, lat, lon, population)
COUNTIES: List[Tuple[str, str, float, float, int]] = []
STATE_IDX: Dict[str, List[int]] = {}
FIPS_IDX: Dict[str, int] = {}
CACHE: Dict[str, Tuple[float, List[Dict]]] = {}


STATE_NAME_TO_ABBR: Dict[str, str] = {
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


class NoDataError(Exception):
    """Raised when NWS data is missing / unusable for a county."""


app = FastAPI(title="Divergent Wx Backend (NWS + CenPop + PEP)")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# -------------------------------------------------------------------
# Utilities
# -------------------------------------------------------------------
def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "ok", "ts": now_iso(), "page_size": str(PAGE_SIZE)}


# -------------------------------------------------------------------
# County + population loading
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
    """Overlay latest PEP populations onto existing COUNTIES using FIPS mapping."""
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
        raise ValueError(f"{key!r} not found in headers: {header}")

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
        c_name, st, la, lo, _old_pop = COUNTIES[idx]
        COUNTIES[idx] = (c_name, st, la, lo, pop_val)
        updated += 1

    print(f"[INFO] Updated populations from PEP for {updated} counties.")


# -------------------------------------------------------------------
# NWS helpers
# -------------------------------------------------------------------
NWS_USER_AGENT = "DivergentWx/1.0 (support@divergentalliance.com)"


def _parse_mph(value: str) -> float:
    """
    Parse strings like:
      "20 mph"
      "15 to 25 mph"
    into a single mph value (using the first integer we find).

    No regex, just character scanning.
    """
    if not value:
        raise NoDataError("empty speed string")

    # Split on spaces, then scan characters for digits.
    parts = value.split(" ")
    for part in parts:
        digits = ""
        for ch in part:
            if "0" <= ch <= "9":
                digits += ch
            elif digits:
                # We already collected some digits; stop at first non-digit.
                break
        if digits:
            try:
                return float(digits)
            except Exception:
                pass

    raise NoDataError(f"could not parse mph from {value!r}")


async def live_wind(lat: float, lon: float, hours: int) -> Tuple[float, float, float, float, float, str]:
    """
    Fetch hourly wind for a lat/lon from NWS.

    Returns:
      (expected_gust, expected_sustained, max_gust, max_sustained, probability, upstream_timestamp)

    IMPORTANT: this function NEVER fabricates calm conditions.
    - On any network / parsing / data error, a NoDataError is raised.
    - The caller (compute) will catch that and skip this county.
    """
    hours = max(1, min(72, int(hours) if hours else 24))

    headers = {
        "User-Agent": NWS_USER_AGENT,
        "Accept": "application/geo+json",
    }

    try:
        async with httpx.AsyncClient(timeout=20) as client:
            # 1) Resolve grid point for this lat/lon
            points_url = f"https://api.weather.gov/points/{lat},{lon}"
            r_points = await client.get(points_url, headers=headers)
            r_points.raise_for_status()
            j_points = r_points.json()
            props = j_points.get("properties") or {}
            hourly_url = props.get("forecastHourly")
            if not hourly_url:
                raise NoDataError("NWS points missing forecastHourly")

            # 2) Fetch hourly forecast
            r_hourly = await client.get(hourly_url, headers=headers)
            r_hourly.raise_for_status()
            j_hourly = r_hourly.json()
            props_h = j_hourly.get("properties") or {}
            periods = props_h.get("periods") or []
    except NoDataError:
        # Propagate explicit "no data" conditions upward.
        raise
    except Exception as exc:
        # Any other error is treated as "no usable data".
        raise NoDataError(f"NWS error: {exc}") from exc

    if not periods:
        raise NoDataError("NWS hourly returned no periods")

    # Limit to requested window
    n = min(len(periods), max(6, hours))

    gusts: List[float] = []
    sustained: List[float] = []

    upstream_stamp = now_iso()

    for idx in range(n):
        period = periods[idx] or {}
        if idx == 0:
            upstream_stamp = period.get("startTime") or upstream_stamp

        wind_speed_str = str(period.get("windSpeed") or "").strip()
        wind_gust_str = str(period.get("windGust") or "").strip()

        # Parse sustained
        try:
            spd = _parse_mph(wind_speed_str) if wind_speed_str else None
        except NoDataError:
            spd = None

        # Parse gust, fallback to sustained if gust is missing but speed exists.
        try:
            gst = _parse_mph(wind_gust_str) if wind_gust_str else None
        except NoDataError:
            gst = None

        if spd is None and gst is None:
            # Nothing usable for this hour.
            continue

        if spd is not None:
            sustained.append(spd)

        if gst is not None:
            gusts.append(gst)
        elif spd is not None:
            gusts.append(spd)

    if not gusts or not sustained:
        raise NoDataError("NWS hourly had no usable wind data")

    # Conservative statistics
    max_gust = max(gusts)
    max_sustained = max(sustained)

    # For expected values, we keep it simple: mean of the sample we collected.
    g_sum = 0.0
    s_sum = 0.0
    count = min(len(gusts), len(sustained))
    for i in range(count):
        g_sum += gusts[i]
        s_sum += sustained[i]
    expected_gust = g_sum / float(count)
    expected_sustained = s_sum / float(count)

    probability = probability_from_wind(max_gust, max_sustained)

    return expected_gust, expected_sustained, max_gust, max_sustained, probability, upstream_stamp


# -------------------------------------------------------------------
# Outage model (conservative)
# -------------------------------------------------------------------
def classify_severity(max_gust: float, max_sustained: float) -> int:
    """
    0..4 severity ladder on mph winds.
      0: Calm / nuisance
      1: Localized
      2: Scattered
      3: Widespread / significant
      4: Extreme / widespread
    """
    if max_gust >= 75 or max_sustained >= 45:
        return 4
    if max_gust >= 58 or max_sustained >= 35:
        return 3
    if max_gust >= 45 or max_sustained >= 25:
        return 2
    if max_gust >= 35 or max_sustained >= 18:
        return 1
    return 0


def outage_for_county(pop: int, probability: float, severity: int) -> Tuple[int, int]:
    """
    Very simple, conservative outage model:

      - If severity 0 or probability tiny -> 0
      - Otherwise outages scale with population * probability * rate(severity)

    Returns (predicted_customers_out, crews).
    """
    if pop <= 0:
        return 0, 0

    if severity <= 0 or probability <= 0.05:
        return 0, 0

    # Base rates: fraction of population impacted
    if severity >= 4:
        rate = 0.015
    elif severity == 3:
        rate = 0.010
    elif severity == 2:
        rate = 0.005
    else:  # severity == 1
        rate = 0.002

    predicted = int(pop * probability * rate)

    if predicted <= 0:
        return 0, 0

    # Roughly 1 crew per 4k customers, rounded up
    crews = (predicted + 3999) // 4000
    if crews < 1:
        crews = 1
    if crews > 999:
        crews = 999

    return predicted, crews


def probability_from_wind(max_gust: float, max_sustained: float) -> float:
    """
    Simple heuristic probability based on wind magnitudes.

    Output is clamped to [0.0, 0.95].
    """
    if max_gust <= 0 and max_sustained <= 0:
        return 0.0

    # Mild days stay low; only severe wind events get near 0.9+
    base = max(max_gust / 90.0, max_sustained / 60.0)
    if base < 0:
        base = 0.0
    if base > 0.95:
        base = 0.95
    return base


def mk_row(
    county_name: str,
    state: str,
    expected_gust: float,
    expected_sustained: float,
    max_gust: float,
    max_sustained: float,
    probability: float,
    pop: int,
    stamp: str,
) -> Dict:
    severity = classify_severity(max_gust, max_sustained)
    predicted, crews = outage_for_county(pop, probability, severity)

    # Confidence just mirrors probability, but in %
    if probability < 0:
        probability = 0.0
    if probability > 0.95:
        probability = 0.95
    confidence = int(round(probability * 100.0))
    if confidence < 0:
        confidence = 0
    if confidence > 100:
        confidence = 100

    return {
        "county": county_name,
        "state": state,
        "expectedGust": round(expected_gust, 1),
        "expectedSustained": round(expected_sustained, 1),
        "maxGust": round(max_gust, 1),
        "maxSustained": round(max_sustained, 1),
        "probability": round(probability, 2),
        "crews": crews,
        "severity": severity,
        "confidence": confidence,
        "population": pop,
        "predicted_customers_out": predicted,
        "generatedAt": now_iso(),
        "source": "nws",
        "upstreamStamp": stamp,
    }


# -------------------------------------------------------------------
# Core compute + state / mode selection
# -------------------------------------------------------------------
def indices_for(mode: str, region: str, state: str, sample: int) -> List[int]:
    """
    Select a subset of county indices based on mode.

    In your current app you are using only "State" mode, but we keep
    "Nationwide" and "Regional" here for compatibility.
    """
    mode_clean = (mode or "State").strip()

    if mode_clean == "Nationwide":
        idx = list(range(len(COUNTIES)))
    elif mode_clean == "State" and state:
        idx = STATE_IDX.get(state.upper(), [])
    elif mode_clean == "Regional" and region in REGION_STATES:
        allowed = set(REGION_STATES[region])
        base: List[int] = []
        for st in allowed:
            base.extend(STATE_IDX.get(st, []))
        idx = base
    else:
        idx = []

    if not idx:
        return []

    # Prefer largest counties first
    idx_sorted = sorted(idx, key=lambda i: COUNTIES[i][4], reverse=True)

    if sample > 0 and sample < len(idx_sorted):
        return idx_sorted[:sample]

    return idx_sorted


def cache_key(mode: str, region: str, state: str, hours: int, sample: int) -> str:
    return f"{mode}|{region}|{state}|{hours}|{sample}"


async def compute(indices: List[int], hours: int) -> List[Dict]:
    """
    For each county index, fetch NWS data and build a row.

    Counties with missing / bad data are skipped (NoDataError caught per-county).
    """
    out: List[Dict] = []
    sem = asyncio.Semaphore(6)

    async def one(i: int) -> None:
        c_name, st, la, lo, pop = COUNTIES[i]
        try:
            async with sem:
                eg, es, mg, ms, p, stamp = await live_wind(la, lo, hours)
            row = mk_row(c_name, st, eg, es, mg, ms, p, pop, stamp)
        except NoDataError as exc:
            print(f"[WARN] NWS no data for {c_name}, {st}: {exc}")
            return
        except Exception as exc:
            print(f"[WARN] compute error for {c_name}, {st}: {exc}")
            return

        out.append(row)

    await asyncio.gather(*(one(i) for i in indices))

    # Sort by severity / gust so the most interesting rows float to the top
    out.sort(key=lambda r: (r.get("severity", 0), r.get("maxGust", 0.0)), reverse=True)
    return out


async def handle(
    mode: str,
    region: str,
    state: str,
    hours: int,
    sample: int,
    nocache: int,
) -> List[Dict]:
    await load_counties_from_cenpop()
    await load_populations_from_pep()

    if not COUNTIES:
        return []

    # Clamp hours and sample
    hours = max(6, min(72, int(hours) if hours else 24))

    # If sample is not provided, use PAGE_SIZE; hard cap at 4 pages for safety.
    if not sample:
        sample = PAGE_SIZE
    else:
        sample = int(sample)
    if sample < 1:
        sample = 1
    if sample > PAGE_SIZE * 4:
        sample = PAGE_SIZE * 4

    mode_eff = (mode or "State").strip()
    if state:
        mode_eff = "State"

    idx = indices_for(mode_eff, region, state, sample)
    if not idx:
        return []

    key = cache_key(mode_eff, region or "", state or "", hours, sample)
    now_ts = time.time()

    if not nocache:
        hit = CACHE.get(key)
        if hit and (now_ts - hit[0]) < 600:
            return hit[1]

    rows = await compute(idx, hours)

    CACHE[key] = (now_ts, rows)
    return rows


# -------------------------------------------------------------------
# FastAPI routes
# -------------------------------------------------------------------
@app.get("/api/wx")
async def api_wx(
    req: Request,
    mode: str = "State",
    region: str = "",
    state: str = "",
    hours: int = 24,
    sample: int = PAGE_SIZE,
    nocache: int = 0,
):
    # Default to State mode if a state is provided
    mode_eff = mode or "State"
    if state:
        mode_eff = "State"
    return await handle(mode_eff, region, state, hours, sample, nocache)


@app.get("/wx")
async def wx_alias(
    req: Request,
    mode: str = "State",
    region: str = "",
    state: str = "",
    hours: int = 24,
    sample: int = PAGE_SIZE,
    nocache: int = 0,
):
    mode_eff = mode or "State"
    if state:
        mode_eff = "State"
    return await handle(mode_eff, region, state, hours, sample, nocache)


@app.get("/{full_path:path}")
async def catch_all(
    req: Request,
    full_path: str,
    mode: str = "State",
    region: str = "",
    state: str = "",
    hours: int = 24,
    sample: int = PAGE_SIZE,
    nocache: int = 0,
):
    mode_eff = mode or "State"
    if state:
        mode_eff = "State"
    return await handle(mode_eff, region, state, hours, sample, nocache)


@app.on_event("startup")
async def init() -> None:
    await load_counties_from_cenpop()
    await load_populations_from_pep()
