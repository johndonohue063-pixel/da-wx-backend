Param(
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance"
)

Write-Host "=== TUNE WX APP START ===" -ForegroundColor Cyan

if (-not (Test-Path $AppPath)) {
    Write-Host "App path does not exist: $AppPath" -ForegroundColor Red
    exit 1
}

Set-Location $AppPath

# --------------------------------------------------
# 1. Fix mis-encoded text in all Dart files
# --------------------------------------------------
Write-Host "[APP] Fixing mis-encoded text in Dart files..." -ForegroundColor Yellow

$patterns = @{
    "Weather Center â€“" = "Weather Center - ";
    "Northeast â€¢"      = "Northeast -";
    "â€¢C&"              = "|";   # weird bullet/glitch from your screenshot
    "â€¢"                = "•";   # generic bullet fix
}

$dartFiles = Get-ChildItem -Path $AppPath -Recurse -Include *.dart

foreach ($file in $dartFiles) {
    $path = $file.FullName
    $text = [System.IO.File]::ReadAllText($path)

    $needsChange = $false
    foreach ($k in $patterns.Keys) {
        if ($text.Contains($k)) { $needsChange = $true; break }
    }
    if (-not $needsChange) { continue }

    $backup = "$path.bak_text_$(Get-Date -Format yyyyMMdd_HHmmss)"
    Copy-Item $path $backup -Force

    foreach ($k in $patterns.Keys) {
        $text = $text.Replace($k, $patterns[$k])
    }

    [System.IO.File]::WriteAllText($path, $text)
    Write-Host "[APP] Fixed text in: $path (backup: $backup)" -ForegroundColor Green
}

# --------------------------------------------------
# 2. Make sure backend URL is da-wx-backend-1 everywhere
# --------------------------------------------------
Write-Host "[APP] Normalizing backend URLs..." -ForegroundColor Yellow

$newUrl  = "https://da-wx-backend-1.onrender.com"
$oldUrls = @(
    "https://da-wx-backend.onrender.com",
    "https://da-wx-backend-1.onrender.com"  # keep idempotent
)

foreach ($file in $dartFiles) {
    $path = $file.FullName
    $text = [System.IO.File]::ReadAllText($path)

    $needsChange = $false
    foreach ($old in $oldUrls) {
        if ($text.Contains($old)) { $needsChange = $true; break }
    }
    if (-not $needsChange) { continue }

    $backup = "$path.bak_url_$(Get-Date -Format yyyyMMdd_HHmmss)"
    Copy-Item $path $backup -Force

    foreach ($old in $oldUrls) {
        $text = $text.Replace($old, $newUrl)
    }

    [System.IO.File]::WriteAllText($path, $text)
    Write-Host "[APP] Set backend URL in: $path (backup: $backup)" -ForegroundColor Green
}

# --------------------------------------------------
# 3. Add timeout to wcp_api.dart backend call
# --------------------------------------------------
Write-Host "[APP] Adding timeout to wcp_api.dart backend call..." -ForegroundColor Yellow

$wcpApiPath = Join-Path $AppPath "lib\services\wcp_api.dart"
if (Test-Path $wcpApiPath) {
    $wcpText = [System.IO.File]::ReadAllText($wcpApiPath)

    $oldLine = "    final resp = await http.get(uri);"
    $newLine = @"
    final resp = await http.get(uri).timeout(
      const Duration(seconds: 25),
    );
"@

    if ($wcpText.Contains($oldLine)) {
        $backup = "$wcpApiPath.bak_timeout_$(Get-Date -Format yyyyMMdd_HHmmss)"
        Copy-Item $wcpApiPath $backup -Force

        $wcpText = $wcpText.Replace($oldLine, $newLine)
        [System.IO.File]::WriteAllText($wcpApiPath, $wcpText)
        Write-Host "[APP] Updated wcp_api.dart with timeout (backup: $backup)" -ForegroundColor Green
    } else {
        Write-Host "[APP] Did not find 'final resp = await http.get(uri);' in wcp_api.dart, leaving it unchanged." -ForegroundColor DarkYellow
    }
} else {
    Write-Host "[APP] wcp_api.dart not found, skipping timeout update." -ForegroundColor DarkYellow
}

Write-Host "=== TUNE WX APP DONE ===" -ForegroundColor Cyan
