import 'dart:convert';
import 'package:http/http.dart' as http;

class NwsService {
  static const _base = 'https://api.weather.gov';

  final http.Client _client;
  final String _ua;

  NwsService({http.Client? client, String? userAgent})
      : _client = client ?? http.Client(),
        _ua = userAgent ?? 'DivergentAllianceApp/1.0 (support@divergent-alliance.example)';

  Map<String, String> get _headers => {
        'Accept': 'application/geo+json',
        'User-Agent': _ua,
      };

  Future<_Point> getPoint(double lat, double lon) async {
    final r = await _client.get(
      Uri.parse('$_base/points/$lat,$lon'),
      headers: _headers,
    );
    if (r.statusCode != 200) {
      throw Exception('NWS points failed: ${r.statusCode}');
    }
    final j = json.decode(r.body) as Map<String, dynamic>;
    final props = j['properties'] as Map<String, dynamic>;
    return _Point(
      gridId: props['gridId'],
      gridX: props['gridX'],
      gridY: props['gridY'],
      forecastUrl: props['forecast'],
      hourlyUrl: props['forecastHourly'],
      forecastZone: props['forecastZone'],
    );
  }

  Future<List<NwsPeriod>> getForecast(String forecastUrl) async {
    final r = await _client.get(Uri.parse(forecastUrl), headers: _headers);
    if (r.statusCode != 200) {
      throw Exception('NWS forecast failed: ${r.statusCode}');
    }
    final j = json.decode(r.body) as Map<String, dynamic>;
    final periods = (j['properties']['periods'] as List)
        .map((e) => NwsPeriod.fromMap(e as Map<String, dynamic>))
        .toList();
    return periods;
  }

  Future<List<NwsPeriod>> getHourly(String hourlyUrl) async {
    final r = await _client.get(Uri.parse(hourlyUrl), headers: _headers);
    if (r.statusCode != 200) {
      throw Exception('NWS hourly failed: ${r.statusCode}');
    }
    final j = json.decode(r.body) as Map<String, dynamic>;
    final periods = (j['properties']['periods'] as List)
        .map((e) => NwsPeriod.fromMap(e as Map<String, dynamic>))
        .toList();
    return periods;
  }

  Future<List<NwsAlert>> getActiveAlerts(double lat, double lon) async {
    final r = await _client.get(
      Uri.parse('$_base/alerts/active?point=$lat,$lon'),
      headers: _headers,
    );
    if (r.statusCode != 200) return const [];
    final j = json.decode(r.body) as Map<String, dynamic>;
    final features = (j['features'] as List?) ?? const [];
    return features
        .map((f) => NwsAlert.fromMap((f as Map<String, dynamic>)['properties']))
        .toList();
  }
}

class _Point {
  final String gridId;
  final int gridX;
  final int gridY;
  final String forecastUrl;
  final String hourlyUrl;
  final String forecastZone;
  _Point({
    required this.gridId,
    required this.gridX,
    required this.gridY,
    required this.forecastUrl,
    required this.hourlyUrl,
    required this.forecastZone,
  });
}

class NwsPeriod {
  final DateTime startTime;
  final DateTime endTime;
  final String name;
  final String shortForecast;
  final int? temperature;
  final String temperatureUnit;
  final double? pop;
  final String windDirection;
  final String windSpeed;

  NwsPeriod({
    required this.startTime,
    required this.endTime,
    required this.name,
    required this.shortForecast,
    required this.temperature,
    required this.temperatureUnit,
    required this.pop,
    required this.windDirection,
    required this.windSpeed,
  });

  factory NwsPeriod.fromMap(Map<String, dynamic> m) => NwsPeriod(
        startTime: DateTime.parse(m['startTime']),
        endTime: DateTime.parse(m['endTime']),
        name: m['name'] ?? '',
        shortForecast: m['shortForecast'] ?? '',
        temperature: m['temperature'],
        temperatureUnit: (m['temperatureUnit'] ?? 'F') as String,
        pop: (m['probabilityOfPrecipitation']?['value'] as num?)?.toDouble(),
        windDirection: m['windDirection'] ?? '',
        windSpeed: m['windSpeed'] ?? '',
      );
}

class NwsAlert {
  final String event;
  final String headline;
  final String description;
  final DateTime? effective;
  final DateTime? expires;

  NwsAlert({
    required this.event,
    required this.headline,
    required this.description,
    this.effective,
    this.expires,
  });

  factory NwsAlert.fromMap(Map<String, dynamic> m) => NwsAlert(
        event: m['event'] ?? '',
        headline: m['headline'] ?? '',
        description: m['description'] ?? '',
        effective:
            m['effective'] != null ? DateTime.tryParse(m['effective']) : null,
        expires:
            m['expires'] != null ? DateTime.tryParse(m['expires']) : null,
      );
}