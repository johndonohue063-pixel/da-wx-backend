Param(
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance"
)

Write-Host "=== FIX WCP API LOG URI LINE START ===" -ForegroundColor Cyan

if (-not (Test-Path $AppPath)) {
    Write-Host "App path does not exist: $AppPath" -ForegroundColor Red
    exit 1
}

Set-Location $AppPath

$wcpPath = Join-Path $AppPath "lib\services\wcp_api.dart"
if (-not (Test-Path $wcpPath)) {
    Write-Host "wcp_api.dart not found at $wcpPath" -ForegroundColor Red
    exit 1
}

$text = [System.IO.File]::ReadAllText($wcpPath)

# The broken line we created
$broken = "    debugPrint('WCP backend call: \');"

if (-not $text.Contains($broken)) {
    Write-Host "Broken debugPrint line not found; nothing to fix." -ForegroundColor Yellow
    Write-Host "=== FIX WCP API LOG URI LINE DONE (NO CHANGES) ===" -ForegroundColor Cyan
    exit 0
}

$backup = "$wcpPath.bak_fixlog_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item $wcpPath $backup -Force
Write-Host "Backup created: $backup" -ForegroundColor Green

$fixed = "    debugPrint('WCP backend call: \$uri');"
$text = $text.Replace($broken, $fixed)

[System.IO.File]::WriteAllText($wcpPath, $text)
Write-Host "Replaced broken debugPrint with: $fixed" -ForegroundColor Green
Write-Host "=== FIX WCP API LOG URI LINE DONE ===" -ForegroundColor Cyan
