Param(
    [string]$BackendPath = "C:\Users\JohnDonohue\dev\da-wx-backend"
)

Write-Host "Replacing build_state_rows_all_counties with tolerant version" -ForegroundColor Cyan

if (-not (Test-Path $BackendPath)) {
    Write-Host "Backend path not found: $BackendPath" -ForegroundColor Red
    exit 1
}

Set-Location $BackendPath

$backendFile = Join-Path $BackendPath "wx_live_backend.py"
if (-not (Test-Path $backendFile)) {
    Write-Host "wx_live_backend.py not found, exiting." -ForegroundColor Red
    exit 1
}

$text = [System.IO.File]::ReadAllText($backendFile)

$start = $text.IndexOf("async def build_state_rows_all_counties(")
if ($start -lt 0) {
    Write-Host "Could not find build_state_rows_all_counties definition, aborting." -ForegroundColor Red
    exit 1
}

$end = $text.IndexOf("async def all_counties_national", $start)
if ($end -lt 0) {
    Write-Host "Could not find all_counties_national after build_state_rows_all_counties, aborting." -ForegroundColor Red
    exit 1
}

$before = $text.Substring(0, $start)
$after  = $text.Substring($end)

$newFunc = @'
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

'@

$backup = "$backendFile.bak_relax2_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item $backendFile $backup -Force
Write-Host "Created backup: $backup" -ForegroundColor Green

$newText = $before + $newFunc + $after
[System.IO.File]::WriteAllText($backendFile, $newText)
Write-Host "Replaced build_state_rows_all_counties function." -ForegroundColor Green

# git add / commit / push
try {
    git add wx_live_backend.py | Out-Null
    git commit -m "Replace build_state_rows_all_counties with tolerant version" | Out-Null
} catch {
    Write-Host "git commit may have no changes or failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

try {
    git push | Out-Null
    Write-Host "git push completed. Check Render for new deploy." -ForegroundColor Green
} catch {
    Write-Host "git push failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "You may need to run 'git push' manually in $BackendPath." -ForegroundColor Yellow
}

Write-Host "Done updating build_state_rows_all_counties." -ForegroundColor Cyan
