Param(
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance"
)

Write-Host "=== SIMPLE FIX FOR WEATHER CENTER ===" -ForegroundColor Cyan

$wcPath = Join-Path $AppPath "lib\screens\weather_center.dart"
if (-not (Test-Path $wcPath)) {
    Write-Host "ERROR: $wcPath not found" -ForegroundColor Red
    exit 1
}

# Backup
$backup = "$wcPath.bak_SIMPLE_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item $wcPath $backup -Force
Write-Host "Backup created: $backup" -ForegroundColor Green

$text = [System.IO.File]::ReadAllText($wcPath)

# 1) Make sure provider points at the live backend
$text = $text.Replace(
    "RealWxProvider('https://da-wx-backend.onrender.com')",
    "RealWxProvider('https://da-wx-backend-1.onrender.com')"
)

# 2) Disable LOCAL preview: show simple text instead of spinning forever
# Replace the "Computing local threat preview..." state with a simple message.
$text = $text.Replace(
"      if (_localLoading && _localError == null) {
        threatSnippet = 'Computing local threat preview...';
      } else if (_localError != null) {
        threatSnippet = _localError;
      } else if (_localRow != null) {",
"      if (_localError != null) {
        threatSnippet = _localError;
      } else if (_localRow != null) {"
)

# Also change the default text when we don't have a location:
$text = $text.Replace(
"    } else if (_userCounty != null && _userState != null) {
      baseText = ' County, ';
    } else {
      baseText = 'Location unavailable';",
"    } else {
      baseText = 'Local preview unavailable.';
"
)

# 3) Add a timeout around the full report call so spinner cannot run forever
# Replace the single await line with a timeout version.
$text = $text.Replace(
"      // Backend returns national list for US/Nationwide; results page filters down.
      final rows = await _provider.fetchByCounty('US', 'Nationwide');",
"      // Backend returns national list for US/Nationwide; results page filters down.
      final rows = await _provider
          .fetchByCounty('US', 'Nationwide')
          .timeout(const Duration(seconds: 25));"
)

[System.IO.File]::WriteAllText($wcPath, $text)
Write-Host "Patched weather_center.dart" -ForegroundColor Green
Write-Host "=== DONE ===" -ForegroundColor Cyan
