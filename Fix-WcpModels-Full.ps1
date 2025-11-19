Param(
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance"
)

Write-Host "=== FIX WCP MODELS (FULL) START ===" -ForegroundColor Cyan

if (-not (Test-Path $AppPath)) {
    Write-Host "App path does not exist: $AppPath" -ForegroundColor Red
    exit 1
}

Set-Location $AppPath

$modelsPath = Join-Path $AppPath "lib\models\wcp_models.dart"
if (Test-Path $modelsPath) {
    $backup = "$modelsPath.bak_full_$(Get-Date -Format yyyyMMdd_HHmmss)"
    Copy-Item $modelsPath $backup -Force
    Write-Host "Backed up existing wcp_models.dart to $backup" -ForegroundColor Green
} else {
    Write-Host "wcp_models.dart not found, it will be created fresh." -ForegroundColor Yellow
}

$modelsContent = @'
import 'dart:math';

/// CountyRow model used by Weather Center Pro screens.
/// This is tolerant to different backend field names. It can consume:
/// - New backend keys: county, state, population, lat, lon,
///   expectedGust, expectedSustained, maxGust, maxSustained,
///   probability, severity, crews, predictedImpactDate
/// - Legacy alias keys we added on the backend:
///   expGust, expSust, maxGust, maxSust, crewCount, threatLevel
/// - Original UI fields: countyName, stateCode, confidence,
///   recommendedCrews, customersAtRisk, peakWindow
class CountyRow {
  final String countyName;
  final String stateCode;
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

  // Extended fields used by UI
  final double confidence;        // 0–100
  final int recommendedCrews;
  final int customersAtRisk;
  final String peakWindow;        // text for "Peak Threat Window"

  CountyRow({
    required this.countyName,
    required this.stateCode,
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
    required this.confidence,
    required this.recommendedCrews,
    required this.customersAtRisk,
    required this.peakWindow,
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

    final countyName = _s(json['countyName'] ?? json['county']);
    final stateCode = _s(json['stateCode'] ?? json['state']);
    final population = _i(json['population']);

    final lat = _d(json['lat']);
    final lon = _d(json['lon']);

    final expectedGust = json.containsKey('expectedGust')
        ? _d(json['expectedGust'])
        : _d(json['expGust']);

    final expectedSustained = json.containsKey('expectedSustained')
        ? _d(json['expectedSustained'])
        : _d(json['expSust']);

    final maxGust = _d(json['maxGust']); // alias is same key
    final maxSustained = json.containsKey('maxSustained')
        ? _d(json['maxSustained'])
        : _d(json['maxSust']);

    final probability = _d(json['probability']);

    final severity = json.containsKey('severity')
        ? _s(json['severity'])
        : _s(json['threatLevel']);

    // recommendedCrews: prefer explicit, fallback to crews/crewCount
    int crews = json.containsKey('crews')
        ? _i(json['crews'])
        : _i(json['crewCount']);

    int recommendedCrews = json.containsKey('recommendedCrews')
        ? _i(json['recommendedCrews'])
        : crews;

    // customersAtRisk: prefer explicit, otherwise probability * population
    int customersAtRisk = json.containsKey('customersAtRisk')
        ? _i(json['customersAtRisk'])
        : max(0, (probability * population).round());

    // confidence: prefer explicit, otherwise map probability 0–1 to 0–100
    final rawConfidence = json.containsKey('confidence')
        ? _d(json['confidence'])
        : (probability * 100.0);
    final confidence = rawConfidence.clamp(0.0, 100.0);

    // peakWindow: prefer explicit, otherwise predictedImpactDate, then N/A
    final peakWindow = _s(json['peakWindow'] ?? json['predictedImpactDate'] ?? 'N/A');

    return CountyRow(
      countyName: countyName,
      stateCode: stateCode,
      population: population,
      lat: lat,
      lon: lon,
      expectedGust: expectedGust,
      expectedSustained: expectedSustained,
      maxGust: maxGust,
      maxSustained: maxSustained,
      probability: probability,
      severity: severity,
      crews: crews,
      confidence: confidence,
      recommendedCrews: recommendedCrews,
      customersAtRisk: customersAtRisk,
      peakWindow: peakWindow,
    );
  }
}

/// Simple centroid model used by search / nearest county logic.
class CountyCentroid {
  final String countyName;
  final String stateCode;
  final double lat;
  final double lon;

  CountyCentroid({
    required this.countyName,
    required this.stateCode,
    required this.lat,
    required this.lon,
  });

  factory CountyCentroid.fromJson(Map<String, dynamic> json) {
    double _d(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    String _s(dynamic v) => v?.toString() ?? '';

    return CountyCentroid(
      countyName: _s(json['countyName'] ?? json['county']),
      stateCode: _s(json['stateCode'] ?? json['state']),
      lat: _d(json['lat']),
      lon: _d(json['lon']),
    );
  }
}
'@

Set-Content -Path $modelsPath -Value $modelsContent -NoNewline
Write-Host "Wrote full CountyRow + CountyCentroid model to $modelsPath" -ForegroundColor Green

Write-Host "=== FIX WCP MODELS (FULL) DONE ===" -ForegroundColor Cyan
