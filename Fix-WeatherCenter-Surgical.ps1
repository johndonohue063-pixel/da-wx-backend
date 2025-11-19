Param(
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance"
)

Write-Host "=== SURGICAL WEATHER CENTER FIX START ===" -ForegroundColor Cyan

$wcPath = Join-Path $AppPath "lib\screens\weather_center.dart"
if (-not (Test-Path $wcPath)) {
    Write-Host "ERROR: $wcPath not found" -ForegroundColor Red
    exit 1
}

# Backup current weather_center.dart
$backup = "$wcPath.bak_SURGICAL_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item $wcPath $backup -Force
Write-Host "Backup created: $backup" -ForegroundColor Green

# Read file
$wc = Get-Content $wcPath -Raw

# -------------------------------------------------------
# 1) Fix _runReport so it filters by Scope (National/Region/State)
# -------------------------------------------------------
$oldRun = @'
  Future<void> _runReport() async {
    setState(() {
      _loadingReport = true;
      _reportError = false;
    });

    try {
      // Backend returns national list for US/Nationwide; results page filters down.
      final rows = await _provider.fetchByCounty('US', 'Nationwide').timeout(const Duration(seconds: 60)).timeout(const Duration(seconds: 60));
      setState(() {
        _rows = rows;
        _loadingReport = false;
      });

      if (!mounted) return;

      String scopeText;
      switch (_scope) {
        case ScopeLevel.national:
          scopeText = 'National';
          break;
        case ScopeLevel.regional:
          scopeText = _selectedRegion ?? 'Regional';
          break;
        case ScopeLevel.state:
          scopeText = _selectedState ?? 'State';
          break;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WeatherCenterResultsPage(
            rows: _rows,
            title: '$scopeText  ${_hoursOut.toInt()}h',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Full report failed: $e');
      setState(() {
        _reportError = true;
        _loadingReport = false;
      });
    }
  }
'@

$newRun = @'
  Future<void> _runReport() async {
    setState(() {
      _loadingReport = true;
      _reportError = false;
    });

    try {
      // Backend returns national list for US/Nationwide.
      final allRows = await _provider
          .fetchByCounty('US', 'Nationwide')
          .timeout(const Duration(seconds: 60));

      // Apply scope filters on the client.
      List<CountyRow> filtered = List<CountyRow>.from(allRows);

      if (_scope == ScopeLevel.regional && _selectedRegion != null) {
        final regionStates = kRegions[_selectedRegion] ?? const [];
        filtered = filtered
            .where((r) => regionStates.contains(r.stateCode))
            .toList();
      } else if (_scope == ScopeLevel.state && _selectedState != null) {
        filtered =
            filtered.where((r) => r.stateCode == _selectedState).toList();
      }

      setState(() {
        _rows = filtered;
        _loadingReport = false;
      });

      if (!mounted) return;

      String scopeText;
      switch (_scope) {
        case ScopeLevel.national:
          scopeText = 'National';
          break;
        case ScopeLevel.regional:
          scopeText = _selectedRegion ?? 'Regional';
          break;
        case ScopeLevel.state:
          scopeText = _selectedState ?? 'State';
          break;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WeatherCenterResultsPage(
            rows: _rows,
            title: '$scopeText  ${_hoursOut.toInt()}h',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Full report failed: $e');
      setState(() {
        _reportError = true;
        _loadingReport = false;
      });
    }
  }
'@

if ($wc.Contains($oldRun)) {
    $wc = $wc.Replace($oldRun, $newRun)
    Write-Host "_runReport replaced with scoped filtering version." -ForegroundColor Green
} else {
    Write-Host "WARNING: _runReport pattern not found; no change applied there." -ForegroundColor Yellow
}

# -------------------------------------------------------
# 2) Fix local preview snippet to show real gust + probability
# -------------------------------------------------------
$oldPreview = @'
      threatSnippet =
          '  Max gust  mph  %';
'@

$newPreview = @'
      threatSnippet =
          'Max gust ${gust.toStringAsFixed(0)} mph · ${prob.toStringAsFixed(0)}%';
'@

if ($wc.Contains($oldPreview)) {
    $wc = $wc.Replace($oldPreview, $newPreview)
    Write-Host "Local preview snippet updated to show gust and probability." -ForegroundColor Green
} else {
    Write-Host "WARNING: local preview placeholder text not found; no change applied there." -ForegroundColor Yellow
}

# -------------------------------------------------------
# 3) Add radar overlay on top of base map
# -------------------------------------------------------
$oldRadar = @'
                children: [
                  // Placeholder basemap; real radar tiles would require a radar tile source.
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.divergent.alliance',
                  ),
                ],
'@

$newRadar = @'
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.divergent.alliance',
                  ),
                  // Simple radar overlay (RainViewer demo tiles).
                  TileLayer(
                    urlTemplate:
                        'https://tilecache.rainviewer.com/v2/radar/now/256/{z}/{x}/{y}/2/1_1.png',
                    userAgentPackageName: 'com.divergent.alliance',
                    opacity: 0.7,
                  ),
                ],
'@

if ($wc.Contains($oldRadar)) {
    $wc = $wc.Replace($oldRadar, $newRadar)
    Write-Host "Radar overlay layer added on top of base map." -ForegroundColor Green
} else {
    Write-Host "WARNING: radar block pattern not found; no change applied there." -ForegroundColor Yellow
}

# -------------------------------------------------------
# Write file back
# -------------------------------------------------------
Set-Content -Path $wcPath -Value $wc -Encoding UTF8
Write-Host "weather_center.dart updated." -ForegroundColor Green
Write-Host "=== SURGICAL WEATHER CENTER FIX DONE ===" -ForegroundColor Cyan
