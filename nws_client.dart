import "dart:async";
import "dart:convert";
import "dart:math";
import "package:http/http.dart" as http;

/// Live NWS wind client: returns max sustained + gust mph over [hours].
class NwsClient {
  static const String _ua = "DivergentAlliance/1.0 (ops@divergentalliance.com)";
  static const Duration _timeout = Duration(seconds: 12);

  // Robust GET that always applies headers (works across http package versions)
  static Future<http.Response> _get(
      Uri uri, Map<String, String> headers) async {
    final client = http.Client();
    try {
      final req = http.Request("GET", uri)..headers.addAll(headers);
      final streamed = await client.send(req).timeout(_timeout);
      return await http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> windForPoint({
    required double lat,
    required double lon,
    int hours = 24,
  }) async {
    final Map<String, String> h = {
      "User-Agent": _ua,
      "Accept": "application/geo+json",
    };

    // 1) points -> grid meta
    final p =
        await _get(Uri.parse("https://api.weather.gov/points/$lat,$lon"), h);
    if (p.statusCode != 200) {
      throw Exception("points ${p.statusCode}");
    }
    final m = json.decode(p.body);
    final office = m["properties"]?["gridId"];
    final gx = m["properties"]?["gridX"];
    final gy = m["properties"]?["gridY"];
    if (office == null || gx == null || gy == null) {
      throw Exception("grid meta missing");
    }

    // 2) hourly forecast
    final r = await _get(
        Uri.parse(
            "https://api.weather.gov/gridpoints/$office/$gx,$gy/forecast/hourly"),
        h);
    if (r.statusCode != 200) {
      throw Exception("hourly ${r.statusCode}");
    }
    final periods =
        (json.decode(r.body)["properties"]?["periods"] as List?) ?? const [];

    double maxG = 0, maxS = 0;
    for (int i = 0; i < periods.length && i < hours; i++) {
      final e = periods[i] as Map<String, dynamic>;
      final g = _mph(e["windGust"]);
      final s = _mph(e["windSpeed"]);
      if (g != null) maxG = max(maxG, g);
      if (s != null) maxS = max(maxS, s);
    }
    return {
      "gust_mph": maxG,
      "sust_mph": maxS,
      "office": "$office",
      "grid": "$gx,$gy"
    };
  }

  static double? _mph(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    final one = RegExp(r'(\d+)\s*mph').firstMatch(s);
    if (one != null) return double.tryParse(one.group(1)!);
    final two = RegExp(r'(\d+)\s*to\s*(\d+)\s*mph').firstMatch(s);
    if (two != null) {
      final a = double.tryParse(two.group(1)!);
      final b = double.tryParse(two.group(2)!);
      if (a != null && b != null) return (a + b) / 2.0;
    }
    return null;
  }

  /// points = [{County, State, lat, lon, Population, Cluster}]
  static Future<List<Map<String, dynamic>>> nationalWind({
    required List<Map<String, dynamic>> points,
    int hours = 24,
    int concurrency = 6,
  }) async {
    final results = <Map<String, dynamic>>[];
    final sem = _Semaphore(concurrency);
    final tasks = points.map((c) async {
      await sem.acquire();
      try {
        final w = await windForPoint(
          lat: (c["lat"] as num).toDouble(),
          lon: (c["lon"] as num).toDouble(),
          hours: hours,
        );
        results.add({
          "Cluster": c["Cluster"] ?? "",
          "County": c["County"] ?? "Unknown",
          "State": c["State"] ?? "??",
          "Population": c["Population"] ?? 0,
          "Max Gust (mph)": w["gust_mph"],
          "Max Sustained (mph)": w["sust_mph"],
          "NWS Grid": "${w["office"]} ${w["grid"]}",
          // placeholders your UI expects
          "Wind Outage Probability %": 0.0,
          "Suggested Crews": 0,
          "Predicted Incidents": 0,
          "Predicted Customers Out": 0,
          "Staging Suggestions": "",
          "Primary + Secondary Utilities": "",
          "Predicted Impact Date (peak)": "D0",
          "Threat Level": "Level 0",
        });
      } finally {
        sem.release();
      }
    }).toList();

    await Future.wait(tasks);
    return results;
  }
}

class _Semaphore {
  int _permits;
  final _waiters = <Completer<void>>[];
  _Semaphore(this._permits);
  Future<void> acquire() {
    if (_permits > 0) {
      _permits--;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _permits++;
    }
  }
}
