Param(
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance"
)

Write-Host "=== FIX WCP API + _runReport START ===" -ForegroundColor Cyan

# Paths
$wcpPath = Join-Path $AppPath "lib\services\wcp_api.dart"
$wcPath  = Join-Path $AppPath "lib\screens\weather_center.dart"

if (-not (Test-Path $wcpPath)) {
    Write-Host "ERROR: $wcpPath not found" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $wcPath)) {
    Write-Host "ERROR: $wcPath not found" -ForegroundColor Red
    exit 1
}

# -------------------- BACKUPS --------------------
$wcpBackup = "$wcpPath.bak_SCOPE_$(Get-Date -Format yyyyMMdd_HHmmss)"
$wcBackup  = "$wcPath.bak_SCOPE_$(Get-Date -Format yyyyMMdd_HHmmss)"

Copy-Item $wcpPath $wcpBackup -Force
Copy-Item $wcPath  $wcBackup  -Force

Write-Host "Backed up wcp_api.dart to $wcpBackup" -ForegroundColor Yellow
Write-Host "Backed up weather_center.dart to $wcBackup" -ForegroundColor Yellow

# -------------------- REWRITE wcp_api.dart --------------------
$wcpContent = @'
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/wcp_models.dart';

/// Abstraction used by Weather Center.
abstract class WxProvider {
  Future<List<CountyRow>> fetchByCounty(String state, String county);
  Future<List<CountyRow>> fetchNational(int hours, String metric);
  Future<List<CountyRow>> fetchRegion(String regionCode, int hours, String metric);
  Future<List<CountyRow>> fetchState(String stateCode, int hours, String metric);
}

/// Real provider that talks to your Render backend.
///
/// Endpoints (backend already implemented):
/// - /wcp/national
/// - /wcp/region
/// - /wcp/state
/// - /report/county   (for local preview per county)
class RealWxProvider implements WxProvider {
  final String baseUrl;

  RealWxProvider(this.baseUrl);

  // ----------------- FULL REPORTS -----------------

  @override
  Future<List<CountyRow>> fetchNational(int hours, String metric) async {
    final uri = Uri.parse(
      '$baseUrl/wcp/national?hours=$hours&metric=$metric&threshold=0',
    );
    return _loadList(uri);
  }

  @override
  Future<List<CountyRow>> fetchRegion(
      String regionCode, int hours, String metric) async {
    final uri = Uri.parse(
      '$baseUrl/wcp/region?region=$regionCode&hours=$hours&metric=$metric&threshold=0',
    );
    return _loadList(uri);
  }

  @override
  Future<List<CountyRow>> fetchState(
      String stateCode, int hours, String metric) async {
    final uri = Uri.parse(
      '$baseUrl/wcp/state?state=$stateCode&hours=$hours&metric=$metric&threshold=0',
    );
    return _loadList(uri);
  }

  // ----------------- LOCAL PREVIEW -----------------

  /// Uses /report/county mainly for GPS-based local preview.
  @override
  Future<List<CountyRow>> fetchByCounty(String state, String county) async {
    final encodedCounty = Uri.encodeComponent(county);
    final uri = Uri.parse(
      '$baseUrl/report/county?state=$state&county=$encodedCounty&hours=36&metric=gust&threshold=0',
    );
    return _loadList(uri);
  }

  // ----------------- INTERNAL HTTP HELPER -----------------

  Future<List<CountyRow>> _loadList(Uri uri) async {
    debugPrint('WCP backend call: $uri');

    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      final body = resp.body;
      final snippet = body.length > 200 ? body.substring(0, 200) : body;
      throw Exception('Backend error ${resp.statusCode}: $snippet');
    }

    final body = resp.body;
    if (body.isEmpty) {
      throw Exception('Empty response from backend.');
    }

    final decoded = json.decode(body);
    if (decoded is! List) {
      throw Exception('Expected JSON list from backend.');
    }

    final List<CountyRow> rows = [];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        try {
          rows.add(CountyRow.fromJson(item));
        } catch (_) {
          // skip bad rows, keep going
        }
      }
    }
    return rows;
  }
}
'@

Set-Content -Path $wcpPath -Value $wcpContent -Encoding UTF8 -NoNewline
Write-Host "wcp_api.dart rewritten with scoped RealWxProvider." -ForegroundColor Green

# -------------------- PATCH _runReport IN weather_center.dart --------------------
$wc = Get-Content $wcPath -Raw

$oldRun = @'
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

$newRun = @'
  Future<void> _runReport() async {
    setState(() {
      _loadingReport = true;
      _reportError = false;
    });

    try {
      final int hours = _hoursOut.toInt();
      const String metric = 'gust';

      List<CountyRow> rows;

      if (_scope == ScopeLevel.national) {
        // Direct national call.
        rows = await _provider
            .fetchNational(hours, metric)
            .timeout(const Duration(seconds: 60));
      } else if (_scope == ScopeLevel.regional && _selectedRegion != null) {
        // Map region label to backend region code.
        final String regionLabel = _selectedRegion!;
        String regionCode;
        switch (regionLabel) {
          case 'Northeast':
            regionCode = 'NE';
            break;
          case 'Midwest':
            regionCode = 'MW';
            break;
          case 'South':
            regionCode = 'SO';
            break;
          case 'West':
            regionCode = 'WE';
            break;
          default:
            regionCode = 'NE';
        }

        rows = await _provider
            .fetchRegion(regionCode, hours, metric)
            .timeout(const Duration(seconds: 60));
      } else if (_scope == ScopeLevel.state && _selectedState != null) {
        final String stateCode = _selectedState!;
        rows = await _provider
            .fetchState(stateCode, hours, metric)
            .timeout(const Duration(seconds: 60));
      } else {
        // Fallback if scope/selection is incomplete: use national.
        rows = await _provider
            .fetchNational(hours, metric)
            .timeout(const Duration(seconds: 60));
      }

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
            title: '$scopeText  ${hours}h',
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
    Write-Host "_runReport replaced with scoped backend calls." -ForegroundColor Green
} else {
    Write-Host "WARNING: _runReport pattern not found; file may have been edited manually." -ForegroundColor Yellow
}

Set-Content -Path $wcPath -Value $wc -Encoding UTF8

Write-Host "weather_center.dart updated." -ForegroundColor Green
Write-Host "=== FIX WCP API + _runReport DONE ===" -ForegroundColor Cyan
