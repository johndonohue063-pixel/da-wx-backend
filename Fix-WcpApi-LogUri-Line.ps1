Param(
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance"
)

Write-Host "=== FIX WCP API LOG URI LINE (LINE-BASED) START ===" -ForegroundColor Cyan

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

$lines = Get-Content $wcpPath

$changed = $false
for ($i = 0; $i -lt $lines.Length; $i++) {
    $lineTrim = $lines[$i].Trim()
    if ($lineTrim.StartsWith("debugPrint('WCP backend call")) {
        $backup = "$wcpPath.bak_fixlogline_$(Get-Date -Format yyyyMMdd_HHmmss)"
        Copy-Item $wcpPath $backup -Force
        Write-Host "Backup created: $backup" -ForegroundColor Green

        $lines[$i] = "    debugPrint('WCP backend call: \$uri');"
        Write-Host "Replaced debugPrint line at line $($i + 1)." -ForegroundColor Green
        $changed = $true
        break
    }
}

if ($changed) {
    Set-Content -Path $wcpPath -Value $lines
    Write-Host "Updated wcp_api.dart" -ForegroundColor Green
} else {
    Write-Host "No debugPrint('WCP backend call...') line found; nothing changed." -ForegroundColor Yellow
}

Write-Host "=== FIX WCP API LOG URI LINE (LINE-BASED) DONE ===" -ForegroundColor Cyan
