import asyncio, time, os
from typing import List, Dict, Tuple
import httpx
from fastapi import FastAPI, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime, timezone

# ---------- CONFIG ----------
OM_BASE = "https://api.open-meteo.com/v1/forecast"
GAZ_CANDIDATES = [
    "https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2023_Gazetteer/2023_Gaz_counties_national.txt",
    "https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2022_Gazetteer/2022_Gaz_counties_national.txt",
    "https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2021_Gazetteer/2021_Gaz_counties_national.txt",
    "https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2020_Gazetteer/2020_Gaz_counties_national.txt",
]
LOCAL_FALLBACK = "counties_gazetteer.txt"  # optional: drop a copy here to bypass network
# Strict Census-style regions
REGION_STATES = {
    "Northeast": ["CT","ME","MA","NH","RI","VT","NJ","NY","PA"],
    "Midwest"  : ["IL","IN","MI","OH","WI","IA","KS","MN","MO","NE","ND","SD"],
    "South"    : ["DE","FL","GA","MD","NC","SC","VA","DC","WV","AL","KY","MS","TN","AR","LA","OK","TX"],
    "West"     : ["AZ","CO","ID","MT","NV","NM","UT","WY","AK","CA","HI","OR","WA"],
}
# ---------------------------

COUNTIES: List[Tuple[str,str,float,float,int]] = []  # (name, state, lat, lon, pop)
STATE_IDX: Dict[str, List[int]] = {}
CACHE: Dict[str, Tuple[float, List[Dict]]] = {}

app = FastAPI(title="Wx Full Counties")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()

@app.get("/health")
def health():
    return {"status":"ok", "countiesLoaded": len(COUNTIES)}

def parse_gazetteer(text: str) -> List[Tuple[str,str,float,float,int]]:
    lines = text.splitlines()
    if not lines: return []
    hdr = lines[0].split("\t")
    # required fields
    name_i = hdr.index("NAME")
    st_i   = hdr.index("USPS")
    lat_i  = hdr.index("INTPTLAT")
    lon_i  = hdr.index("INTPTLONG")
    pop_i  = hdr.index("POPULATION") if "POPULATION" in hdr else None
    out: List[Tuple[str,str,float,float,int]] = []
    for ln in lines[1:]:
        parts = ln.split("\t")
        try:
            nm = parts[name_i].replace(" County","").replace(" Parish","")
            st = parts[st_i].upper()
            la = float(parts[lat_i]); lo = float(parts[lon_i])
            pop = int(parts[pop_i]) if pop_i is not None and parts[pop_i].isdigit() else 0
            out.append((nm, st, la, lo, pop))
        except Exception:
            continue
    return out

async def load_counties() -> None:
    """Load full county list from any working Gazetteer or local file; build STATE_IDX."""
    global COUNTIES, STATE_IDX
    if COUNTIES: return
    # try remote
    async with httpx.AsyncClient(timeout=30) as c:
        for url in GAZ_CANDIDATES:
            try:
                r = await c.get(url)
                r.raise_for_status()
                data = parse_gazetteer(r.text)
                if data:
                    COUNTIES = data
                    break
            except Exception:
                continue
    # try local fallback
    if not COUNTIES and os.path.exists(LOCAL_FALLBACK):
        try:
            with open(LOCAL_FALLBACK, "r", encoding="utf-8") as f:
                data = parse_gazetteer(f.read())
            if data:
                COUNTIES = data
        except Exception:
            pass
    # build index
    STATE_IDX.clear()
    for i, (_, st, _, _, _) in enumerate(COUNTIES):
        STATE_IDX.setdefault(st, []).append(i)

async def live_wind(lat: float, lon: float, hours: int):
    """Pull live hourly winds; never raise; returns (eg, es, mg, ms, p, upstreamStamp)."""
    try:
        params = {"latitude":lat,"longitude":lon,"hourly":"windspeed_10m,windgusts_10m","forecast_days":3,"timezone":"UTC"}
        async with httpx.AsyncClient(timeout=20) as c:
            r = await c.get(OM_BASE, params=params); r.raise_for_status(); j = r.json()
        g = j.get("hourly",{}).get("windgusts_10m",[]) or []
        w = j.get("hourly",{}).get("windspeed_10m",[]) or []
        t = j.get("hourly",{}).get("time",[]) or []
        if not g or not w: return (0,0,0,0,0, now_iso())
        n = max(6, min(hours, len(g)))
        eg, es = sum(g[:n])/n, sum(w[:n])/n
        mg, ms = max(g), max(w)
        p = max(0.0, min(0.75, mg/100.0))
        stamp = t[0] if t else now_iso()
        return (eg, es, mg, ms, p, stamp)
    except Exception:
        return (0,0,0,0,0, now_iso())

def mk_row(c,s,eg,es,mg,ms,p,pop,stamp):
    sev = "3" if mg>=50 else ("2" if mg>=35 else "1")
    conf = int(min(100, max(0, p*100)))
    crews = int(max(1, round((p*(pop/100000.0))*10))) if pop>0 else int(max(1, round(p*10)))
    return {
        "county": c, "state": s,
        "expectedGust": round(eg,1), "expectedSustained": round(es,1),
        "maxGust": round(mg,1), "maxSustained": round(ms,1),
        "probability": round(p,2), "crews": crews,
        "severity": sev, "confidence": conf, "population": pop,
        "generatedAt": now_iso(), "upstreamStamp": stamp, "source":"open-meteo"
    }

async def compute(indices: List[int], hours: int) -> List[Dict]:
    out: List[Dict] = []
    sem = asyncio.Semaphore(8)
    async def one(i:int):
        try:
            c,st,la,lo,pop = COUNTIES[i]
            async with sem:
                eg,es,mg,ms,p,stamp = await live_wind(la,lo,hours)
            out.append(mk_row(c,st,eg,es,mg,ms,p,pop,stamp))
        except Exception:
            pass
    await asyncio.gather(*[one(i) for i in indices])
    out.sort(key=lambda r:(r["probability"], r["maxGust"]), reverse=True)
    return out

def select_indices(mode: str, region: str, state: str) -> List[int]:
    """Strict region filter using Census lists; state filter uses exact USPS."""
    m = (mode or "Nationwide").strip()
    if m == "Nationwide":
        return list(range(len(COUNTIES)))
    if m == "State" and state:
        return STATE_IDX.get(state.upper(), [])
    if m == "Regional" and region in REGION_STATES:
        allowed = set(REGION_STATES[region])
        idx: List[int] = []
        for st in allowed:
            idx.extend(STATE_IDX.get(st, []))
        return idx
    return []

def cache_key(mode,region,state,hours,sample): return f"{mode}|{region}|{state}|{hours}|{sample}"

async def handle(mode: str, region: str, state: str, hours: int, sample: int, nocache: int):
    await load_counties()
    if not COUNTIES: return []
    hours  = max(6, min(72, hours or 24))
    sample = max(1, min(5000, sample or 200))  # default 200 rows

    idx = select_indices(mode, region, state)
    if not idx: return []
    # prioritize by population
    idx = sorted(idx, key=lambda i: COUNTIES[i][4], reverse=True)
    if sample < len(idx): idx = idx[:sample]

    k = cache_key(mode or "Nationwide", region or "", state or "", hours, sample)
    now = time.time()
    if not nocache:
        hit = CACHE.get(k)
        if hit and (now-hit[0]) < 600: return hit[1]

    rows = await compute(idx, hours)
    CACHE[k]=(now, rows)
    return rows

# Proper route definitions (no lambda/req issue)
from fastapi import Request

@app.get("/api/wx")
async def api_wx(request: Request,
                 mode: str = "Nationwide",
                 region: str = "",
                 state: str = "",
                 hours: int = 24,
                 sample: int = 200,
                 nocache: int = 0):
    return await handle(mode, region, state, hours, sample, nocache)

@app.get("/wx")
async def wx_alias(request: Request,
                   mode: str = "Nationwide",
                   region: str = "",
                   state: str = "",
                   hours: int = 24,
                   sample: int = 200,
                   nocache: int = 0):
    return await handle(mode, region, state, hours, sample, nocache)

@app.get("/{full_path:path}")
async def catch_all(request: Request, full_path: str,
                    mode: str = "Nationwide",
                    region: str = "",
                    state: str = "",
                    hours: int = 24,
                    sample: int = 200,
                    nocache: int = 0):
    return await handle(mode, region, state, hours, sample, nocache)

@app.on_event("startup")
async def init():
    await load_counties()
