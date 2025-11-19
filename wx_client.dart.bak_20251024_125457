import "dart:convert";
import "dart:typed_data";
import "package:http/http.dart" as http;

/// Lightweight client for fetching national CSV and building URIs.
/// Only the minimal surface used by the app is implemented.
class WxClient {
  static String _base = "https://example.com";

  /// Optionally override the base URL discovered elsewhere.
  static void discover({String? overrideBase}) {
    if (overrideBase != null && overrideBase.isNotEmpty) {
      _base = overrideBase;
    }
  }

  /// Build the URI for the national CSV endpoint.
  static Uri nationalUri({
    String path = "/api/national.csv",
    Map<String, String>? params,
  }) {
    final base = Uri.parse(_base);
    return base.replace(
      path: path,
      queryParameters: params == null || params.isEmpty ? null : params,
    );
  }

  /// Fetch and parse the national CSV.
  static Future<List<Map<String, dynamic>>> nationalCsv({
    Map<String, String>? params,
    String path = "/api/national.csv",
  }) async {
    final uri = nationalUri(path: path, params: params);
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      return const [];
    }
    final text = _decodeBody(resp.bodyBytes, resp.headers["content-type"]);
    if (text.trim().isEmpty) return const [];
    return _parseCsv(text);
  }

  // ---------- helpers ----------

  static String _decodeBody(Uint8List bytes, String? contentType) {
    // Honor charset if provided, else UTF-8.
    final ct = contentType ?? "";
    final m = RegExp(r"charset=([A-Za-z0-9_\-]+)", caseSensitive: false)
        .firstMatch(ct);
    final cs = (m != null) ? m.group(1)!.toLowerCase() : "utf-8";
    try {
      switch (cs) {
        case "latin1":
        case "iso-8859-1":
          return latin1.decode(bytes);
        default:
          return utf8.decode(bytes);
      }
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  /// Simple CSV parser with BOM strip, quote handling, and header mapping.
  static List<Map<String, dynamic>> _parseCsv(String csv) {
    if (csv.isEmpty) return const [];
    // Normalize newlines and strip BOM from first line if present.
    final rawLines =
        csv.replaceAll("\r\n", "\n").replaceAll("\r", "\n").split("\n");
    if (rawLines.isEmpty) return const [];
    if (rawLines[0].isNotEmpty && rawLines[0].codeUnitAt(0) == 0xFEFF) {
      rawLines[0] = rawLines[0].substring(1);
    }

    // Parse CSV rows (supporting quoted fields with commas and double quotes)
    List<List<String>> rows = [];
    for (final line in rawLines) {
      if (line.isEmpty) continue;
      rows.add(_splitCsvLine(line));
    }
    if (rows.isEmpty) return const [];

    final header = rows.first;
    final data = <Map<String, dynamic>>[];
    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      if (r.isEmpty) continue;
      final m = <String, dynamic>{};
      for (var c = 0; c < header.length; c++) {
        final key = header[c];
        final val = c < r.length ? r[c] : "";
        m[key] = val;
      }
      data.add(m);
    }
    return data;
  }

  /// Split a single CSV line into fields, handling quotes and escapes.
  static List<String> _splitCsvLine(String line) {
    final out = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"') {
          final peek = (i + 1 < line.length) ? line[i + 1] : null;
          if (peek == '"') {
            // Escaped quote ("")
            sb.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          sb.write(ch);
        }
      } else {
        if (ch == ',') {
          out.add(sb.toString());
          sb.clear();
        } else if (ch == '"') {
          inQuotes = true;
        } else {
          sb.write(ch);
        }
      }
    }
    out.add(sb.toString());
    return out;
  }
}
