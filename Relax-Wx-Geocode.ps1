Param(
    [string]$BackendPath = "C:\Users\JohnDonohue\dev\da-wx-backend"
)

Write-Host "Relaxing geocode/wind failures in wx_live_backend.py" -ForegroundColor Cyan

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

$oldBlock = @"
            query_name = f"{county_name} County, {STATE_NAME.get(state_abbr, state_abbr)}"
            async with sem:
                g = await geocode(client, query_name)
                if not g:
                    return
                lat = g["lat"]
                lon = g["lon"]
                w = await live_wind(client, lat, lon, hh)
"@

$newBlock = @"
            query_name = f"{county_name} County, {STATE_NAME.get(state_abbr, state_abbr)}"
            async with sem:
                try:
                    g = await geocode(client, query_name)
                    if g and "lat" in g and "lon" in g:
                        lat = g["lat"]
                        lon = g["lon"]
                    else:
                        lat = 0.0
                        lon = 0.0
                    w = await live_wind(client, lat, lon, hh)
                except Exception:
                    # If anything fails, keep the county with zero winds
                    lat = 0.0
                    lon = 0.0
                    w = {"exp_sust": 0.0, "exp_gust": 0.0, "max_sust": 0.0, "max_gust": 0.0}
"@

if (-not $text.Contains($oldBlock)) {
    Write-Host "Did not find expected geocode/wind block. Aborting to avoid corrupting file." -ForegroundColor Red
    exit 1
}

$backup = "$backendFile.bak_relax_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item $backendFile $backup -Force
Write-Host "Created backup: $backup" -ForegroundColor Green

$newText = $text.Replace($oldBlock, $newBlock)
[System.IO.File]::WriteAllText($backendFile, $newText)
Write-Host "Replaced geocode/wind block with tolerant version." -ForegroundColor Green

# git push so Render redeploys
try {
    git add wx_live_backend.py | Out-Null
    git commit -m "Relax geocode/wind failures; keep counties with zeros" | Out-Null
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

Write-Host "Done relaxing geocode/wind failures." -ForegroundColor Cyan
