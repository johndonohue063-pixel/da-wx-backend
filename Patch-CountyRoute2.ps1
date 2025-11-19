Param(
    [string]$AppPath    = "C:\Users\JohnDonohue\dev\divergentalliance",
    [string]$BackendPath = "C:\Users\JohnDonohue\dev\da-wx-backend"
)

Write-Host "=== PATCH COUNTY ROUTE2 START ===" -ForegroundColor Cyan

# -------------------------
# Patch backend: wx_live_backend.py
# -------------------------
Set-Location $BackendPath
$backendFile = "wx_live_backend.py"
if (-not (Test-Path $backendFile)) {
    Write-Host "ERROR: $backendFile not found in $BackendPath" -ForegroundColor Red
    exit 1
}

$backendBackup = "$backendFile.bak_route2_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item $backendFile $backendBackup -Force
Write-Host "[BACKEND] Backup: $backendBackup" -ForegroundColor Green

$backendText = [System.IO.File]::ReadAllText($backendFile)

if ($backendText.Contains('app.get("/report/county2")')) {
    Write-Host "[BACKEND] /report/county2 already exists, skipping append." -ForegroundColor Yellow
} else {
    $route2 = @"
@app.get("/report/county2")
async def report_county2(
    state: str = Query(...),
    county: str = Query(...),
    hours: int = Query(36),
    metric: str = Query("gust"),
    threshold: float = Query(0.0),
) -> List[Dict[str, Any]]:
    """
    New county route used by mobile app.
    Uses existing builders to get data:
      - state='US' and county ~ 'Nationwide' returns all US counties.
      - otherwise returns matching county rows from that state.
    """
    st = (state or "").upper()
    cname = (county or "").strip().lower()

    # Special national case
    if st == "US" and cname in ("nationwide", "national", "us", ""):
        rows = await all_counties_national(
            hours=hours,
            metric=metric,
            threshold=threshold,
        )
        return rows

    # State-level rows, then filter by county name
    rows = await build_state_rows_all_counties(
        state_abbr=st,
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

"@

    $backendText = $backendText + "`n`n" + $route2
    [System.IO.File]::WriteAllText($backendFile, $backendText)
    Write-Host "[BACKEND] Appended /report/county2 route." -ForegroundColor Green

    # Commit + push so Render redeploys
    try {
        git add $backendFile | Out-Null
        git commit -m "Add /report/county2 for mobile client" | Out-Null
    } catch {
        Write-Host "[BACKEND] git commit notice: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    try {
        git push | Out-Null
        Write-Host "[BACKEND] git push OK. Check Render for new deploy." -ForegroundColor Green
    } catch {
        Write-Host "[BACKEND] git push failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "If needed, run 'git push' manually in $BackendPath." -ForegroundColor Yellow
    }
}

# -------------------------
# Patch app: wcp_api.dart -> use /report/county2
# -------------------------
Set-Location $AppPath
$wcpFile = "lib\services\wcp_api.dart"
if (-not (Test-Path $wcpFile)) {
    Write-Host "ERROR: $wcpFile not found in $AppPath" -ForegroundColor Red
    exit 1
}

$wcpBackup = "$wcpFile.bak_route2_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item $wcpFile $wcpBackup -Force
Write-Host "[APP] Backup: $wcpBackup" -ForegroundColor Green

$wcpText = [System.IO.File]::ReadAllText($wcpFile)

# Replace only the path portion, keep the $state/$county variables intact
$wcpText = $wcpText.Replace("report/county?state=`$state&county=`$county",
                            "report/county2?state=`$state&county=`$county")

[System.IO.File]::WriteAllText($wcpFile, $wcpText)
Write-Host "[APP] Updated RealWxProvider to call /report/county2." -ForegroundColor Green

Write-Host "=== PATCH COUNTY ROUTE2 DONE ===" -ForegroundColor Cyan
