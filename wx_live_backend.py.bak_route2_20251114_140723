import asyncio
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Any

import httpx
from fastapi import FastAPI, Query

app = FastAPI(title="WX Live Backend", version="1.0")

# region sets matching the app
REGIONS: Dict[str, set[str]] = {
    "NE": {"ME","NH","VT","MA","RI","CT","NY","NJ","PA"},
    "MW": {"OH","MI","IN","IL","WI","MN","IA","MO","ND","SD","NE","KS"},
    "SO": {"DE","MD","DC","VA","WV","NC","SC","GA","FL","KY","TN","MS","AL","OK","TX","AR","LA"},
    "WE": {"MT","ID","WY","CO","NM","AZ","UT","NV","WA","OR","CA","AK","HI"},
}

STATE_NAME: Dict[str, str] = {
    "AL":"Alabama","AK":"Alaska","AZ":"Arizona","AR":"Arkansas","CA":"California","CO":"Colorado","CT":"Connecticut","DC":"District of Columbia","DE":"Delaware",
    "FL":"Florida","GA":"Georgia","HI":"Hawaii","IA":"Iowa","ID":"Idaho","IL":"Illinois","IN":"Indiana","KS":"Kansas","KY":"Kentucky","LA":"Louisiana",
    "MA":"Massachusetts","MD":"Maryland","ME":"Maine","MI":"Michigan","MN":"Minnesota","MO":"Missouri","MS":"Mississippi","MT":"Montana",
    "NC":"North Carolina","ND":"North Dakota","NE":"Nebraska","NH":"New Hampshire","NJ":"New Jersey","NM":"New Mexico","NV":"Nevada","NY":"New York",
    "OH":"Ohio","OK":"Oklahoma","OR":"Oregon","PA":"Pennsylvania","RI":"Rhode Island","SC":"South Carolina","SD":"South Dakota","TN":"Tennessee","TX":"Texas",
    "UT":"Utah","VA":"Virginia","VT":"Vermont","WA":"Washington","WI":"Wisconsin","WV":"West Virginia","WY":"Wyoming",
}

ABBR_TO_FIPS: Dict[str, str] = {
    "AL":"01","AK":"02","AZ":"04","AR":"05","CA":"06","CO":"08","CT":"09","DE":"10","DC":"11",
    "FL":"12","GA":"13","HI":"15","ID":"16","IL":"17","IN":"18","IA":"19","KS":"20","KY":"21",
    "LA":"22","ME":"23","MD":"24","MA":"25","MI":"26","MN":"27","MS":"28","MO":"29","MT":"30",
    "NE":"31","NV":"32","NH":"33","NJ":"34","NM":"35","NY":"36","NC":"37","ND":"38","OH":"39",
    "OK":"40","OR":"41","PA":"42","RI":"44","SC":"45","SD":"46","TN":"47","TX":"48","UT":"49",
    "VT":"50","VA":"51","WA":"53","WV":"54","WI":"55","WY":"56","PR":"72",
}


async def fetch_json(client: httpx.AsyncClient, url: str) -> Any:
    r = await client.get(url, timeout=20)
    r.raise_for_status()
    return r.json()


async def census_counties(client: httpx.AsyncClient, state_abbr: str) -> List[Dict[str, Any]]:
    """
    Return [{"county": ..., "state": "TX", "population": int}, ...] for the given state.
    Try Census PEP first, then ACS if needed.
    """
    state_abbr = (state_abbr or "").upper()
    st_fips = ABBR_TO_FIPS.get(state_abbr)
    if not st_fips:
        return []

    pep_years = ["2023", "2022", "2021", "2020", "2019"]
    acs_years = ["2023", "2022", "2021", "2020", "2019"]

    attempts: List[Dict[str, str]] = []
    for yr in pep_years:
        attempts.append({
            "url": f"https://api.census.gov/data/{yr}/pep/population?get=NAME,POP&for=county:*&in=state:{st_fips}",
            "field": "POP",
        })
    for yr in acs_years:
        attempts.append({
            "url": f"https://api.census.gov/data/{yr}/acs/acs5?get=NAME,B01003_001E&for=county:*&in=state:{st_fips}",
            "field": "B01003_001E",
        })

    out: List[Dict[str, Any]] = []
    for att in attempts:
        try:
            data = await fetch_json(client, att["url"])
        except Exception:
            data = None
        if not data or len(data) < 2:
            continue

        header = data[0]
        rows = data[1:]

        try:
            pop_idx = header.index(att["field"])
        except Exception:
            pop_idx = -1
        if pop_idx < 0:
            continue

        name_idx = 0
        tmp: List[Dict[str, Any]] = []
        for row in rows:
            if not row or len(row) <= pop_idx:
                continue
            name = row[name_idx]
            pop_val = row[pop_idx]
            try:
                pop_i = int(pop_val)
            except Exception:
                pop_i = 0

            county_name = (
                name.split(",")[0]
                .replace(" County", "")
                .replace(" Parish", "")
                .replace(" Borough", "")
                .replace(" Census Area", "")
                .strip()
            )
            tmp.append({"county": county_name, "state": state_abbr, "population": pop_i})

        if tmp:
            out = sorted(tmp, key=lambda x: x["population"], reverse=True)
            return out

    return out


async def geocode(client: httpx.AsyncClient, q: str) -> Dict[str, float] | None:
    """
    Geocode with Open Meteo.
    Returns {"lat": float, "lon": float} or None.
    """
    q = (q or "").strip()
    if not q:
        return None

    county_part = q
    st_abbr = ""
    if "," in q:
        pieces = [p.strip() for p in q.split(",")]
        if len(pieces) >= 2:
            county_part = pieces[0]
            st_abbr = pieces[1].split(" ")[0].upper()

    county_core = (
        county_part.replace(" County", "")
        .replace(" Parish", "")
        .replace(" Borough", "")
        .strip()
    )
    state_full = STATE_NAME.get(st_abbr, "")

    candidates: List[str] = []
    seen = set()

    def add_candidate(s: str) -> None:
        k = s.strip()
        if k and k not in seen:
            seen.add(k)
            candidates.append(k)

    if q:
        add_candidate(q)
    if county_core and st_abbr:
        add_candidate(f"{county_core} County, {st_abbr}")
        add_candidate(f"{county_core}, {st_abbr}")
        add_candidate(f"{county_core} {st_abbr}, USA")
    if county_core and state_full:
        add_candidate(f"{county_core} County, {state_full}")
        add_candidate(f"{county_core}, {state_full}")
    if county_core:
        add_candidate(county_core)
        add_candidate(f"{county_core}, USA")

    async def try_one(name: str) -> Dict[str, float] | None:
        from urllib.parse import quote

        key = quote(name)
        url = f"https://geocoding-api.open-meteo.com/v1/search?name={key}&count=1&language=en&format=json"
        try:
            data = await fetch_json(client, url)
        except Exception:
            return None
        if not isinstance(data, dict):
            return None
        results = data.get("results") or []
        if not results:
            return None
        top = results[0]
        lat = top.get("latitude")
        lon = top.get("longitude")
        if lat is None or lon is None:
            return None
        return {"lat": float(lat), "lon": float(lon)}

    for name in candidates:
        res = await try_one(name)
        if res:
            return res

    return None


def pick_window_slice(times: List[str], hours: int) -> tuple[int, int]:
    """
    Normalize timestamps to UTC and return indices covering the next hours window.
    """
    def _parse(ts: str):
        if not isinstance(ts, str):
            return None
        t = ts.strip()
        if not t:
            return None
        t2 = t.replace("Z", "+00:00")
        try:
            dt_val = datetime.fromisoformat(t2)
        except Exception:
            try:
                dt_val = datetime.strptime(t, "%Y-%m-%dT%H:%M")
            except Exception:
                return None
        if dt_val.tzinfo is None:
            dt_val = dt_val.replace(tzinfo=timezone.utc)
        else:
            try:
                dt_val = dt_val.astimezone(timezone.utc)
            except Exception:
                dt_val = dt_val.replace(tzinfo=timezone.utc)
        return dt_val

    now = datetime.utcnow().replace(tzinfo=timezone.utc)
    try:
        H = int(hours)
    except Exception:
        H = 24
    if H <= 0:
        H = 1
    end = now + timedelta(hours=H)

    parsed = [_parse(x) for x in list(times or [])]
    if not parsed or all(p is None for p in parsed):
        return 0, min(len(times), H)

    start_idx = 0
    for i, dt_val in enumerate(parsed):
        if dt_val is not None and dt_val >= now:
            start_idx = i
            break

    end_idx = len(parsed)
    for j in range(len(parsed) - 1, -1, -1):
        dt_val = parsed[j]
        if dt_val is not None and dt_val <= end:
            end_idx = j + 1
            break

    if start_idx >= end_idx:
        return 0, min(len(times), H)
    return start_idx, end_idx


async def live_wind(client: httpx.AsyncClient, lat: float, lon: float, hours: int) -> Dict[str, float]:
    """
    Use Open Meteo hourly wind speed and gust, then derive expected and max values
    over the requested window.
    """
    url = (
        "https://api.open-meteo.com/v1/forecast"
        f"?latitude={lat}&longitude={lon}"
        "&hourly=wind_speed_10m,wind_gusts_10m"
        "&forecast_days=3&timezone=UTC"
    )
    j = await fetch_json(client, url)
    h = (j or {}).get("hourly") or {}
    times = h.get("time") or []
    wspd = h.get("wind_speed_10m") or []
    wgst = h.get("wind_gusts_10m") or []

    i0, i1 = pick_window_slice(times, hours)
    if i1 <= i0:
        return {"exp_sust": 0.0, "exp_gust": 0.0, "max_sust": 0.0, "max_gust": 0.0}

    sp = wspd[i0:i1]
    gs = wgst[i0:i1]
    if not sp or not gs:
        return {"exp_sust": 0.0, "exp_gust": 0.0, "max_sust": 0.0, "max_gust": 0.0}

    try:
        sp_vals = [float(x) for x in sp]
        gs_vals = [float(x) for x in gs]
    except Exception:
        return {"exp_sust": 0.0, "exp_gust": 0.0, "max_sust": 0.0, "max_gust": 0.0}

    avg_sust = sum(sp_vals) / len(sp_vals)
    avg_gust = sum(gs_vals) / len(gs_vals)
    max_sust = max(sp_vals)
    max_gust = max(gs_vals)

    return {"exp_sust": avg_sust, "exp_gust": avg_gust, "max_sust": max_sust, "max_gust": max_gust}


def severity(eg: float, es: float) -> str:
    if eg >= 75 or es >= 45:
        return "Level 4"
    if eg >= 58 or es >= 35:
        return "Level 3"
    if eg >= 45 or es >= 25:
        return "Level 2"
    if eg >= 30 or es >= 18:
        return "Level 1"
    return "Level 0"


def crews(pop: int, p: float, eg: float, es: float) -> int:
    raw = pop * p * 0.002
    bump = 1.0
    if eg >= 58:
        bump += 0.35
    elif eg >= 45:
        bump += 0.2
    elif eg >= 30:
        bump += 0.1
    if es >= 35:
        bump += 0.2
    elif es >= 25:
        bump += 0.1
    c = int(round(raw * bump))
    if pop >= 2000000:
        c = int(round(c * 0.85))
    elif pop >= 1000000:
        c = int(round(c * 0.90))
    return max(0, min(c, 99999))


def probability(eg: float, es: float) -> float:
    # heuristic between about 0.05 and 0.85
    val = (eg - 28.0) / 100.0 + (es - 20.0) / 200.0
    val = max(0.05, val)
    val = min(0.85, val)
    return float(val)


async def build_state_rows_all_counties(
    state_abbr: str,
    hours: int = 36,
    metric: str = "gust",
    threshold: float | None = None,
) -> List[Dict[str, Any]]:
    """
    Build rows for all counties in a state using census_counties, geocode, live_wind.
    Tolerant of geocode/wind failures; keeps counties with zero winds rather than dropping them.
    Output uses camelCase keys for wind values:
      expectedGust, expectedSustained, maxGust, maxSustained
    """
    state_abbr = (state_abbr or "").upper()
    if not state_abbr:
        return []

    try:
        hh = int(hours)
    except Exception:
        hh = 36

    try:
        th = float(threshold) if threshold is not None else 0.0
    except Exception:
        th = 0.0

    metric = (metric or "gust").lower()
    out: List[Dict[str, Any]] = []

    async with httpx.AsyncClient(timeout=20) as client:
        counties = await census_counties(client, state_abbr)
        if not counties:
            return []

        sem = asyncio.Semaphore(8)

        async def _one(c: Dict[str, Any]) -> None:
            try:
                county_name = str(c.get("county", "")).strip()
                if not county_name:
                    return

                query_name = f"{county_name} County, {STATE_NAME.get(state_abbr, state_abbr)}"
                async with sem:
                    try:
                        g = await geocode(client, query_name)
                        if g and "lat" in g and "lon" in g:
                            lat = float(g["lat"])
                            lon = float(g["lon"])
                        else:
                            lat = 0.0
                            lon = 0.0
                        w = await live_wind(client, lat, lon, hh)
                    except Exception:
                        # If anything fails, keep the county with zero winds
                        lat = 0.0
                        lon = 0.0
                        w = {"exp_sust": 0.0, "exp_gust": 0.0, "max_sust": 0.0, "max_gust": 0.0}

                eg = float(w.get("exp_gust", 0.0) or 0.0)
                es = float(w.get("exp_sust", 0.0) or 0.0)
                mg = float(w.get("max_gust", 0.0) or 0.0)
                ms = float(w.get("max_sust", 0.0) or 0.0)

                focus = eg if metric == "gust" else es
                if th > 0.0 and focus < th:
                    return

                pop = int(c.get("population", 0) or 0)
                p = probability(eg, es)
                sev = severity(eg, es)
                crew_count = crews(pop, p, eg, es)

                row: Dict[str, Any] = {
                    "county": county_name,
                    "state": state_abbr,
                    "population": pop,
                    "lat": float(lat),
                    "lon": float(lon),
                    "expectedGust": eg,
                    "expectedSustained": es,
                    "maxGust": mg,
                    "maxSustained": ms,
                    "probability": p,
                    "severity": sev,
                    "crews": crew_count,
                }
                # legacy aliases for WCP client
                row["expGust"] = eg
                row["expSust"] = es
                row["maxGust"] = mg
                row["maxSust"] = ms
                row["crewCount"] = crew_count
                row["threatLevel"] = sev

                out.append(row)
            except Exception:
                return

        await asyncio.gather(*[_one(c) for c in counties])

    out.sort(key=lambda r: r.get("population", 0), reverse=True)
    return out
async def all_counties_national(
    hours: int = 36,
    metric: str = "gust",
    threshold: float | None = None,
) -> List[Dict[str, Any]]:
    """
    Nationwide, every county.
    Flat list of rows in the same shape as build_state_rows_all_counties.
    """
    rows: List[Dict[str, Any]] = []
    for st in STATE_NAME.keys():
        try:
            part = await build_state_rows_all_counties(st, hours, metric, threshold)
        except Exception:
            part = []
        if part:
            rows.extend(part)

    rows.sort(key=lambda r: r.get("population", 0), reverse=True)
    return rows


async def rows_for_state(
    state: str,
    hours: int | None,
    metric: str | None,
    threshold: float | None,
) -> List[Dict[str, Any]]:
    return await build_state_rows_all_counties(
        state_abbr=state,
        hours=hours or 36,
        metric=metric or "gust",
        threshold=threshold,
    )


def rows_for_region_sync(
    region: str,
    hours: int,
    metric: str,
    threshold: float,
) -> List[Dict[str, Any]]:
    region_code = (region or "NE").upper()
    states = REGIONS.get(region_code, REGIONS["NE"])
    allrows: List[Dict[str, Any]] = []

    for st in states:
        part = asyncio.run(
            build_state_rows_all_counties(
                state_abbr=st,
                hours=hours,
                metric=metric,
                threshold=threshold,
            )
        )
        allrows.extend(part)

    allrows.sort(key=lambda x: x.get("population", 0), reverse=True)
    return allrows


@app.get("/report/state")
async def report_state(
    state: str = Query(...),
    hours: int = Query(36),
    metric: str = Query("gust"),
    threshold: float = Query(0.0),
) -> List[Dict[str, Any]]:
    return await rows_for_state(state, hours, metric, threshold)


@app.get("/report/region")
def report_region(
    region: str = Query("NE"),
    hours: int = Query(36),
    metric: str = Query("gust"),
    threshold: float = Query(0.0),
) -> List[Dict[str, Any]]:
    return rows_for_region_sync(region, hours, metric, threshold)


@app.get("/report/national")
async def report_national(
    hours: int = Query(36),
    metric: str = Query("gust"),
    threshold: float = Query(0.0),
) -> List[Dict[str, Any]]:
    return await all_counties_national(hours, metric, threshold)


# Optional small diagnostics

@app.get("/__diag_census")
async def __diag_census(state: str = "TX"):
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            rows = await census_counties(client, state)
    except Exception:
        rows = []
    return {"state": state, "count": len(rows), "sample": rows[:5]}


@app.get("/__diag_geocode")
async def __diag_geocode(q: str = Query(..., description="Place to geocode")):
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            res = await geocode(client, q)
    except Exception:
        res = None
    return {"q": q, "result": res}




# --- WCP SHIMS ADDED BY MASTER-FIX-WX ---
# --- WCP SHIMS ADDED BY MASTER-FIX-WX ---



@app.get("/report/county")
async def report_county(
    state: str = Query(...),
    county: str = Query(...),
    hours: int = Query(36),
    metric: str = Query("gust"),
    threshold: float = Query(0.0),
) -> List[Dict[str, Any]]:
    """
    Client compatibility shim:
      - If state='US' and county is 'Nationwide' (or similar), return the national list.
      - Otherwise, return the matching county from the state-level rows.
    """
    st = (state or "").upper()
    cname = (county or "").strip().lower()

    # Special case: US / Nationwide triggers national output
    if st == "US" and cname in ("nationwide", "national", "us"):
        rows = await all_counties_national(
            hours=hours,
            metric=metric,
            threshold=threshold,
        )
        return rows

    # Normal case: get all rows for that state and filter by county name
    rows = await rows_for_state(
        state=st,
        hours=hours,
        metric=metric,
        threshold=threshold,
    )

    out: List[Dict[str, Any]] = []
    for r in rows:
        rc = str(r.get("county", "")).strip().lower()
        if rc == cname:
            out.append(r)
    return out

@app.get("/wcp/region")
def wcp_region(
    region: str = Query("NE"),
    hours: int = Query(36),
    metric: str = Query("gust"),
    threshold: float = Query(0.0),
):
    # Delegate to existing region report
    return report_region(region=region, hours=hours, metric=metric, threshold=threshold)


@app.get("/wcp/state")
async def wcp_state(
    state: str = Query(...),
    hours: int = Query(36),
    metric: str = Query("gust"),
    threshold: float = Query(0.0),
):
    return await report_state(state=state, hours=hours, metric=metric, threshold=threshold)


@app.get("/wcp/national")
async def wcp_national(
    hours: int = Query(36),
    metric: str = Query("gust"),
    threshold: float = Query(0.0),
):
    return await report_national(hours=hours, metric=metric, threshold=threshold)


if __name__ == "__main__":
    async def _demo():
        rows = await all_counties_national(hours=12, metric="gust", threshold=0.0)
        print("Total county rows:", len(rows))
        if rows:
            import json
            print(json.dumps(rows[0], indent=2))

    asyncio.run(_demo())
