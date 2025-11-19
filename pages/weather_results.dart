import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../widgets/rugged_button.dart';
import 'package:divergent_alliance/screens/weather_center_pro.dart';

class WeatherResults extends StatefulWidget {
  final String region; // "Southeast", "South Central", "Nationwide"
  final String state; // when not nationwide
  final bool isNationwide;
  final int minWindMph;
  final int daysOut; // 1..10
  final String threatFilter; // Any, Low, Moderate, High, Extreme

  const WeatherResults({
    super.key,
    required this.region,
    required this.state,
    required this.isNationwide,
    required this.minWindMph,
    required this.daysOut,
    required this.threatFilter,
  });

  @override
  State<WeatherResults> createState() => _WeatherResultsState();
}

class _WeatherResultsState extends State<WeatherResults> {
  bool loading = true;
  Map<String, dynamic>? singleData;
  List<_StateSummary>? nationwideRows;

  @override
  void initState() {
    super.initState();
    widget.isNationwide
        ? _loadNationwide(widget.region)
        : _loadSingle(widget.state);
  }

  // 13 state belt with regions
  static const _states = <String, (double lat, double lon, String region)>{
    "Florida": (28.54, -81.38, "Southeast"),
    "Texas": (29.76, -95.36, "South Central"),
    "Louisiana": (29.95, -90.07, "South Central"),
    "Mississippi": (32.30, -90.18, "Southeast"),
    "Alabama": (33.52, -86.81, "Southeast"),
    "Georgia": (33.75, -84.39, "Southeast"),
    "South Carolina": (34.00, -81.04, "Southeast"),
    "North Carolina": (35.78, -78.64, "Southeast"),
    "Virginia": (37.54, -77.43, "Mid-Atlantic"),
    "Tennessee": (36.16, -86.78, "Southeast"),
    "Kentucky": (38.20, -84.87, "Southeast"),
    "West Virginia": (38.35, -81.63, "Mid-Atlantic"),
    "Arkansas": (34.75, -92.27, "South Central"),
  };

  Future<void> _loadNationwide(String regionFilter) async {
    try {
      final entries = (regionFilter == "Nationwide")
          ? _states.entries
          : _states.entries.where((e) => e.value.$3 == regionFilter);

      final futures = entries.map((e) async {
        final (lat, lon, region) = e.value;
        final url = Uri.parse(
          "https://api.open-meteo.com/v1/forecast"
          "?latitude=$lat&longitude=$lon"
          "&daily=wind_speed_10m_max,temperature_2m_max,temperature_2m_min,precipitation_sum"
          "&timezone=auto",
        );
        final resp = await http.get(url);
        if (resp.statusCode != 200) return null;

        final data = json.decode(resp.body) as Map<String, dynamic>;
        final daily = data["daily"] as Map<String, dynamic>;
        final times = List<String>.from(daily["time"]);
        final windKph = List<double>.from(daily["wind_speed_10m_max"]);
        final n = times.isEmpty ? 0 : (widget.daysOut.clamp(1, times.length));

        double maxMph = -1;
        int maxIdx = 0;
        for (var i = 0; i < n; i++) {
          final mph = windKph[i] * 0.621371;
          if (mph > maxMph) {
            maxMph = mph;
            maxIdx = i;
          }
        }

        final threat = _threatFrom(maxMph);
        return _StateSummary(
          state: e.key,
          region: region,
          date: times.isEmpty ? "" : times[maxIdx],
          maxWindMph: maxMph,
          crews: _crewSuggest(threat),
          color: _color(threat),
          threat: threat,
          lat: lat,
          lon: lon,
        );
      }).toList();

      final results = await Future.wait(futures);
      var rows = results.whereType<_StateSummary>().toList();

      // wind filter
      rows = rows.where((r) => r.maxWindMph >= widget.minWindMph).toList();

      // threat filter, strict
      if (widget.threatFilter != "Any") {
        rows = rows.where((r) => r.threat == widget.threatFilter).toList();
      }

      rows.sort((a, b) => b.maxWindMph.compareTo(a.maxWindMph));

      setState(() {
        nationwideRows = rows;
        loading = false;
      });
    } catch (_) {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> _loadSingle(String state) async {
    final (lat, lon, _) = _states[state] ?? (39.50, -98.35, "Nationwide");
    final url = Uri.parse(
      "https://api.open-meteo.com/v1/forecast"
      "?latitude=$lat&longitude=$lon"
      "&daily=wind_speed_10m_max,temperature_2m_max,temperature_2m_min,precipitation_sum"
      "&timezone=auto",
    );
    try {
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        setState(() {
          singleData = json.decode(resp.body);
          loading = false;
        });
      } else {
        setState(() {
          loading = false;
        });
      }
    } catch (_) {
      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isNationwide
        ? (widget.region == "Nationwide"
            ? "Forecast, Nationwide"
            : "Forecast, ${widget.region}")
        : "Forecast, ${widget.state}";
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : widget.isNationwide
              ? _NationwideList(rows: nationwideRows ?? const [])
              : (singleData == null)
                  ? const Center(
                      child: Text("No forecast available",
                          style: TextStyle(color: Colors.white70)))
                  : _StateDailyList(
                      data: singleData!,
                      minWind: widget.minWindMph,
                      daysOut: widget.daysOut,
                      threatFilter: widget.threatFilter,
                    ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: RuggedButton(
          label: "Change Filters",
          icon: Icons.tune,
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }

  static String _threatFrom(double mph) {
    if (mph >= 60) return "Extreme";
    if (mph >= 45) return "High";
    if (mph >= 30) return "Moderate";
    return "Low";
  }

  static int _crewSuggest(String t) {
    switch (t) {
      case "Extreme":
        return 30;
      case "High":
        return 20;
      case "Moderate":
        return 8;
      default:
        return 3;
    }
  }

  static Color _color(String t) {
    switch (t) {
      case "Extreme":
        return const Color(0xFF880E4F);
      case "High":
        return const Color(0xFFB71C1C);
      case "Moderate":
        return const Color(0xFF8E8E00);
      default:
        return const Color(0xFF1B5E20);
    }
  }
}

class _NationwideList extends StatelessWidget {
  final List<_StateSummary> rows;
  const _NationwideList({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(
        child: Text("No states match the selected wind and threat filters.",
            style: TextStyle(color: Colors.white70)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final r = rows[i];
        return Card(
          color: r.color.withValues(alpha: 0.14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: r.color.withValues(alpha: 0.65)),
          ),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(
              "${r.state}  ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢  ${r.region}  ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢  ${r.threat}",
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "Max Wind: ${r.maxWindMph.toStringAsFixed(0)} mph  ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢  Date: ${r.date}\n"
                "Suggested Crews: ${r.crews}",
                style: const TextStyle(color: Colors.white70, height: 1.3),
              ),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WeatherResults(
                    region: r.region,
                    state: r.state,
                    isNationwide: false,
                    minWindMph: 10,
                    daysOut: 7,
                    threatFilter: "Any",
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _StateDailyList extends StatelessWidget {
  final Map<String, dynamic> data;
  final int minWind;
  final int daysOut;
  final String threatFilter;
  const _StateDailyList({
    required this.data,
    required this.minWind,
    required this.daysOut,
    required this.threatFilter,
  });

  @override
  Widget build(BuildContext context) {
    final daily = data["daily"];
    final times = List<String>.from(daily["time"]);
    final windKph = List<double>.from(daily["wind_speed_10m_max"]);
    final tmax = List<double>.from(daily["temperature_2m_max"]);
    final tmin = List<double>.from(daily["temperature_2m_min"]);
    final precip = List<double>.from(daily["precipitation_sum"]);
    final n = times.isEmpty ? 0 : daysOut.clamp(1, times.length);

    final rows = <_DayRow>[];
    for (var i = 0; i < n; i++) {
      final mph = windKph[i] * 0.621371;
      final thr = _threat(mph);
      if (mph < minWind) continue;
      if (threatFilter != "Any" && thr != threatFilter) continue;
      rows.add(_DayRow(times[i], mph, precip[i], tmax[i], tmin[i], thr));
    }

    if (rows.isEmpty) {
      return const Center(
        child: Text("No days match the selected wind and threat filters.",
            style: TextStyle(color: Colors.white70)),
      );
    }

    rows.sort((a, b) => _rank(b.threat).compareTo(_rank(a.threat)));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final r = rows[i];
        final color = _color(r.threat);
        return Card(
          color: color.withValues(alpha: 0.16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: color.withValues(alpha: 0.65)),
          ),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(
              "${r.date}  ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢  ${r.threat}",
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "Wind: ${r.windMph.toStringAsFixed(0)} mph   "
                "Precip: ${r.precipMm.toStringAsFixed(1)} mm   "
                "High: ${r.tHighC.toStringAsFixed(1)}ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°C  Low: ${r.tLowC.toStringAsFixed(1)}ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°C\n"
                "Suggested Crews: ${_crewSuggest(r.threat)}",
                style: const TextStyle(color: Colors.white70, height: 1.3),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _threat(double mph) {
    if (mph >= 60) return "Extreme";
    if (mph >= 45) return "High";
    if (mph >= 30) return "Moderate";
    return "Low";
  }

  static int _rank(String t) =>
      {"Low": 1, "Moderate": 2, "High": 3, "Extreme": 4}[t] ?? 0;

  static Color _color(String t) {
    switch (t) {
      case "Extreme":
        return const Color(0xFF880E4F);
      case "High":
        return const Color(0xFFB71C1C);
      case "Moderate":
        return const Color(0xFF8E8E00);
      default:
        return const Color(0xFF1B5E20);
    }
  }

  static int _crewSuggest(String t) {
    switch (t) {
      case "Extreme":
        return 30;
      case "High":
        return 20;
      case "Moderate":
        return 8;
      default:
        return 3;
    }
  }
}

class _StateSummary {
  final String state, region, date, threat;
  final double maxWindMph, lat, lon;
  final int crews;
  final Color color;
  _StateSummary({
    required this.state,
    required this.region,
    required this.date,
    required this.maxWindMph,
    required this.crews,
    required this.color,
    required this.threat,
    required this.lat,
    required this.lon,
  });
}

class _DayRow {
  final String date, threat;
  final double windMph, precipMm, tHighC, tLowC;
  _DayRow(this.date, this.windMph, this.precipMm, this.tHighC, this.tLowC,
      this.threat);
}
