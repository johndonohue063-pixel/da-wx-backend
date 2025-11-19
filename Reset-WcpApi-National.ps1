Param(
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance"
)

Write-Host "=== RESET wcp_api.dart to use /report/national ===" -ForegroundColor Cyan

Set-Location $AppPath

$wcp = "lib\services\wcp_api.dart"
if (-not (Test-Path $wcp)) {
    Write-Host "ERROR: $wcp not found" -ForegroundColor Red
    exit 1
}

# Backup current file
$backup = "$wcp.bak_RESET_NATIONAL_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item $wcp $backup -Force
Write-Host "Backup created: $backup" -ForegroundColor Green

# Overwrite with clean Dart source (single-quoted here-string: PowerShell will not touch $, ' etc)
@'
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/wcp_models.dart';

/// WxProvider abstraction for Weather Center Pro.
abstract class WxProvider {
  Future<List<CountyRow>> fetchByCounty(String state, String county);
}

/// Real implementation that talks to the backend.
/// For now we ignore the state/county hints and always fetch national data
/// so the UI has something to show.
class RealWxProvider implements WxProvider {
  final String baseUrl;
  RealWxProvider(this.baseUrl);

  @override
  Future<List<CountyRow>> fetchByCounty(String state, String county) async {
    // Hard-wire to national route for now to ensure data flows end-to-end.
    final uri = Uri.parse('$baseUrl/report/national?hours=36&metric=gust&threshold=0');
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
          // Skip malformed rows but continue.
          continue;
        }
      }
    }
    return rows;
  }
}
'@ | Set-Content $wcp -NoNewline

Write-Host "wcp_api.dart overwritten to call /report/national." -ForegroundColor Cyan
Write-Host "=== DONE ===" -ForegroundColor Cyan
