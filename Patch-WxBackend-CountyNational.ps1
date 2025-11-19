Param(
    [string]$BackendPath = "C:\Users\JohnDonohue\dev\da-wx-backend"
)

Write-Host "=== PATCH WX BACKEND /report/county START ===" -ForegroundColor Cyan

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

if ($text.Contains('@app.get("/report/county")')) {
    Write-Host "[BACKEND] /report/county already exists, not adding a second one." -ForegroundColor Yellow
} else {
    $backup = "$backendFile.bak_county_$(Get-Date -Format yyyyMMdd_HHmmss)"
    Copy-Item $backendFile $backup -Force
    Write-Host "[BACKEND] Backup created: $backup" -ForegroundColor Green

    $shim = @'

@app.get("/report/county")
async def report_county(
    state: str = Query(...),
    county: str = Query(...),
    hours: int = Query(36),
    metric: str = Query("gust"),
    threshold: float = Query(0.0),
) -> List[Dict[str, Any]]:
    """
    Shim for existing client:
      - If state='US' and county='Nationwide' (or similar), return the national list.
      - Otherwise, return just the one matching county from rows_for_state.
    """
    st = (state or "").upper()
    cname = (county or "").strip().lower()

    # Special case: US / Nationwide triggers national list
    if st == "US" and cname in ("nationwide", "national", "us"):
        rows = await all_counties_national(hours=hours, metric=metric, threshold=threshold)
        return rows

    # Normal case: single county from the state list
    rows = await rows_for_state(st, hours, metric, threshold)
    out: List[Dict[str, Any]] = []
    for r in rows:
        rc = str(r.get("county", "")).strip().lower()
        if rc == cname:
            out.append(r)
    return out

'@

    # Append shim near the bottom, before any diag routes if present
    $insertMarker = "# === TEMP DIAG ROUTES ==="
    if ($text.Contains($insertMarker)) {
        $parts = $text.Split($insertMarker, 2)
        $newText = $parts[0] + "`n`n" + $shim + "`n" + $insertMarker + $parts[1]
    } else {
        $newText = $text + "`n`n" + $shim
    }

    [System.IO.File]::WriteAllText($backendFile, $newText)
    Write-Host "[BACKEND] Added /report/county shim to wx_live_backend.py" -ForegroundColor Green

    # git add/commit/push so Render redeploys
    try {
        git add wx_live_backend.py | Out-Null
        git commit -m "Add /report/county shim for US/Nationwide" | Out-Null
    } catch {
        Write-Host "[BACKEND] git commit warning: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    try {
        git push | Out-Null
        Write-Host "[BACKEND] git push completed. Check Render for new deploy." -ForegroundColor Green
    } catch {
        Write-Host "[BACKEND] git push failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "You can run 'git push' manually in $BackendPath if needed." -ForegroundColor Yellow
    }
}

Write-Host "=== PATCH WX BACKEND /report/county DONE ===" -ForegroundColor Cyan
