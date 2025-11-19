Param(
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance"
)

Write-Host "=== RESET WCP API PROVIDER START ===" -ForegroundColor Cyan

if (-not (Test-Path $AppPath)) {
    Write-Host "App path does not exist: $AppPath" -ForegroundColor Red
    exit 1
}

Set-Location $AppPath

$wcpPath = Join-Path $AppPath "lib\services\wcp_api.dart"
if (Test-Path $wcpPath) {
    $backup = "$wcpPath.bak_reset_$(Get-Date -Format yyyyMMdd_HHmmss)"
    Copy-Item $wcpPath $backup -Force
    Write-Host "Backed up existing wcp_api.dart to $backup" -ForegroundColor Green
} else {
    Write-Host "wcp_api.dart not found; a new one will be created." -ForegroundColor Yellow
}

# Known-good provider content: no debugPrint, no broken quotes
$wcpContent = @'
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/wcp_models.dart';

/// WxProvider abstraction for Weather Center Pro.
/// RealWxProvider talks to the backend at /report/county.
abstract class WxProvider {
  Future<List<CountyRow>> fetchByCounty(String state, String county);
}

class RealWxProvider implements WxProvider {
  final String baseUrl;
  RealWxProvider(this.baseUrl);

  @override
  Future<List<CountyRow>> fetchByCounty(String state, String county) async {
    final uri = Uri.parse('$baseUrl/report/county?state=$state&county=$county');

    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      final body = resp.body;
      final snippet =
          body.length > 200 ? body.substring(0, 200) : body;
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
'@

Set-Content -Path $wcpPath -Value $wcpContent -NoNewline
Write-Host "wcp_api.dart has been reset to a clean RealWxProvider implementation." -ForegroundColor Green
Write-Host "=== RESET WCP API PROVIDER DONE ===" -ForegroundColor Cyan
