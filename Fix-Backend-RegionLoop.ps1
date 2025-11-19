Param(
    [string]$BackendPath = "C:\Users\JohnDonohue\dev\da-wx-backend"
)

Write-Host "=== FIX BACKEND rows_for_region_sync START ===" -ForegroundColor Cyan

Set-Location $BackendPath

$pyPath = "wx_live_backend.py"
if (-not (Test-Path $pyPath)) {
    Write-Host "ERROR: $pyPath not found" -ForegroundColor Red
    exit 1
}

# Backup
$backup = "$pyPath.bak_REGIONLOOP_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item $pyPath $backup -Force
Write-Host "Backup created: $backup" -ForegroundColor Green

$old = @"
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
                limit=MAX_ROWS,
            )
        )
        allrows.extend(part)
        if len(allrows) >= MAX_ROWS:
            break

    allrows.sort(key=lambda x: x.get("maxGust", 0.0), reverse=True)
    return allrows[:MAX_ROWS]
"@

$new = @"
def rows_for_region_sync(
    region: str,
    hours: int,
    metric: str,
    threshold: float,
) -> List[Dict[str, Any]]:
    region_code = (region or "NE").upper()
    states = REGIONS.get(region_code, REGIONS["NE"])
    allrows: List[Dict[str, Any]] = []

    # Collect rows from all states in the region, then keep the top MAX_ROWS.
    for st in states:
        part = asyncio.run(
            build_state_rows_all_counties(
                state_abbr=st,
                hours=hours,
                metric=metric,
                threshold=threshold,
                limit=MAX_ROWS,
            )
        )
        allrows.extend(part)

    allrows.sort(key=lambda x: x.get("maxGust", 0.0), reverse=True)
    return allrows[:MAX_ROWS]
"@

$py = Get-Content $pyPath -Raw
if ($py.Contains($old)) {
    $py = $py.Replace($old, $new)
    Set-Content -Path $pyPath -Value $py -Encoding UTF8
    Write-Host "rows_for_region_sync patched to use all region states." -ForegroundColor Green
} else {
    Write-Host "WARNING: rows_for_region_sync pattern not found; no change applied." -ForegroundColor Yellow
}

Write-Host "=== FIX BACKEND rows_for_region_sync DONE ===" -ForegroundColor Cyan
