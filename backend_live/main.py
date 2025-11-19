import asyncio, time
from typing import List, Dict, Tuple
import httpx
from fastapi import FastAPI, Query
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
  ("Miami-Dade","FL",25.7617,-80.1918,2715000),
  ("Dallas","TX",32.7767,-96.7970,2635000),
  # West
  ("Los Angeles","CA",34.0522,-118.2437,10098000),
  ("Maricopa","AZ",33.4484,-112.0740,4485000),
  ("San Diego","CA",32.7157,-117.1611,3330000)
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
    if not g or not w:
      return (0,0,0,0,0)
    n = max(6,min(hours,len(g)))
    eg, es = sum(g[:n])/n, sum(w[:n])/n
    mg, ms = max(g), max(w)
    p = max(0.0, min(0.75, mg/100.0))
    return (eg, es, mg, ms, p)
  except Exception as ex:
    # Return safe zeros on any per-county error
    return (0,0,0,0,0)
  async with httpx.AsyncClient(timeout=20) as c:
    r = await c.get(OM_BASE, params=params); r.raise_for_status(); j = r.json()
  g = j.get("hourly",{}).get("windgusts_10m",[]) or []
  w = j.get("hourly",{}).get("windspeed_10m",[]) or []
  if not g or not w: return (0,0,0,0,0)
  n = max(6,min(hours,len(g)))
  eg, es = sum(g[:n])/n, sum(w[:n])/n
  mg, ms = max(g), max(w)
  p = max(0.0, min(0.75, mg/100.0))
  return (eg, es, mg, ms, p)

def row(c,s,eg,es,mg,ms,p,pop):
  sev = "3" if mg>=50 else ("2" if mg>=35 else "1")
  conf = int(min(100,max(0,p*100)))
  crews = int(max(1, round((p*(pop/100000.0))*10))) if pop>0 else int(max(1,round(p*10)))
  return {"county":c,"state":s,"expectedGust":round(eg,1),"expectedSustained":round(es,1),
          "maxGust":round(mg,1),"maxSustained":round(ms,1),"probability":round(p,2),
          "crews":crews,"severity":sev,"confidence":conf,"population":pop}

async def compute_rows(indices: List[int], hours: int) -> List[Dict]:
  out: List[Dict] = []
  sem = asyncio.Semaphore(8)  # slightly lower concurrency
  async def one(i:int):
    try:
      c,st,la,lo,pop = COUNTIES[i]
      async with sem:
        eg,es,mg,ms,p = await live_wind(la,lo,hours)
      out.append(row(c,st,eg,es,mg,ms,p,pop))
    except Exception:
      # Skip failing county safely
      pass
  await asyncio.gather(*[one(i) for i in indices])
  out.sort(key=lambda r:(r["probability"], r["maxGust"]), reverse=True)
  return out

# Backward-compat alias if other code calls compute()
async def compute(indices: List[int], hours: int) -> List[Dict]:
  return await compute_rows(indices, hours)

async def wx_core(mode: str, region: str, state: str, hours: int):
  idx = handle_query(mode, region, state, hours)
  if not idx: return []
  key = cache_key(mode, region, state, max(6,min(72,hours or 24)))
  now = time.time()
  hit = CACHE.get(key)
  if hit and (now-hit[0]) < 600:
    return hit[1]
  rows = await compute(idx, max(6,min(72,hours or 24)))
  CACHE[key]=(now,rows)
  return rows

# Compat routes: /api/wx, /wx, and / return the same data
@app.get("/api/wx")
async def api_wx(mode: str = "Nationwide", region: str = "", state: str = "", hours: int = 24):
  return await wx_core(mode, region, state, hours)

@app.get("/wx")
async def wx_alias(mode: str = "Nationwide", region: str = "", state: str = "", hours: int = 24):
  return await wx_core(mode, region, state, hours)

@app.get("/")
async def root_wx(mode: str = "Nationwide", region: str = "", state: str = "", hours: int = 24):
  return await wx_core(mode, region, state, hours)
