Param(
    [string]$BackendPath = "C:\Users\JohnDonohue\dev\da-wx-backend"
)

Write-Host "`n=== FORCE BACKEND COUNTY ROUTE FIX ===" -ForegroundColor Cyan

Set-Location $BackendPath
$backendFile = "wx_live_backend.py"

if (-not (Test-Path $backendFile)) {
    Write-Host "ERROR: $backendFile NOT FOUND" -ForegroundColor Red
    exit 1
}

# Backup
$backup = "$backendFile.bak_FORCE_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item $backendFile $backup -Force
Write-Host "Backup created: $backup" -ForegroundColor Green

$content = Get-Content $backendFile -Raw

# REMOVE ANY EXISTING /report/county or /report/county2 BLOCKS
$content = $content -replace "(?ms)@app\.get\(\"/report/county.*?def .*?\n(.*?)\n}", ""
$content = $content -replace "(?ms)@app\.get\(\"/report/county2.*?def .*?\n(.*?)\n}", ""

# ADD NEW ROUTE AT BOTTOM OF FILE
$route = @"
@app.get("/report/county2")
async def report_county2(
    state: str = Query(...),
    county: str = Query(...),
    hours: int = Query(36),
    metric: str = Query("gust"),
    threshold: float = Query(0.0),
) -> List[Dict[str, Any]]:

    st = (state or "").upper()
    cname = (county or "").strip().lower()

    # NATIONAL CASE
    if st == "US" and cname in ("nationwide", "national", "us", ""):
        rows = await all_counties_national(
            hours=hours,
            metric=metric,
            threshold=threshold,
        )
        return rows

    # STATE CASE
    rows = await build_state_rows_all_counties(
        state_abbr=st,
        hours=hours,
        metric=metric,
        threshold=threshold,
    )

    out = []
    for r in rows:
        if str(r.get("county","")).lower() == cname:
            out.append(r)
    return out
"@

$new = $content + "`n`n" + $route
Set-Content $backendFile $new -NoNewline

Write-Host "[BACKEND] Injected /report/county2 route." -ForegroundColor Green

# GIT PUSH
try {
    git add $backendFile | Out-Null
    git commit -m "FORCE ADD /report/county2 working route" | Out-Null
    git push | Out-Null
    Write-Host "[GIT] PUSHED. Go to Render dashboard and wait for redeploy." -ForegroundColor Green
}
catch {
    Write-Host "[GIT] Push failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "=== DONE ===" -ForegroundColor Cyan
