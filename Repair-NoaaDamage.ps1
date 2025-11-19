Param(
    [string]$Root = "C:\Users\JohnDonohue\dev",
    [string]$BackendFolder = "da-wx-backend",
    [string]$FrontendFolder = "divergentalliance"
)

Write-Host "=== REPAIR NOAA DAMAGE START ===" -ForegroundColor Cyan

$backend = Join-Path $Root $BackendFolder
$frontend = Join-Path $Root $FrontendFolder

$targets = @(
    @{ Path = Join-Path $backend  "wx_live_backend.py";               Pattern = "wx_live_backend.py.bak_NOAA*" },
    @{ Path = Join-Path $frontend "lib\screens\weather_center.dart";  Pattern = "weather_center.dart.bak_NOAA*" },
    @{ Path = Join-Path $frontend "lib\screens\weather_center_results.dart"; Pattern = "weather_center_results.dart.bak_NOAA*" }
)

foreach ($t in $targets) {
    $filePath   = $t.Path
    $pattern    = $t.Pattern
    $dir        = Split-Path $filePath -Parent

    if (-not (Test-Path $filePath)) {
        Write-Host "WARNING: target file not found: $filePath" -ForegroundColor Yellow
        continue
    }

    $backup = Get-ChildItem -Path $dir -Filter $pattern -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1

    if ($backup -eq $null) {
        Write-Host "WARNING: no $pattern backup found next to $filePath" -ForegroundColor Yellow
        continue
    }

    $localBackup = "$filePath.bak_REVERT_$(Get-Date -Format yyyyMMdd_HHmmss)"
    Copy-Item $filePath $localBackup -Force
    Write-Host "Created safety backup: $localBackup" -ForegroundColor Gray

    Copy-Item $backup.FullName $filePath -Force
    Write-Host "Restored $filePath from $($backup.Name)" -ForegroundColor Green
}

Write-Host "=== REPAIR NOAA DAMAGE DONE ===" -ForegroundColor Cyan
Write-Host "Now run: flutter clean; flutter pub get; flutter run" -ForegroundColor Yellow
