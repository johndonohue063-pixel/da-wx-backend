Param(
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance"
)

Write-Host "=== MASTER WX APP FIX START ===" -ForegroundColor Cyan

if (-not (Test-Path $AppPath)) {
    Write-Host "App path does not exist: $AppPath" -ForegroundColor Red
    exit 1
}

Set-Location $AppPath

# ---------------------------------------------
# 1. Fix mis-encoded text (â€¢, â€“ etc.)
# ---------------------------------------------
Write-Host "[APP] Fixing mis-encoded characters in Dart files..." -ForegroundColor Yellow

# Keep this mapping simple and safe: only the ones we know you have
$badToGoodMap = @{
    "â€¢" = "•";    # bullet
    "â€“" = "-";    # en dash to hyphen
}

$dartFiles = Get-ChildItem -Path $AppPath -Recurse -Include *.dart

foreach ($file in $dartFiles) {
    $path = $file.FullName
    $text = [System.IO.File]::ReadAllText($path)

    $needsChange = $false
    foreach ($bad in $badToGoodMap.Keys) {
        if ($text.Contains($bad)) { $needsChange = $true; break }
    }
    if (-not $needsChange) { continue }

    $backup = "$path.bak_text_$(Get-Date -Format yyyyMMdd_HHmmss)"
    Copy-Item $path $backup -Force

    foreach ($bad in $badToGoodMap.Keys) {
        $good = $badToGoodMap[$bad]
        $text = $text.Replace($bad, $good)
    }

    [System.IO.File]::WriteAllText($path, $text)
    Write-Host "[APP] Fixed text in: $path (backup: $backup)" -ForegroundColor Green
}

# ---------------------------------------------
# 2. Normalize backend URLs in Dart
# ---------------------------------------------
Write-Host "[APP] Pointing all backend URLs to da-wx-backend-1..." -ForegroundColor Yellow

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

# ---------------------------------------------
# 3. Add timeout to wcp_api.dart http call
# ---------------------------------------------
Write-Host "[APP] Adding timeout to wcp_api.dart backend call..." -ForegroundColor Yellow

$wcpApiPath = Join-Path $AppPath "lib\services\wcp_api.dart"
if (Test-Path $wcpApiPath) {
    $wcpText = [System.IO.File]::ReadAllText($wcpApiPath)

    # Ensure debugPrint import
    $httpImport = "import 'package:http/http.dart' as http;"
    $debugImport = "import 'package:flutter/foundation.dart';"
    if ($wcpText.Contains($httpImport) -and -not $wcpText.Contains($debugImport)) {
        $backupImp = "$wcpApiPath.bak_import_$(Get-Date -Format yyyyMMdd_HHmmss)"
        Copy-Item $wcpApiPath $backupImp -Force
        Write-Host "[APP] Backup before adding import: $backupImp" -ForegroundColor Green

        $wcpText = $wcpText.Replace($httpImport, $httpImport + [Environment]::NewLine + $debugImport)
        [System.IO.File]::WriteAllText($wcpApiPath, $wcpText)
        $wcpText = [System.IO.File]::ReadAllText($wcpApiPath)
        Write-Host "[APP] Added $debugImport" -ForegroundColor Green
    }

    $oldLine = "    final resp = await http.get(uri);"
    $newLine = @"
    final resp = await http.get(uri).timeout(
      const Duration(seconds: 25),
    );
"@

    if ($wcpText.Contains($oldLine)) {
        $backupTimeout = "$wcpApiPath.bak_timeout_$(Get-Date -Format yyyyMMdd_HHmmss)"
        Copy-Item $wcpApiPath $backupTimeout -Force

        $wcpText = $wcpText.Replace($oldLine, $newLine)
        [System.IO.File]::WriteAllText($wcpApiPath, $wcpText)
        Write-Host "[APP] Updated wcp_api.dart with timeout (backup: $backupTimeout)" -ForegroundColor Green
    } else {
        Write-Host "[APP] Timeout line already updated or not found; leaving wcp_api.dart call as-is." -ForegroundColor DarkYellow
    }
} else {
    Write-Host "[APP] wcp_api.dart not found; skipping timeout update." -ForegroundColor DarkYellow
}

# ---------------------------------------------
# 4. Overwrite wcp_models.dart with tolerant CountyRow
# ---------------------------------------------
Write-Host "[APP] Overwriting wcp_models.dart with tolerant CountyRow model..." -ForegroundColor Yellow

$wcpModelsPath = Join-Path $AppPath "lib\models\wcp_models.dart"
if (-not (Test-Path $wcpModelsPath)) {
    Write-Host "[APP] wcp_models.dart not found at $wcpModelsPath, creating new file." -ForegroundColor DarkYellow
} else {
    $backupModels = "$wcpModelsPath.bak_master_$(Get-Date -Format yyyyMMdd_HHmmss)"
    Copy-Item $wcpModelsPath $backupModels -Force
    Write-Host "[APP] Backed up existing wcp_models.dart to $backupModels" -ForegroundColor Green
}

$wcpModelsContent = @'
import 'dart:math';

class CountyRow {
  final String county;
  final String state;
  final int population;
  final double lat;
  final double lon;
  final double expectedGust;
  final double expectedSustained;
  final double maxGust;
  final double maxSustained;
  final double probability;
  final String severity;
  final int crews;

  CountyRow({
    required this.county,
    required this.state,
    required this.population,
    required this.lat,
    required this.lon,
    required this.expectedGust,
    required this.expectedSustained,
    required this.maxGust,
    required this.maxSustained,
    required this.probability,
    required this.severity,
    required this.crews,
  });

  factory CountyRow.fromJson(Map<String, dynamic> json) {
    double _d(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    int _i(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    String _s(dynamic v) => v?.toString() ?? '';

    final eg = json.containsKey('expectedGust')
        ? _d(json['expectedGust'])
        : _d(json['expGust']);

    final es = json.containsKey('expectedSustained')
        ? _d(json['expectedSustained'])
        : _d(json['expSust']);

    final mg = _d(json['maxGust']); // same key for alias
    final ms = json.containsKey('maxSustained')
        ? _d(json['maxSustained'])
        : _d(json['maxSust']);

    final crews = json.containsKey('crews')
        ? _i(json['crews'])
        : _i(json['crewCount']);

    final sev = json.containsKey('severity')
        ? _s(json['severity'])
        : _s(json['threatLevel']);

    return CountyRow(
      county: _s(json['county']),
      state: _s(json['state']),
      population: _i(json['population']),
      lat: _d(json['lat']),
      lon: _d(json['lon']),
      expectedGust: eg,
      expectedSustained: es,
      maxGust: mg,
      maxSustained: ms,
      probability: _d(json['probability']),
      severity: sev,
      crews: crews,
    );
  }
}
'@

Set-Content -Path $wcpModelsPath -Value $wcpModelsContent -NoNewline
Write-Host "[APP] wcp_models.dart overwritten with tolerant model." -ForegroundColor Green

Write-Host "=== MASTER WX APP FIX DONE ===" -ForegroundColor Cyan
