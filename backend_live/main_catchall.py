import asyncio, time
from typing import List, Dict, Tuple
import httpx
from fastapi import FastAPI, Query, Request
from fastapi.middleware.cors import CORSMiddleware

OM_BASE = "https://api.open-meteo.com/v1/forecast"

REGION_STATES = {
  "Northeast": ["CT","ME","MA","NH","RI","VT","NJ","NY","PA"],
  "Midwest"  : ["IL","IN","MI","OH","WI","IA","KS","MN","MO","NE","ND","SD"],
  "South"    : ["DE","FL","GA","MD","NC","SC","VA","DC","WV","AL","KY","MS","TN","AR","LA","OK","TX"],
  "West"     : ["AZ","CO","ID","MT","NV","NM","UT","WY","AK","CA","HI","OR","WA"]
}

COUNTIES: List[Tuple[str,str,float,float,int]] = [
  # Northeast
  ("Kings","NY",40.6782,-73.9442,2583000),
  ("Queens","NY",40.7282,-73.7949,2320000),
  ("Philadelphia","PA",39.9526,-75.1652,1604000),
  # Midwest
  ("Cook","IL",41.8781,-87.6298,5217000),
  ("Wayne","MI",42.3314,-83.0458,1760000),
  # South
  ("Harris","TX",29.7604,-95.3698,4885000),
  ("Dallas","TX",32.7767,-96.7970,2635000),
  ("Miami-Dade","FL",25.7617,-80.1918,2715000),
  # West
  ("Los Angeles","CA",34.0522,-118.2437,10098000),
  ("San Diego","CA",32.7157,-117.1611,3330000),
  ("Maricopa","AZ",33.4484,-112.0740,4485000)
]

CACHE: Dict[str, Tuple[float, List[Dict]]] = {}

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

@app.get("/health")
def health(): return {"status":"ok"}

async def live_wind(lat: float, lon: float, hours: int):
  try:
    params = {"latitude":lat,"longitude":lon,"hourly":"windspeed_10m,windgusts_10m","forecast_days":3,"timezone":"UTC"}
    async with httpx.AsyncClient(timeout=20) as c:
      r = await c.get(OM_BASE, params=params)
      r.raise_for_status()
      j = r.json()
    g = j.get("hourly",{}).get("windgusts_10m",[]) or []
    w = j.get("hourly",{}).get("windspeed_10m",[]) or []
    if not g or not w: return (0,0,0,0,0)
    n = max(6,min(hours,len(g)))
    eg, es = sum(g[:n])/n, sum(w[:n])/n
    mg, ms = max(g), max(w)
    p = max(0.0, min(0.75, mg/100.0))
    return (eg, es, mg, ms, p)
  except Exception:
    return (0,0,0,0,0)

def row(c,s,eg,es,mg,ms,p,pop):
  sev = "3" if mg>=50 else ("2" if mg>=35 else "1")
  conf = int(min(100,max(0,p*100)))
  crews = int(max(1, round((p*(pop/100000.0))*10))) if pop>0 else int(max(1,round(p*10)))
  return {"county":c,"state":s,"expectedGust":round(eg,1),"expectedSustained":round(es,1),
          "maxGust":round(mg,1),"maxSustained":round(ms,1),"probability":round(p,2),
          "crews":crews,"severity":sev,"confidence":conf,"population":pop}

async def compute(indices: List[int], hours: int) -> List[Dict]:
  out: List[Dict] = []
  sem = asyncio.Semaphore(8)
  async def one(i:int):
    try:
      c,st,la,lo,pop = COUNTIES[i]
      async with sem:
        eg,es,mg,ms,p = await live_wind(la,lo,hours)
      out.append(row(c,st,eg,es,mg,ms,p,pop))
    except Exception:
      pass
  await asyncio.gather(*[one(i) for i in indices])
  out.sort(key=lambda r:(r["probability"], r["maxGust"]), reverse=True)
  return out

def select_indices(mode: str, region: str, state: str) -> List[int]:
  m = (mode or "Nationwide").strip()
  if m == "Nationwide": return list(range(len(COUNTIES)))
  if m == "State" and state:
    return [i for i,(_,S,_,_,_) in enumerate(COUNTIES) if S.upper()==state.upper()]
  if m == "Regional" and region:
    allowed = set(REGION_STATES.get(region, []))
    return [i for i,(_,S,_,_,_) in enumerate(COUNTIES) if S.upper() in allowed]
  # Default: give them something rather than empty
  return list(range(len(COUNTIES)))

def key(mode:str, region:str, state:str, hours:int) -> str:
  return f"{mode}|{region}|{state}|{hours}"

async def wx_core(mode: str, region: str, state: str, hours: int):
  try:
    h = max(6,min(72,(hours or 24)))
    idx = select_indices(mode, region, state)
    k  = key(mode or "Nationwide", region or "", state or "", h)
    now = time.time()
    if (hit := CACHE.get(k)) and (now-hit[0]) < 600: return hit[1]
    rows = await compute(idx, h)
    CACHE[k] = (now, rows)
    return rows
  except Exception:
    return []

# Primary endpoints
@app.get("/api/wx")
async def api_wx(req: Request, mode: str = "Nationwide", region: str = "", state: str = "", hours: int = 24):
  return await wx_core(mode, region, state, hours)

@app.get("/wx")
async def wx_alias(req: Request, mode: str = "Nationwide", region: str = "", state: str = "", hours: int = 24):
  return await wx_core(mode, region, state, hours)

# Catch-all: any GET path returns data using query params (or defaults)
@app.get("/{full_path:path}")
async def catch_all(req: Request, full_path: str, mode: str = "Nationwide", region: str = "", state: str = "", hours: int = 24):
  return await wx_core(mode, region, state, hours)
