from __future__ import annotations

import json
from dataclasses import dataclass
from enum import Enum
from functools import lru_cache
from pathlib import Path
from typing import Dict, List, Optional

from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
import urllib.request
import time
import random
from concurrent.futures import ThreadPoolExecutor, as_completed

# ---------------------------------------------------------------------------
# FastAPI app setup
# ---------------------------------------------------------------------------

app = FastAPI(title="DA Wx Backend", version="1.2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

class Mode(str, Enum):
    NATIONAL = "National"
    REGION = "Region"
    STATE = "State"
    COUNTY = "County"


@dataclass
class County:
    statefp: str
    countyfp: str
    county: str
    state: str
    population: int
    lat: float
    lon: float


@dataclass
class WxRow:
    county: str
    state: str
    population: int
    severity: int
    expectedGust: float
    expectedSustained: float
    maxGust: float
    maxSustained: float
    probability: float          # 0.0-1.0
    predicted_customers_out: int
    crews: int

    def to_dict(self) -> Dict[str, object]:
        return {
            "county": self.county,
            "state": self.state,
            "population": self.population,
            "severity": self.severity,
            "expectedGust": self.expectedGust,
            "expectedSustained": self.expectedSustained,
            "maxGust": self.maxGust,
            "maxSustained": self.maxSustained,
            "probability": self.probability,
            "predicted_customers_out": self.predicted_customers_out,
            "crews": self.crews,
        }


# ---------------------------------------------------------------------------
# Load counties (Census 2020, mean center of population)
# ---------------------------------------------------------------------------

@lru_cache
def load_counties() -> List[County]:
    here = Path(__file__).resolve().parent
    path = here / "CenPop2020_Mean_CO.txt"
    if not path.exists():
        raise RuntimeError("County file missing: CenPop2020_Mean_CO.txt")

    out: List[County] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("STATEFP"):
                continue
            parts = line.split(",")
            if len(parts) != 7:
                continue
            try:
                statefp, countyfp, couname, stname, pop, lat, lon = parts
                out.append(
                    County(
                        statefp=statefp,
                        countyfp=countyfp,
                        county=couname + " County",
                        state=stname,
                        population=int(pop),
                        lat=float(lat),
                        lon=float(lon),
                    )
                )
            except Exception:
                # Skip malformed rows, keep the rest of the file usable
                continue
    return out


# ---------------------------------------------------------------------------
# Region + state mappings
# ---------------------------------------------------------------------------

# Region -> states mapping (NOAA-ish)
REGION_STATES: Dict[str, List[str]] = {
    "northeast": [
        "Maine", "New Hampshire", "Vermont", "Massachusetts", "Rhode Island",
        "Connecticut", "New York", "New Jersey", "Pennsylvania"
    ],
    "southeast": [
        "Virginia", "North Carolina", "South Carolina", "Georgia", "Florida",
        "Alabama", "Mississippi", "Tennessee"
    ],
    "ohio valley": ["Ohio", "West Virginia", "Kentucky", "Indiana"],
    "upper midwest": ["Michigan", "Wisconsin", "Minnesota", "Iowa"],
    "south": ["Tennessee", "Arkansas", "Louisiana"],
    "northern rockies & plains": ["Montana", "North Dakota", "South Dakota", "Wyoming"],
    "northwest": ["Washington", "Oregon", "Idaho"],
    "southwest": ["California", "Nevada", "Utah", "Arizona", "New Mexico"],
    "west": ["Colorado", "Kansas", "Oklahoma", "Texas", "Nebraska"],
    "mid-atlantic": [
        "New York", "New Jersey", "Pennsylvania",
        "Maryland", "Delaware", "Virginia", "West Virginia"
    ],
    "south central": [
        "Texas", "Oklahoma", "Arkansas", "Louisiana"
    ],
}

STATE_ABBREV_TO_NAME: Dict[str, str] = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
    "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
    "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho",
    "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
    "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
    "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi",
    "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
    "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
    "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
    "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina",
    "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah",
    "VT": "Vermont", "VA": "Virginia", "WA": "Washington", "WV": "West Virginia",
    "WI": "Wisconsin", "WY": "Wyoming",
}


def _normalize_state_name(raw: str) -> str:
    raw = (raw or "").strip()
    if not raw:
        return raw
    return STATE_ABBREV_TO_NAME.get(raw.upper(), raw)


def filter_counties(
    mode: Mode,
    sample: int,
    region: Optional[str],
    state: Optional[str],
    county: Optional[str],
) -> List[County]:
    """Single, consistent filter implementation used by /api/wx.

    - Accepts full state names OR USPS abbreviations for STATE/COUNTY modes.
    - REGION uses REGION_STATES mapping and is case-insensitive.
    - NATIONAL simply samples from all counties.
    """
    allc = load_counties()

    # Build base list for the requested scope
    if mode == Mode.NATIONAL:
        base = list(allc)
    elif mode == Mode.STATE:
        if not state:
            raise ValueError("state is required for STATE mode")
        full_name = _normalize_state_name(state)
        base = [c for c in allc if c.state.lower() == full_name.lower()]
    elif mode == Mode.COUNTY:
        if not state or not county:
            raise ValueError("state and county are required for COUNTY mode")
        full_name = _normalize_state_name(state)
        county_prefix = county.strip().lower()
        base = [
            c
            for c in allc
            if c.state.lower() == full_name.lower()
            and c.county.lower().startswith(county_prefix)
        ]
    elif mode == Mode.REGION:
        if not region:
            raise ValueError("region is required for REGION mode")

        key = (region or "").strip().lower()
        region_key = None
        for k in REGION_STATES.keys():
            if k.lower() == key:
                region_key = k
                break
        if region_key is None:
            valid = ", ".join(sorted(REGION_STATES.keys()))
            raise ValueError(f"Unknown region '{region}'. Valid options: {valid}")

        allowed_states = set(REGION_STATES[region_key])
        base = [c for c in allc if c.state in allowed_states]
    else:
        base = list(allc)

    if not base:
        return []

    # Sort by population (biggest first) so we always include major metros
    base.sort(key=lambda c: c.population, reverse=True)

    if sample >= len(base):
        return base

    # For NATIONAL & REGION we want wider geographic coverage, so random sample.
    # For STATE/COUNTY we just take the top-N by population.
    if mode in (Mode.NATIONAL, Mode.REGION):
        return random.sample(base, sample)
    return base[:sample]


# ---------------------------------------------------------------------------
# NOAA helpers with RETRY + TIMEOUT + SAFE FALLBACK
# ---------------------------------------------------------------------------

UA = "DivergentAllianceWxBackend/1.2"
WX_MAX_WORKERS = 12  # max parallel NOAA requests per API call


def http_get_json(url: str) -> Dict:
    for attempt in range(2):  # retry once
        try:
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": UA,
                    "Accept": "application/geo+json, application/json",
                },
            )
            with urllib.request.urlopen(req, timeout=4) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception:
            if attempt == 1:
                raise
            time.sleep(0.2)
    raise RuntimeError("Should not reach here")


def parse_mph(field) -> float:
    if not field:
        return 0.0
    s = str(field)
    best = 0.0
    for p in s.replace("mph", "").split():
        try:
            v = float(p)
            if v > best:
                best = v
        except Exception:
            pass
    return best


def summarize_hours(hourly_json: Dict, hours: int) -> Dict[str, float]:
    periods = hourly_json.get("properties", {}).get("periods", [])
    if not isinstance(periods, list) or not periods:
        return {
            "expectedGust": 0.0,
            "expectedSustained": 0.0,
            "maxGust": 0.0,
            "maxSustained": 0.0,
        }

    slice_p = periods[: min(hours, len(periods))]

    gusts: List[float] = []
    sust: List[float] = []

    for p in slice_p:
        ws = parse_mph(p.get("windSpeed"))
        wg = parse_mph(p.get("windGust"))
        if wg == 0:
            wg = ws
        sust.append(ws)
        gusts.append(wg)

    if not gusts or not sust:
        return {
            "expectedGust": 0.0,
            "expectedSustained": 0.0,
            "maxGust": 0.0,
            "maxSustained": 0.0,
        }

    return {
        "expectedGust": round(sum(gusts) / len(gusts), 1),
        "expectedSustained": round(sum(sust) / len(sust), 1),
        "maxGust": round(max(gusts), 1),
        "maxSustained": round(max(sust), 1),
    }


def fallback_row(county: County) -> WxRow:
    # Treat as "no data / no threat", not Level 1.
    return WxRow(
        county=county.county,
        state=county.state,
        population=county.population,
        severity=0,
        expectedGust=0.0,
        expectedSustained=0.0,
        maxGust=0.0,
        maxSustained=0.0,
        probability=0.0,
        predicted_customers_out=0,
        crews=0,
    )


# ---------------------------------------------------------------------------
# Outage prediction (SPP-style core)
# ---------------------------------------------------------------------------

def predict_customers_out(pop: int, prob: float) -> int:
    """
    Core SPP-style logic:
      - raw_out = population * probability
      - probability bands with outage caps
      - metro dampening
    """
    if pop <= 0 or prob <= 0.0:
        return 0

    p = max(0.0, min(0.99, prob))
    raw_out = pop * p

    # Metro dampening
    if pop >= 2_000_000:
        cap_mult = 0.85
    elif pop >= 1_000_000:
        cap_mult = 1.0
    else:
        cap_mult = 1.0

    # Probability-tier caps (banded)
    if p < 0.20:  # 0-19%
        prob_scale = p / 0.16 if p > 0 else 0.0
        if pop >= 500_000:
            tier_cap = pop * 0.01 * prob_scale
        elif pop >= 100_000:
            tier_cap = pop * 0.015 * prob_scale
        else:
            tier_cap = pop * 0.02 * prob_scale
    elif p < 0.30:  # 20-29%
        if pop < 100_000:
            tier_cap = pop * 0.02
        elif pop < 500_000:
            tier_cap = pop * 0.015
        elif pop < 1_000_000:
            tier_cap = pop * 0.01
        else:
            tier_cap = pop * 0.008
    elif p < 0.45:  # 30-44%
        if pop < 100_000:
            tier_cap = pop * 0.03
        elif pop < 500_000:
            tier_cap = pop * 0.022
        elif pop < 1_000_000:
            tier_cap = pop * 0.015
        else:
            tier_cap = pop * 0.01
    else:  # >= 45%
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
    """
    Simple crew ladder based on predicted customers out.
    You can tune thresholds however you like.
    """
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
    # very small or zero predicted impact
    return 0


# ---------------------------------------------------------------------------
# Probability from winds – FIXED (no 7 mph -> 20k customers nonsense)
# ---------------------------------------------------------------------------

def probability_from_severity(severity: int) -> float:
    """
    Map severity band (0-4) to an outage probability in 0-1.

    These are deliberately conservative at the low end so that light
    winds never imply big outage numbers.
    """
    if severity <= 0:
        return 0.0          # calm / breezy -> essentially no outages
    if severity == 1:
        return 0.18         # 25-34 gusts or 18-24 sustained
    if severity == 2:
        return 0.30         # 35-49 gusts or 25-34 sustained
    if severity == 3:
        return 0.45         # 50-64 gusts or 35-44 sustained
    # severity >= 4
    return 0.60             # 65+ gusts or 45+ sustained


# ---------------------------------------------------------------------------
# Fetch NOAA-based row for a single county
# ---------------------------------------------------------------------------

def fetch_row_for_county(county: County, hours: int) -> WxRow:
    """
    Live NOAA/NWS-backed fetch for a single county.

    IMPORTANT:
      Threat Level 0 (severity == 0) is hard-clamped to:
        - probability = 0.0
        - predicted_customers_out = 0
        - crews = 0

    This prevents benign wind forecasts from ever showing
    thousands of customers out at "Level 0".
    """
    try:
        pts = http_get_json(f"https://api.weather.gov/points/{county.lat},{county.lon}")
        hourly_url = pts.get("properties", {}).get("forecastHourly")
        if not hourly_url:
            return fallback_row(county)

        hourly = http_get_json(hourly_url)
        s = summarize_hours(hourly, hours)

        max_g = s["maxGust"]
        max_s = s["maxSustained"]

        # Severity bands
        if max_g >= 65 or max_s >= 45:
            sev = 4
        elif max_g >= 50 or max_s >= 35:
            sev = 3
        elif max_g >= 35 or max_s >= 25:
            sev = 2
        elif max_g >= 25 or max_s >= 18:
            sev = 1
        else:
            sev = 0

        pop = county.population

        # Core outage probability heuristic (0..~0.95) from wind
        prob = min(0.95, max(0.0, 0.5 + (max_g / 100.0)))

        if sev == 0:
            # Threat Level 0 clamp: no outages, no crews, prob 0.0
            prob = 0.0
            predicted = 0
            crew_ct = 0
        else:
            # Predicted customers out (SPP-style core, no cluster ceiling)
            predicted = predict_customers_out(pop, prob)
            # Crews from predicted customers out
            crew_ct = crews_from_predicted(predicted, pop)

        return WxRow(
            county=county.county,
            state=county.state,
            population=pop,
            severity=sev,
            expectedGust=s["expectedGust"],
            expectedSustained=s["expectedSustained"],
            maxGust=max_g,
            maxSustained=max_s,
            probability=round(prob, 2),
            predicted_customers_out=predicted,
            crews=crew_ct,
        )
    except Exception:
        # Never skip a county — return fallback
        return fallback_row(county)
def compute_rows_for_counties(counties: List[County], hours: int) -> List[WxRow]:
    rows: List[WxRow] = []
    if not counties:
        return rows

    max_workers = min(len(counties), WX_MAX_WORKERS)
    if max_workers <= 1:
        for c in counties:
            rows.append(fetch_row_for_county(c, hours))
        return rows

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_county = {
            executor.submit(fetch_row_for_county, c, hours): c for c in counties
        }
        for fut in as_completed(future_to_county):
            c = future_to_county[fut]
            try:
                row = fut.result()
            except Exception:
                row = fallback_row(c)
            rows.append(row)

    return rows


# ---------------------------------------------------------------------------
# API route
# ---------------------------------------------------------------------------

@app.get("/api/wx")
def api_wx(
    mode: Mode = Query(..., description="National, Region, State, or County"),
    hours: int = Query(6, ge=1, le=120),
    sample: int = Query(20, ge=1, le=200),
    region: Optional[str] = Query(None),
    state: Optional[str] = Query(None),
    county: Optional[str] = Query(None),
):
    counties = filter_counties(mode, sample, region, state, county)
    rows = compute_rows_for_counties(counties, hours)

    rows.sort(
        key=lambda r: (r.severity, r.predicted_customers_out, r.maxGust, r.maxSustained),
        reverse=True,
    )
    return [r.to_dict() for r in rows]


@app.get("/health")
async def health():
    return {"status": "ok"}
