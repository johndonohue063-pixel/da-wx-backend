from __future__ import annotations

import json
import math
from dataclasses import dataclass
from enum import Enum
from functools import lru_cache
from pathlib import Path
from typing import Dict, List, Optional

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
import urllib.request
import urllib.error


# ---------------------------------------------------------------------------
# FastAPI app setup
# ---------------------------------------------------------------------------

app = FastAPI(title="DA Wx Backend", version="1.0.0")

# Allow the mobile app to call this API.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # tighten later if you want
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
    severity: int
    expectedGust: float
    expectedSustained: float
    maxGust: float
    maxSustained: float
    probability: float
    crews: int

    def to_dict(self) -> Dict[str, object]:
        return {
            "county": self.county,
            "state": self.state,
            "severity": self.severity,
            "expectedGust": self.expectedGust,
            "expectedSustained": self.expectedSustained,
            "maxGust": self.maxGust,
            "maxSustained": self.maxSustained,
            "probability": self.probability,
            "crews": self.crews,
        }


# ---------------------------------------------------------------------------
# County centroids from CenPop2020_Mean_CO.txt
# ---------------------------------------------------------------------------

@lru_cache
def load_counties() -> List[County]:
    """
    Load county centroids from CenPop2020_Mean_CO.txt.

    CSV format:
    STATEFP,COUNTYFP,COUNAME,STNAME,POPULATION,LATITUDE,LONGITUDE
    """
    here = Path(__file__).resolve().parent
    path = here / "CenPop2020_Mean_CO.txt"
    if not path.exists():
        raise RuntimeError(f"CenPop2020_Mean_CO.txt not found next to {__file__}")

    counties: List[County] = []

    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            # Skip header (handles BOM too)
            if line.startswith("STATEFP") or line.startswith("\ufeffSTATEFP"):
                continue

            parts = line.split(",")
            if len(parts) != 7:
                continue

            statefp, countyfp, couname, stname, pop, lat, lon = parts
            try:
                counties.append(
                    County(
                        statefp=statefp,
                        countyfp=countyfp,
                        county=couname + " County",  # "Adams" -> "Adams County"
                        state=stname,
                        population=int(pop),
                        lat=float(lat),
                        lon=float(lon),
                    )
                )
            except ValueError:
                # Bad numeric parsing – just skip this row
                continue

    if not counties:
        raise RuntimeError("No counties loaded from CenPop2020_Mean_CO.txt")

    return counties


# Approximate climate regions to match your UI labels
REGION_STATES: Dict[str, List[str]] = {
    "northeast": [
        "Maine", "New Hampshire", "Vermont", "Massachusetts",
        "Rhode Island", "Connecticut", "New York",
        "New Jersey", "Pennsylvania",
    ],
    "southeast": [
        "Virginia", "North Carolina", "South Carolina", "Georgia",
        "Florida", "Alabama", "Mississippi",
    ],
    "ohio valley": [
        "Ohio", "West Virginia", "Kentucky", "Indiana",
    ],
    "upper midwest": [
        "Michigan", "Wisconsin", "Minnesota", "Iowa",
    ],
    "south": [
        "Tennessee", "Arkansas", "Louisiana",
    ],
    "northern rockies & plains": [
        "Montana", "North Dakota", "South Dakota", "Wyoming",
    ],
    "northwest": [
        "Washington", "Oregon", "Idaho",
    ],
    "southwest": [
        "California", "Nevada", "Utah", "Arizona", "New Mexico",
    ],
    "west": [
        "Colorado", "Kansas", "Oklahoma", "Texas", "Nebraska",
    ],
}


def filter_counties(
    mode: Mode,
    sample: int,
    region: Optional[str],
    state: Optional[str],
    county: Optional[str],
) -> List[County]:
    all_counties = load_counties()

    if mode == Mode.NATIONAL:
        counties = all_counties
    elif mode == Mode.STATE:
        if not state:
            raise HTTPException(status_code=400, detail="state is required for mode=State")
        s_lower = state.lower()
        counties = [c for c in all_counties if c.state.lower() == s_lower]
    elif mode == Mode.COUNTY:
        if not (state and county):
            raise HTTPException(
                status_code=400,
                detail="state and county are required for mode=County",
            )
        s_lower = state.lower()
        c_lower = county.lower()
        counties = [
            c for c in all_counties
            if c.state.lower() == s_lower and c.county.lower().startswith(c_lower)
        ]
    elif mode == Mode.REGION:
        if not region:
            raise HTTPException(status_code=400, detail="region is required for mode=Region")
        key = region.lower()
        if key not in REGION_STATES:
            raise HTTPException(status_code=400, detail=f"Unknown region '{region}'")
        allowed_states = set(REGION_STATES[key])
        counties = [c for c in all_counties if c.state in allowed_states]
    else:
        counties = all_counties

    if not counties:
        return []

    # Largest counties first (by population)
    counties = sorted(counties, key=lambda c: c.population, reverse=True)
    return counties[:sample]


# ---------------------------------------------------------------------------
# NOAA helpers – standard library only
# ---------------------------------------------------------------------------

UA = "DivergentAllianceWxBackend/1.0 (mobile backend)"


def http_get_json(url: str) -> Dict:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": UA,
            "Accept": "application/geo+json, application/json;q=0.9,*/*;q=0.1",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = resp.read()
    except urllib.error.HTTPError as e:
        raise HTTPException(status_code=e.code, detail=f"Upstream error {e.code} for {url}") from e
    except urllib.error.URLError as e:
        raise HTTPException(status_code=502, detail=f"Unable to reach upstream: {e}") from e

    try:
        return json.loads(data.decode("utf-8"))
    except json.JSONDecodeError:
        raise HTTPException(status_code=502, detail="Bad JSON from upstream")


def parse_mph(field) -> float:
    """
    NOAA winds are strings like '15 mph' or '20 to 30 mph'.
    Take the largest number.
    """
    if not field:
        return 0.0
    s = str(field)
    parts = s.replace("mph", "").split()
    best = 0.0
    for p in parts:
        try:
            v = float(p)
            if v > best:
                best = v
        except ValueError:
            continue
    return best


def summarize_hours(hourly_json: Dict, hours: int) -> Dict[str, float]:
    periods = (
        hourly_json
        .get("properties", {})
        .get("periods", [])
    )
    if not isinstance(periods, list) or not periods:
        return {
            "expectedGust": 0.0,
            "expectedSustained": 0.0,
            "maxGust": 0.0,
            "maxSustained": 0.0,
        }

    # Use first `hours` periods (NOAA hourly is already time-ordered)
    slice_periods = periods[: max(1, min(hours, len(periods)))]

    gusts: List[float] = []
    sust: List[float] = []

    for p in slice_periods:
        ws = parse_mph(p.get("windSpeed"))
        wg = parse_mph(p.get("windGust"))
        sust.append(ws)
        gusts.append(wg)

    if not gusts and not sust:
        return {
            "expectedGust": 0.0,
            "expectedSustained": 0.0,
            "maxGust": 0.0,
            "maxSustained": 0.0,
        }

    exp_gust = sum(gusts) / len(gusts) if gusts else 0.0
    exp_sust = sum(sust) / len(sust) if sust else 0.0
    max_gust = max(gusts) if gusts else 0.0
    max_sust = max(sust) if sust else 0.0

    return {
        "expectedGust": round(exp_gust, 1),
        "expectedSustained": round(exp_sust, 1),
        "maxGust": round(max_gust, 1),
        "maxSustained": round(max_sust, 1),
    }


def fetch_row_for_county(county: County, hours: int) -> WxRow:
    # Step 1: NOAA points API → get hourly forecast URL
    points_url = f"https://api.weather.gov/points/{county.lat},{county.lon}"
    points = http_get_json(points_url)
    props = points.get("properties") or {}
    hourly_url = props.get("forecastHourly")
    if not hourly_url:
        # No hourly forecast – treat as calm but real location
        return WxRow(
            county=county.county,
            state=county.state,
            severity=1,
            expectedGust=0.0,
            expectedSustained=0.0,
            maxGust=0.0,
            maxSustained=0.0,
            probability=0.6,
            crews=1,
        )

    hourly = http_get_json(hourly_url)
    summary = summarize_hours(hourly, hours)

    max_gust = summary["maxGust"]
    max_sust = summary["maxSustained"]

    # Severity heuristic – can be tuned later
    if max_gust >= 65 or max_sust >= 45:
        severity = 4
    elif max_gust >= 50 or max_sust >= 35:
        severity = 3
    elif max_gust >= 35 or max_sust >= 25:
        severity = 2
    else:
        severity = 1

    # Simple probability proxy – higher winds => higher "probability"
    probability = min(0.95, 0.5 + (max_gust / 100.0))

    # Crew recommendation – rough rule of thumb.
    crews = max(1, min(10, int(math.ceil(max_gust / 20.0))))

    return WxRow(
        county=county.county,
        state=county.state,
        severity=severity,
        expectedGust=summary["expectedGust"],
        expectedSustained=summary["expectedSustained"],
        maxGust=max_gust,
        maxSustained=max_sust,
        probability=round(probability, 2),
        crews=crews,
    )


# ---------------------------------------------------------------------------
# API routes
# ---------------------------------------------------------------------------

@app.get("/")
def root():
    return {"status": "ok", "message": "DA Wx backend running"}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/api/wx")
def api_wx(
    mode: Mode = Query(..., description="National, Region, State, County"),
    hours: int = Query(6, ge=1, le=120),
    sample: int = Query(10, ge=1, le=50),
    region: Optional[str] = None,
    state: Optional[str] = None,
    county: Optional[str] = None,
):
    """
    Unified endpoint for the mobile app.

    Examples:
      /api/wx?mode=National&hours=6&sample=25
      /api/wx?mode=State&state=Rhode%20Island&hours=10&sample=20
      /api/wx?mode=County&state=Illinois&county=Cook&hours=6&sample=5
    """
    # Clamp sample defensively – NOAA gets slow if you ask too many counties.
    if sample > 50:
        sample = 50

    counties = filter_counties(mode, sample, region, state, county)
    if not counties:
        return []

    rows: List[WxRow] = []
    for c in counties:
        try:
            rows.append(fetch_row_for_county(c, hours))
        except HTTPException:
            # Bubble up FastAPI HTTP errors (like 502 from NOAA).
            raise
        except Exception as e:  # noqa: BLE001
            # If one county fails, log and skip it.
            print(f"ERROR fetching NOAA data for {c.county}, {c.state}: {e}")
            continue

    # Highest risk first.
    rows.sort(key=lambda r: (r.severity, r.maxGust, r.maxSustained), reverse=True)

    # Convert dataclasses to dictionaries for JSON.
    return [r.to_dict() for r in rows]
