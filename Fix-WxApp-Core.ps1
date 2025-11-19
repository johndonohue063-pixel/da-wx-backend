Param(
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance"
)

Write-Host "=== FIX WX APP CORE START ===" -ForegroundColor Cyan

# 1) FILE PATHS
$wc         = Join-Path $AppPath "lib\screens\weather_center.dart"
$wcRes      = Join-Path $AppPath "lib\screens\weather_center_results.dart"

# ---------- VALIDATE FILES ----------
foreach ($f in @($wc,$wcRes)) {
    if (-not (Test-Path $f)) {
        Write-Host "Missing file: $f" -ForegroundColor Red
        exit 1
    }
}

# ---------- BACKUPS ----------
foreach ($f in @($wc,$wcRes)) {
    $backup="$f.bak_autofix_$(Get-Date -Format yyyyMMdd_HHmmss)"
    Copy-Item $f $backup -Force
    Write-Host "Backup created: $backup" -ForegroundColor Green
}

# ---------- FIX BASE URL ----------
$wcText = Get-Content $wc -Raw
$wcText = $wcText.Replace(
    "RealWxProvider('https://da-wx-backend.onrender.com')",
    "RealWxProvider('https://da-wx-backend-1.onrender.com')"
)

# ---------- FIX BAD CHARACTERS ----------
$wcText = $wcText.Replace("â€¢", "·")
$wcText = $wcText.Replace("â€“", "-")
$wcText = $wcText.Replace(" â€¢ Max gust  mph â€¢ %",
                          " Max gust {gust} mph · {prob}%")

Set-Content $wc -Value $wcText -NoNewline
Write-Host "Fixed weather_center.dart" -ForegroundColor Green

# ---------- FIX RESULTS PAGE ----------
$wcResText = Get-Content $wcRes -Raw
$wcResText = $wcResText.Replace("â€¢", "·")
$wcResText = $wcResText.Replace("â€“", "-")
$wcResText = $wcResText.Replace("split('â€¢')","split('·')")

Set-Content $wcRes -Value $wcResText -NoNewline
Write-Host "Fixed weather_center_results.dart" -ForegroundColor Green

Write-Host "=== FIX WX APP CORE DONE ===" -ForegroundColor Cyan
