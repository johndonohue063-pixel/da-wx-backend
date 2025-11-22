from __future__ import annotations

import json
import math
from dataclasses import dataclass
from enum import Enum
from functools import lru_cache
from pathlib import Path
from typing import Dict, List, Optional

from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
import urllib.request
import urllib.error
import time

# ---------------------------------------------------------------------------
# FastAPI app setup
# ---------------------------------------------------------------------------

app = FastAPI(title="DA Wx Backend", version="1.1.0")

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
    probability: float          # 0.0â€“1.0
    predicted_customers_out: int
    crews: int

    def to_dict(self):
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
                continue
    return out

# Region â†’ states mapping (NOAA-style, readable)
REGION_STATES = {
    "northeast": [
        "Maine","New Hampshire","Vermont","Massachusetts","Rhode Island",
        "Connecticut","New York","New Jersey","Pennsylvania"
    ],
    "southeast": [
        "Virginia","North Carolina","South Carolina","Georgia","Florida",
        "Alabama","Mississippi"
    ],
    "ohio valley": ["Ohio","West Virginia","Kentucky","Indiana"],
    "upper midwest": ["Michigan","Wisconsin","Minnesota","Iowa"],
    "south": ["Tennessee","Arkansas","Louisiana"],
    "northern rockies & plains": ["Montana","North Dakota","South Dakota","Wyoming"],
    "northwest": ["Washington","Oregon","Idaho"],
    "southwest": ["California","Nevada","Utah","Arizona","New Mexico"],
    "west": ["Colorado","Kansas","Oklahoma","Texas","Nebraska"],
    "mid-atlantic": [
        "New York","New Jersey","Pennsylvania",
        "Maryland","Delaware","Virginia","West Virginia"
    ],
    "south central": [
        "Texas","Oklahoma","Arkansas","Louisiana"
    ],
}

# ---------------------------------------------------------------------------
# Select counties
# ---------------------------------------------------------------------------

def filter_counties(mode: Mode, sample: int,
                    region: Optional[str],
                    state: Optional[str],
                    county: Optional[str]) -> List[County]:
    allc = load_counties()

    if mode == Mode.NATIONAL:
        counties = allc
    elif mode == Mode.STATE:
        if not state:
            raise ValueError("state is required for STATE mode")
        counties = [c for c in allc if c.state.lower() == state.lower()]
    elif mode == Mode.COUNTY:
        if not state or not county:
            raise ValueError("state and county are required for COUNTY mode")
        counties = [
            c for c in allc
            if c.state.lower() == state.lower()
            and c.county.lower().startswith(county.lower())
        ]
    elif mode == Mode.REGION:
        if not region:
            raise ValueError("region is required for REGION mode")
        key = region.lower()
        counties = [c for c in allc if c.state in REGION_STATES.get(key, [])]
    else:
        counties = allc

    counties = sorted(counties, key=lambda c: c.population, reverse=True)
    return counties[:sample]

# ---------------------------------------------------------------------------
# NOAA helpers with RETRY + TIMEOUT + SAFE FALLBACK
# ---------------------------------------------------------------------------

UA = "DivergentAllianceWxBackend/1.1"

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
        return {"expectedGust": 0.0, "expectedSustained": 0.0,
                "maxGust": 0.0, "maxSustained": 0.0}

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
        return {"expectedGust": 0.0, "expectedSustained": 0.0,
                "maxGust": 0.0, "maxSustained": 0.0}

    return {
        "expectedGust": round(sum(gusts) / len(gusts), 1),
        "expectedSustained": round(sum(sust) / len(sust), 1),
        "maxGust": round(max(gusts), 1),
        "maxSustained": round(max(sust), 1),
    }

def fallback_row(county: County) -> WxRow:
    return WxRow(
        county=county.county,
        state=county.state,
        population=county.population,
        severity=1,
        expectedGust=0.0,
        expectedSustained=0.0,
        maxGust=0.0,
        maxSustained=0.0,
        probability=0.0,
        predicted_customers_out=0,
        crews=1,
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
    Cluster ceilings can be layered on top if needed, but are not
    implemented here because we do not have cluster context in this backend.
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
    if p < 0.20:  # 12â€“19% tier style, with scale
        prob_scale = p / 0.16 if p > 0 else 0.0
        if pop >= 500_000:
            tier_cap = pop * 0.01 * prob_scale
        elif pop >= 100_000:
            tier_cap = pop * 0.015 * prob_scale
        else:
            tier_cap = pop * 0.02 * prob_scale
    elif p < 0.30:  # 20â€“29%
        if pop < 100_000:
            tier_cap = pop * 0.02
        elif pop < 500_000:
            tier_cap = pop * 0.015
        elif pop < 1_000_000:
            tier_cap = pop * 0.01
        else:
            tier_cap = pop * 0.008
    elif p < 0.45:  # 30â€“44%
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
# Fetch NOAA-based row for a single county
# ---------------------------------------------------------------------------

def fetch_row_for_county(county: County, hours: int) -> WxRow:
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

        # Outage probability heuristic (0..~0.95)
        prob = min(0.95, max(0.0, 0.5 + (max_g / 100.0)))

        # Predicted customers out (SPP-style core, no cluster ceiling)
        pop = county.population
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
        # Never skip a county â€” return fallback
        return fallback_row(county)

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
    try:
        counties = filter_counties(mode, sample, region, state, county)
    except Exception as e:
        raise ValueError(str(e))

    rows: List[WxRow] = []
    for c in counties:
        rows.append(fetch_row_for_county(c, hours))

    rows.sort(
        key=lambda r: (r.severity, r.predicted_customers_out, r.maxGust, r.maxSustained),
        reverse=True,
    )
    return [r.to_dict() for r in rows]

# ---------------------------------------------------------------------------
# State abbreviation mapping + improved county filtering
# ---------------------------------------------------------------------------

STATE_ABBREV_TO_NAME = {
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


def filter_counties(mode, sample, region, state, county):
    """
    Replacement filter_counties that:
      - Accepts state abbreviations (e.g. "RI") and full names
      - Handles National, State, County, Region modes
      - For Regions, can balance output across states instead of all NY
    """
    allc = load_counties()

    # NATIONAL: all counties
    if mode == Mode.NATIONAL:
        counties = allc

    # STATE: normalize abbreviations like "RI" -> "Rhode Island"
    elif mode == Mode.STATE:
        if not state:
            raise ValueError("state is required for STATE mode")
        raw = state.strip()
        full_name = STATE_ABBREV_TO_NAME.get(raw.upper(), raw)
        counties = [c for c in allc if c.state.lower() == full_name.lower()]

    # COUNTY: same normalization, then prefix-match on county name
    elif mode == Mode.COUNTY:
        if not state or not county:
            raise ValueError("state and county are required for COUNTY mode")
        raw = state.strip()
        full_name = STATE_ABBREV_TO_NAME.get(raw.upper(), raw)
        counties = [
            c for c in allc
            if c.state.lower() == full_name.lower()
            and c.county.lower().startswith(county.lower())
        ]

    # REGION: use REGION_STATES and allow for more balanced per-state output
    elif mode == Mode.REGION:
        if not region:
            raise ValueError("region is required for REGION mode")

        key = region.lower()
        state_list = REGION_STATES.get(key, [])
        if not state_list:
            counties = []
        else:
            # You can tune this. For now, try to give each state some representation.
            per_state_limit = max(1, sample // max(1, len(state_list)))
            selected = []
            for st in state_list:
                st_counties = [c for c in allc if c.state == st]
                st_counties.sort(key=lambda c: c.population, reverse=True)
                selected.extend(st_counties[:per_state_limit])
            selected.sort(key=lambda c: c.population, reverse=True)
            counties = selected[:sample]

    else:
        counties = allc

    counties = sorted(counties, key=lambda c: c.population, reverse=True)
    return counties[:sample]

