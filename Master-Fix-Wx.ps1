Param(
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance",
    [string]$BackendPath = "C:\Users\JohnDonohue\dev\da-wx-backend"
)

Write-Host "=== MASTER WX FIX START ===" -ForegroundColor Cyan

# ---------------------------
#  A. APP SIDE (FLUTTER)
# ---------------------------
if (-not (Test-Path $AppPath)) {
    Write-Host "App path not found: $AppPath" -ForegroundColor Red
    exit 1
}

Write-Host "Using Flutter app path: $AppPath" -ForegroundColor Cyan
Set-Location $AppPath

# 1) Fix wx_api.dart _points() to NWS
$wxApiPath = Join-Path $AppPath "lib\services\wx_api.dart"
if (Test-Path $wxApiPath) {
    Write-Host "[APP] Fixing _points() in wx_api.dart" -ForegroundColor Yellow
    $text = [System.IO.File]::ReadAllText($wxApiPath)

    $startMarker = "  Future<_PointMeta> _points(double lat, double lon) async {"
    $endMarker   = "  Future<List<Map<String, dynamic>>> _hourly(String forecastHourlyUrl) async {"

    $sIndex = $text.IndexOf($startMarker)
    $eIndex = $text.IndexOf($endMarker)

    if ($sIndex -ge 0 -and $eIndex -gt $sIndex) {
        $before = $text.Substring(0, $sIndex)
        $after  = $text.Substring($eIndex)

        $pointsFunction = @'
  Future<_PointMeta> _points(double lat, double lon) async {
    final url = Uri.parse('https://api.weather.gov/points/$lat,$lon');
    final r = await http.get(
      url,
      headers: {'User-Agent': _ua, 'Accept': 'application/geo+json'},
    );
    if (r.statusCode != 200) {
      throw Exception('NWS points failed: ${r.statusCode}');
    }
    final j = json.decode(r.body);
    final props = j['properties'] ?? {};
    return _PointMeta(
      forecastHourly: props['forecastHourly'],
    );
  }

'@

        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
        $wxBackup = "$wxApiPath.bak_$ts"
        Copy-Item $wxApiPath $wxBackup -Force

        $newText = $before + $pointsFunction + $after
        [System.IO.File]::WriteAllText($wxApiPath, $newText)
        Write-Host "[APP] Replaced _points() and backed up to $wxBackup" -ForegroundColor Green
    } else {
        Write-Host "[APP] Could not find recognizable _points() block in wx_api.dart; leaving file unchanged." -ForegroundColor DarkYellow
    }
} else {
    Write-Host "[APP] wx_api.dart not found, skipping." -ForegroundColor DarkYellow
}

# 2) Point ALL backend URLs at da-wx-backend-1
$newUrl  = "https://da-wx-backend-1.onrender.com"
$oldUrls = @(
    "https://da-wx-backend.onrender.com",
    "https://da-wx-backend-1.onrender.com" # make re-runs idempotent
)

Write-Host "[APP] Updating backend URLs in Dart files to $newUrl" -ForegroundColor Yellow
$dartFiles = Get-ChildItem -Path $AppPath -Recurse -Include *.dart
foreach ($file in $dartFiles) {
    $path = $file.FullName
    $text = [System.IO.File]::ReadAllText($path)

    $needsChange = $false
    foreach ($old in $oldUrls) {
        if ($text.Contains($old)) {
            $needsChange = $true
            break
        }
    }

    if (-not $needsChange) { continue }

    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = "$path.bak_url_$ts"
    Copy-Item $path $backupPath -Force

    foreach ($old in $oldUrls) {
        $text = $text.Replace($old, $newUrl)
    }

    [System.IO.File]::WriteAllText($path, $text)
    Write-Host "[APP] Updated URL in: $path (backup: $backupPath)" -ForegroundColor Green
}

# 3) Try to fix footer gibberish
Write-Host "[APP] Attempting footer text fix (Storm Response...)" -ForegroundColor Yellow
$badFooterExamples = @(
    "Storm Response â€¢C& Material Supply â€¢C& Utility R&D",
    "Storm Response â€¢ Material Supply â€¢ Utility R&D"
)
$newFooter = "Storm Response  |  Material Supply  |  Utility R&D"

foreach ($file in $dartFiles) {
    $path = $file.FullName
    $text = [System.IO.File]::ReadAllText($path)

    $footerNeedsChange = $false
    foreach ($bad in $badFooterExamples) {
        if ($text.Contains($bad)) { $footerNeedsChange = $true; break }
    }

    if (-not $footerNeedsChange) { continue }

    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = "$path.bak_footer_$ts"
    Copy-Item $path $backupPath -Force

    foreach ($bad in $badFooterExamples) {
        $text = $text.Replace($bad, $newFooter)
    }

    [System.IO.File]::WriteAllText($path, $text)
    Write-Host "[APP] Fixed footer text in: $path (backup: $backupPath)" -ForegroundColor Green
}

Write-Host "=== APP SIDE DONE ===" -ForegroundColor Cyan

# ---------------------------
#  B. BACKEND SIDE (PYTHON)
# ---------------------------
if (-not (Test-Path $BackendPath)) {
    Write-Host "Backend path not found: $BackendPath" -ForegroundColor Red
    Write-Host "Skipping backend shim updates." -ForegroundColor DarkYellow
    Write-Host "=== MASTER WX FIX COMPLETE (APP ONLY) ==="
    exit 0
}

Write-Host "Using backend path: $BackendPath" -ForegroundColor Cyan
Set-Location $BackendPath

$backendFile = Join-Path $BackendPath "wx_live_backend.py"
if (-not (Test-Path $backendFile)) {
    Write-Host "[BACKEND] wx_live_backend.py not found, skipping backend updates." -ForegroundColor Red
    Write-Host "=== MASTER WX FIX COMPLETE (APP ONLY) ==="
    exit 0
}

Write-Host "[BACKEND] Updating wx_live_backend.py shim endpoints" -ForegroundColor Yellow
$pyText = [System.IO.File]::ReadAllText($backendFile)

$shimMarker = "# --- WCP SHIMS ADDED BY MASTER-FIX-WX ---"
if ($pyText.Contains($shimMarker)) {
    Write-Host "[BACKEND] Shim block already present; skipping re-add." -ForegroundColor DarkYellow
} else {

    $shimBlock = @'
# --- WCP SHIMS ADDED BY MASTER-FIX-WX ---

@app.get("/report/county")
async def report_county(
    state: str = Query(...),
    county: str = Query(...),
    hours: int = Query(36),
    metric: str = Query("gust"),
    threshold: float = Query(0.0),
):
    rows = await build_state_rows_all_counties(
        state_abbr=state,
        hours=hours,
        metric=metric,
        threshold=threshold,
    )
    cname = county.strip().lower()
    out = [r for r in rows if r.get("county", "").strip().lower() == cname]
    return out


@app.get("/wcp/region")
def wcp_region(
    region: str = Query("NE"),
    hours: int = Query(36),
    metric: str = Query("gust"),
    threshold: float = Query(0.0),
):
    # Delegate to existing region report
    return report_region(region=region, hours=hours, metric=metric, threshold=threshold)


@app.get("/wcp/state")
async def wcp_state(
    state: str = Query(...),
    hours: int = Query(36),
    metric: str = Query("gust"),
    threshold: float = Query(0.0),
):
    return await report_state(state=state, hours=hours, metric=metric, threshold=threshold)


@app.get("/wcp/national")
async def wcp_national(
    hours: int = Query(36),
    metric: str = Query("gust"),
    threshold: float = Query(0.0),
):
    return await report_national(hours=hours, metric=metric, threshold=threshold)

'@

    # append shimBlock near the end, before __main__ if present
    $insertIndex = $pyText.IndexOf('if __name__ == "__main__":')
    if ($insertIndex -lt 0) {
        # no __main__ block, just append
        $newPyText = $pyText + "`n`n" + $shimMarker + "`n" + $shimBlock
    } else {
        $beforeMain = $pyText.Substring(0, $insertIndex)
        $mainAndAfter = $pyText.Substring($insertIndex)
        $newPyText = $beforeMain + "`n`n" + $shimMarker + "`n" + $shimBlock + "`n`n" + $mainAndAfter
    }

    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $pyBackup = "$backendFile.bak_$ts"
    Copy-Item $backendFile $pyBackup -Force
    [System.IO.File]::WriteAllText($backendFile, $newPyText)

    Write-Host "[BACKEND] Shim endpoints appended, backup at $pyBackup" -ForegroundColor Green
}

#  Push changes so Render redeploys
Write-Host "[BACKEND] Running git add/commit/push" -ForegroundColor Yellow
try {
    git add wx_live_backend.py | Out-Null
    git commit -m "Add WCP shim endpoints (master fix)" | Out-Null
} catch {
    Write-Host "[BACKEND] git commit may have no changes or failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

try {
    git push | Out-Null
    Write-Host "[BACKEND] git push completed (check Render for new deploy)." -ForegroundColor Green
} catch {
    Write-Host "[BACKEND] git push failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "You may need to run 'git push' manually inside $BackendPath." -ForegroundColor DarkYellow
}

Write-Host "=== MASTER WX FIX COMPLETE ===" -ForegroundColor Cyan
