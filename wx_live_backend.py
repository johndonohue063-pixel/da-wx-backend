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
import time

# ---------------------------------------------------------------------------
# FastAPI app setup
# ---------------------------------------------------------------------------

app = FastAPI(title="DA Wx Backend", version="1.0.0")

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
    severity: int
    expectedGust: float
    expectedSustained: float
    maxGust: float
    maxSustained: float
    probability: float
    crews: int

    def to_dict(self):
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
# Load counties
# ---------------------------------------------------------------------------

@lru_cache
def load_counties() -> List[County]:
    here = Path(__file__).resolve().parent
    path = here / "CenPop2020_Mean_CO.txt"
    if not path.exists():
        raise RuntimeError("County file missing")

    out = []
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
            except:
                continue
    return out

# Region → states mapping
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
}

# ---------------------------------------------------------------------------
# Select counties
# ---------------------------------------------------------------------------

def filter_counties(mode, sample, region, state, county):
    allc = load_counties()

    if mode == Mode.NATIONAL:
        counties = allc
    elif mode == Mode.STATE:
        counties = [c for c in allc if c.state.lower() == state.lower()]
    elif mode == Mode.COUNTY:
        counties = [c for c in allc
                    if c.state.lower() == state.lower()
                    and c.county.lower().startswith(county.lower())]
    elif mode == Mode.REGION:
        key = region.lower()
        counties = [c for c in allc if c.state in REGION_STATES.get(key, [])]
    else:
        counties = allc

    counties = sorted(counties, key=lambda c: c.population, reverse=True)
    return counties[:sample]

# ---------------------------------------------------------------------------
# NOAA helpers with RETRY + TIMEOUT + SAFE FALLBACK
# ---------------------------------------------------------------------------

UA = "DivergentAllianceWxBackend/1.0"

def http_get_json(url: str) -> Dict:
    for attempt in range(2):  # retry once
        try:
            req = urllib.request.Request(
                url,
                headers={"User-Agent": UA, "Accept": "application/geo+json, application/json"}
            )
            with urllib.request.urlopen(req, timeout=3) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as e:
            if attempt == 1:
                raise e
            time.sleep(0.2)
    raise RuntimeError("Should not reach here")

def parse_mph(field):
    if not field:
        return 0.0
    s = str(field)
    best = 0.0
    for p in s.replace("mph","").split():
        try:
            v = float(p)
            if v > best:
                best = v
        except:
            pass
    return best

def summarize_hours(hourly_json, hours):
    periods = hourly_json.get("properties",{}).get("periods",[])
    if not isinstance(periods,list) or not periods:
        return {"expectedGust":0,"expectedSustained":0,"maxGust":0,"maxSustained":0}

    slice_p = periods[:min(hours,len(periods))]

    gusts=[]
    sust=[]
    for p in slice_p:
        ws=parse_mph(p.get("windSpeed"))
        wg=parse_mph(p.get("windGust"))
        if wg == 0:  # gust fallback
            wg = ws
        sust.append(ws)
        gusts.append(wg)

    return {
        "expectedGust": round(sum(gusts)/len(gusts),1),
        "expectedSustained": round(sum(sust)/len(sust),1),
        "maxGust": round(max(gusts),1),
        "maxSustained": round(max(sust),1),
    }

def fallback_row(county):
    return WxRow(
        county=county.county,
        state=county.state,
        severity=1,
        expectedGust=0,
        expectedSustained=0,
        maxGust=0,
        maxSustained=0,
        probability=0.5,
        crews=1,
    )

def fetch_row_for_county(county, hours):
    try:
        pts = http_get_json(f"https://api.weather.gov/points/{county.lat},{county.lon}")
        hourly_url = pts.get("properties",{}).get("forecastHourly")
        if not hourly_url:
            return fallback_row(county)
        hourly = http_get_json(hourly_url)
        s = summarize_hours(hourly, hours)

        max_g = s["maxGust"]
        max_s = s["maxSustained"]

        if max_g >= 65 or max_s >= 45: sev=4
        elif max_g >= 50 or max_s >= 35: sev=3
        elif max_g >= 35 or max_s >= 25: sev=2
        else: sev=1

        prob = min(0.95, 0.5 + (max_g/100))

        crews = max(1, min(10, int(math.ceil(max_g/20))))

        return WxRow(
            county=county.county,
            state=county.state,
            severity=sev,
            expectedGust=s["expectedGust"],
            expectedSustained=s["expectedSustained"],
            maxGust=max_g,
            maxSustained=max_s,
            probability=round(prob,2),
            crews=crews,
        )
    except:
        # Never skip a county — return fallback
        return fallback_row(county)

# ---------------------------------------------------------------------------
# API route
# ---------------------------------------------------------------------------

@app.get("/api/wx")
def api_wx(
    mode: Mode = Query(...),
    hours: int = Query(6, ge=1, le=120),
    sample: int = Query(20, ge=1, le=50),
    region: Optional[str] = None,
    state: Optional[str] = None,
    county: Optional[str] = None,
):
    counties = filter_counties(mode, sample, region, state, county)
    rows=[]

    for c in counties:
        rows.append(fetch_row_for_county(c, hours))

    rows.sort(key=lambda r:(r.severity,r.maxGust,r.maxSustained), reverse=True)
    return [r.to_dict() for r in rows]
