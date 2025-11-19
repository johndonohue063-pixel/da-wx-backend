import 'dart:async';
import 'dart:io' show Platform;
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb, debugPrint;
import 'package:http/http.dart' as http;

class WxApi {
  WxApi._();

  static String? _base;

  static void discover({String? overrideBase}) {
    _base = overrideBase ?? _defaultBase();
  }

  static String _defaultBase() {
    if (kIsWeb) return 'http://localhost:8010';
    if (Platform.isAndroid) return 'http://10.0.2.2:8010';
    return 'http://127.0.0.1:8010';
  }

  static String get baseUrl => _base ?? _defaultBase();

  static const _timeout = Duration(seconds: 60);

  static Uri _build(String path, Map<String, String?> qp) {
    return Uri.parse('$baseUrl$path').replace(
      queryParameters: {
        for (final e in qp.entries)
          if (e.value != null) e.key: e.value!,
      },
    );
  }

  static Future<String> _getText(Uri uri) async { debugPrint("[WxApi] GET $uri");
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.reasonPhrase}');
    }
    return res.body;
  }

  static Future<List<Map<String, dynamic>>> nationalSmart({
    required String region,
    required int maxZones,
    required int threshold,
    required int horizonHours,
    required int windMph,
    String? state,
  }) async {
    final uri = nationalRequestUri(
      region: region,
      maxZones: maxZones,
      threshold: threshold,
      horizonHours: horizonHours,
      windMph: windMph,
      state: state,
      format: 'csv',
    );
    final csvText = await _getText(uri);
    final rows = await compute(_parseCsvToMaps, csvText);
    return rows;
  }

  static Uri nationalRequestUri({
    required String region,
    required int maxZones,
    required int threshold,
    required int horizonHours,
    required int windMph,
    String? state,
    String format = 'csv',
  }) {
    return _build('/report/national', {
      'region': region,
      'max_zones': '$maxZones',
      'threshold': '$threshold',
      'timeline': '$horizonHours',
      'wind_mph': '$windMph',
      'state': state?.trim().isEmpty == true ? null : state,
      'format': format,
    });
  }

  static Uri nationalCsvUri({
    required String region,
    required int maxZones,
    required int threshold,
    required int horizonHours,
    required int windMph,
    String? state,
  }) =>
      nationalRequestUri(
        region: region,
        maxZones: maxZones,
        threshold: threshold,
        horizonHours: horizonHours,
        windMph: windMph,
        state: state,
        format: 'csv',
      );
}

List<Map<String, dynamic>> _parseCsvToMaps(String csvText) {
  if (csvText.trim().isEmpty) return const [];
  final rows = const CsvToListConverter(
    eol: '\n',
    shouldParseNumbers: false,
  ).convert(csvText);
  if (rows.isEmpty) return const [];
  final header = rows.first.map((e) => (e ?? '').toString().trim()).toList();
  final out = <Map<String, dynamic>>[];
  for (var i = 1; i < rows.length; i++) {
    final r = rows[i];
    if (r.isEmpty) continue;
    final m = <String, dynamic>{};
    for (var j = 0; j < header.length && j < r.length; j++) {
      m[header[j]] = r[j];
    }
    out.add(m);
  }
  return out;
}


