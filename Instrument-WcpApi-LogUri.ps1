Param(
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance"
)

Write-Host "=== INSTRUMENT WCP API (LOG URI) START ===" -ForegroundColor Cyan

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

# 1) Ensure debugPrint import
$httpImport  = "import 'package:http/http.dart' as http;"
$debugImport = "import 'package:flutter/foundation.dart';"

if ($text.Contains($httpImport) -and -not $text.Contains($debugImport)) {
    $backupImp = "$wcpPath.bak_loguri_import_$(Get-Date -Format yyyyMMdd_HHmmss)"
    Copy-Item $wcpPath $backupImp -Force
    Write-Host "Backup before adding import: $backupImp" -ForegroundColor Green

    $text = $text.Replace($httpImport, $httpImport + [Environment]::NewLine + $debugImport)
}

# 2) Insert debugPrint before http.get(uri)
$oldLine = "    final resp = await http.get(uri)"
if (-not $text.Contains($oldLine)) {
    # maybe it already has timeout etc – handle that too
    $oldLine = "    final resp = await http.get(uri).timeout("
}

if (-not $text.Contains($oldLine)) {
    Write-Host "Could not find http.get(uri) line in wcp_api.dart; leaving file unchanged." -ForegroundColor Yellow
    Write-Host "=== INSTRUMENT WCP API (LOG URI) DONE (NO CHANGES) ===" -ForegroundColor Cyan
    exit 0
}

$backup = "$wcpPath.bak_loguri_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item $wcpPath $backup -Force
Write-Host "Backup before inserting log: $backup" -ForegroundColor Green

$logLine = "    debugPrint('WCP backend call: \$uri');" + [Environment]::NewLine + $oldLine
$text = $text.Replace($oldLine, $logLine)

[System.IO.File]::WriteAllText($wcpPath, $text)
Write-Host "Inserted debugPrint('WCP backend call: \$uri') in wcp_api.dart" -ForegroundColor Green
Write-Host "=== INSTRUMENT WCP API (LOG URI) DONE ===" -ForegroundColor Cyan
