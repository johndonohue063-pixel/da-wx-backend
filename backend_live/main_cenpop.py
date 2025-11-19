import asyncio, time, os, csv
from typing import List, Dict, Tuple
import httpx
from fastapi import FastAPI, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime, timezone

OM_BASE = "https://api.open-meteo.com/v1/forecast"
CENPOP_FILES = ["CenPop2020_Mean_CO.txt", "CenPop2010_Mean_CO.txt"]  # local filenames to try first
CENPOP_URLS = [
    "https://www2.census.gov/geo/docs/reference/cenpop2020/county/CenPop2020_Mean_CO.txt",
    "https://www2.census.gov/geo/docs/reference/cenpop2010/county/CenPop2010_Mean_CO.txt",
]

REGION_STATES = {
  "Northeast": ["CT","ME","MA","NH","RI","VT","NJ","NY","PA"],
  "Midwest"  : ["IL","IN","MI","OH","WI","IA","KS","MN","MO","NE","ND","SD"],
  "South"    : ["DE","FL","GA","MD","NC","SC","VA","DC","WV","AL","KY","MS","TN","AR","LA","OK","TX"],
  "West"     : ["AZ","CO","ID","MT","NV","NM","UT","WY","AK","CA","HI","OR","WA"]
}

COUNTIES: List[Tuple[str,str,float,float,int]] = []  # (name, state, lat, lon, pop)
STATE_IDX: Dict[str, List[int]] = {}
CACHE: Dict[str, Tuple[float, List[Dict]]] = {}

app = FastAPI(title="Wx Live Counties (CenPop)")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

def now_iso(): return datetime.now(timezone.utc).isoformat()

@app.get("/health")
def health(): return {"status":"ok","countiesLoaded":len(COUNTIES)}

def _get(h: Dict[str,int], names: list):
    for n in names:
        if n in h: return h[n]
    raise KeyError(names[0])

def parse_cenpop(text: str) -> List[Tuple[str,str,float,float,int]]:
    """Accept either COUNAME|COUNTYNAME and STNAME|STATE; tolerate '+' in coords."""
    lines = text.splitlines()
    if not lines: return []
    reader = csv.reader(lines)
    header = next(reader)
    hmap = {name.strip().upper(): idx for idx, name in enumerate(header)}

    name_i = _get(hmap, ["COUNAME","COUNTYNAME"])
    st_i   = _get(hmap, ["STNAME","STATE"])
    lat_i  = _get(hmap, ["LATITUDE"])
    lon_i  = _get(hmap, ["LONGITUDE"])
    pop_i  = None
    for cand in ["POPULATION","POPESTIMATE","POP"]:
        if cand in hmap: pop_i = hmap[cand]; break

    out: List[Tuple[str,str,float,float,int]] = []
    for row in reader:
        try:
            nm = row[name_i].replace(" County","").replace(" Parish","").strip()
            st = row[st_i].strip().upper()
            if not nm or not st or len(st)!=2:  # USPS abbrev only
                continue
            lat_s = row[lat_i].strip().replace("+","")
            lon_s = row[lon_i].strip().replace("+","")
            la = float(lat_s); lo = float(lon_s)
            pop = 0
            if pop_i is not None:
                v = row[pop_i].strip()
                if v and v.replace(".","",1).isdigit():
                    pop = int(float(v))
            out.append((nm, st, la, lo, pop))
        except Exception:
            continue
    return out

async def load_counties():
    """Try local CenPop file(s), else attempt download; then build STATE index."""
    global COUNTIES, STATE_IDX
    if COUNTIES: return

    # 1) local files
    for fn in CENPOP_FILES:
        if os.path.exists(fn):
            try:
                with open(fn,"r",encoding="utf-8") as f:
                    data = parse_cenpop(f.read())
                if data:
                    COUNTIES = data
                    break
            except Exception:
                pass

    # 2) remote if still empty
    if not COUNTIES:
        async with httpx.AsyncClient(timeout=30) as c:
            for url in CENPOP_URLS:
                try:
                    r = await c.get(url); r.raise_for_status()
                    data = parse_cenpop(r.text)
                    if data:
                        COUNTIES = data
                        break
                except Exception:
                    continue

    STATE_IDX.clear()
    for i, (_, st, _, _, _) in enumerate(COUNTIES):
        STATE_IDX.setdefault(st, []).append(i)

async def live_wind(lat: float, lon: float, hours: int):
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
    return {"county":c,"state":s,"expectedGust":round(eg,1),"expectedSustained":round(es,1),
            "maxGust":round(mg,1),"maxSustained":round(ms,1),"probability":round(p,2),
            "crews":crews,"severity":sev,"confidence":conf,"population":pop,
            "generatedAt":now_iso(),"upstreamStamp":stamp,"source":"open-meteo"}

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
    m = (mode or "Nationwide").strip()
    if m == "Nationwide": return list(range(len(COUNTIES)))
    if m == "State" and state: return STATE_IDX.get(state.upper(), [])
    if m == "Regional" and region in REGION_STATES:
        allowed = set(REGION_STATES[region]); idx=[]
        for st in allowed: idx.extend(STATE_IDX.get(st,[]))
        return idx
    return []

def key(mode,region,state,hours,sample): return f"{mode}|{region}|{state}|{hours}|{sample}"

async def handle(mode: str, region: str, state: str, hours: int, sample: int, nocache: int):
    await load_counties()
    if not COUNTIES: return []
    hours  = max(6, min(72, hours or 24))
    sample = max(1, min(5000, sample or 200))
    idx = select_indices(mode, region, state)
    if not idx: return []
    idx = sorted(idx, key=lambda i: COUNTIES[i][4], reverse=True)
    if sample < len(idx): idx = idx[:sample]
    k = key(mode or "Nationwide", region or "", state or "", hours, sample)
    now = time.time()
    if not nocache:
        hit = CACHE.get(k)
        if hit and (now-hit[0]) < 600: return hit[1]
    rows = await compute(idx, hours)
    CACHE[k]=(now, rows)
    return rows

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
# === BEGIN FLEXIBLE FILE LOADER PATCH ===
import glob

# optional explicit path from environment
CENPOP_PATH = os.environ.get("CENPOP_PATH")  # absolute or relative to working dir

def _try_parse_file(path: str):
    try:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
        data = parse_cenpop(text)
        return data
    except Exception:
        return []

async def load_counties():
    """First try explicit env var file, then local CenPop defaults, then any *.txt that matches, finally remote URLs."""
    global COUNTIES, STATE_IDX
    if COUNTIES: return

    # 0) explicit file from env
    if CENPOP_PATH and os.path.exists(CENPOP_PATH):
        data = _try_parse_file(CENPOP_PATH)
        if data:
            COUNTIES = data

    # 1) local defaults
    if not COUNTIES:
        for fn in ["CenPop2020_Mean_CO.txt", "CenPop2010_Mean_CO.txt"]:
            if os.path.exists(fn):
                data = _try_parse_file(fn)
                if data:
                    COUNTIES = data
                    break

    # 2) any *.txt in folder that parses with required headers
    if not COUNTIES:
        for p in glob.glob("*.txt*"):
            data = _try_parse_file(p)
            if data:
                COUNTIES = data
                break

    # 3) remote if still empty
    if not COUNTIES:
        async with httpx.AsyncClient(timeout=30) as c:
            for url in CENPOP_URLS:
                try:
                    r = await c.get(url); r.raise_for_status()
                    data = parse_cenpop(r.text)
                    if data:
                        COUNTIES = data
                        break
                except Exception:
                    continue

    STATE_IDX.clear()
    for i, (_, st, _, _, _) in enumerate(COUNTIES):
        STATE_IDX.setdefault(st, []).append(i)
# === END FLEXIBLE FILE LOADER PATCH ===
# === BEGIN USPS MAP + PARSER OVERRIDE ===
STATE_NAME_TO_USPS = {
 "ALABAMA":"AL","ALASKA":"AK","ARIZONA":"AZ","ARKANSAS":"AR","CALIFORNIA":"CA","COLORADO":"CO","CONNECTICUT":"CT",
 "DELAWARE":"DE","DISTRICT OF COLUMBIA":"DC","FLORIDA":"FL","GEORGIA":"GA","HAWAII":"HI","IDAHO":"ID","ILLINOIS":"IL",
 "INDIANA":"IN","IOWA":"IA","KANSAS":"KS","KENTUCKY":"KY","LOUISIANA":"LA","MAINE":"ME","MARYLAND":"MD","MASSACHUSETTS":"MA",
 "MICHIGAN":"MI","MINNESOTA":"MN","MISSISSIPPI":"MS","MISSOURI":"MO","MONTANA":"MT","NEBRASKA":"NE","NEVADA":"NV",
 "NEW HAMPSHIRE":"NH","NEW JERSEY":"NJ","NEW MEXICO":"NM","NEW YORK":"NY","NORTH CAROLINA":"NC","NORTH DAKOTA":"ND",
 "OHIO":"OH","OKLAHOMA":"OK","OREGON":"OR","PENNSYLVANIA":"PA","RHODE ISLAND":"RI","SOUTH CAROLINA":"SC","SOUTH DAKOTA":"SD",
 "TENNESSEE":"TN","TEXAS":"TX","UTAH":"UT","VERMONT":"VT","VIRGINIA":"VA","WASHINGTON":"WA","WEST VIRGINIA":"WV",
 "WISCONSIN":"WI","WYOMING":"WY"
}

def parse_cenpop(text: str) -> List[Tuple[str,str,float,float,int]]:
    """Accept COUNAME|COUNTYNAME and STNAME|STATE; map STNAME full names to USPS codes."""
    import csv
    lines = text.splitlines()
    if not lines: return []
    reader = csv.reader(lines)
    header = next(reader)
    hmap = {name.strip().upper(): idx for idx, name in enumerate(header)}

    # required columns (flexible)
    def _get(h, names):
        for n in names:
            if n in h: return h[n]
        raise KeyError(names[0])

    name_i = _get(hmap, ["COUNAME","COUNTYNAME"])
    # choose state field present
    use_stname = "STNAME" in hmap
    st_i = hmap["STNAME"] if use_stname else _get(hmap, ["STATE"])
    lat_i = _get(hmap, ["LATITUDE"])
    lon_i = _get(hmap, ["LONGITUDE"])
    pop_i = None
    for cand in ["POPULATION","POPESTIMATE","POP"]:
        if cand in hmap: pop_i = hmap[cand]; break

    out: List[Tuple[str,str,float,float,int]] = []
    for row in reader:
        try:
            nm = row[name_i].replace(" County","").replace(" Parish","").strip()
            st_raw = row[st_i].strip()
            # map full name to USPS if needed
            if use_stname:
                st = STATE_NAME_TO_USPS.get(st_raw.upper(), "")
                if not st:
                    continue
            else:
                st = st_raw.upper()
                if len(st) != 2:
                    continue

            lat_s = row[lat_i].strip().replace("+","")
            lon_s = row[lon_i].strip().replace("+","")
            la = float(lat_s); lo = float(lon_s)
            pop = 0
            if pop_i is not None:
                v = row[pop_i].strip()
                # handle ints or floats in POPULATION
                try:
                    pop = int(float(v)) if v else 0
                except:
                    pop = 0
            out.append((nm, st, la, lo, pop))
        except Exception:
            continue
    return out
# === END USPS MAP + PARSER OVERRIDE ===
