import "package:flutter/material.dart";
import "../ui/da_button.dart";
import "../services/wx_client.dart";
import "../screens/weather_center_gate.dart";

// ===================== SPP Row Model =====================
class SppRow {
  final String cluster;
  final String county;
  final String state;
  final double prob; // Wind Outage Probability %
  final int population;
  final int suggestedCrews;
  final int predictedIncidents;
  final int predictedCustomersOut;
  final String staging;
  final String utilities;
  final String peakDate;
  final int threatLevel; // 0..3
  final double? maxGust; // optional
  final double? maxSustained; // optional

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? "") ?? 0;
  }

  SppRow.fromJson(Map<String, dynamic> j)
      : cluster = (j["Cluster"] ?? "").toString(),
        county = (j["County"] ?? "").toString(),
        state = (j["State"] ?? "").toString(),
        prob = _asDouble(j["Wind Outage Probability %"] ?? j["prob"] ?? 0) ?? 0,
        population = _asInt(j["Population"]),
        suggestedCrews = _asInt(j["Suggested Crews"]),
        predictedIncidents = _asInt(j["Predicted Incidents"]),
        predictedCustomersOut = _asInt(j["Predicted Customers Out"]),
        staging = (j["Staging Suggestions"] ?? "").toString(),
        utilities = (j["Primary + Secondary Utilities"] ?? "").toString(),
        peakDate = (j["Predicted Impact Date (peak)"] ?? "").toString(),
        threatLevel = _asInt(j["Threat Level"] ?? j["threat"] ?? 0),
        maxGust = _asDouble(j["Max Gust"] ?? j["max_gust"] ?? j["gust"]),
        maxSustained = _asDouble(
            j["Max Sustained"] ?? j["max_sustained"] ?? j["sustained"]);
}

// ===================== Modes =====================
enum ScopeMode { nationwide, region, state }

enum FilterMode { wind, threat }

// ===================== Screen =====================
class WeatherCenter extends StatefulWidget {
  static const route = "/weather-center";
  const WeatherCenter({super.key});
  @override
  State<WeatherCenter> createState() => _WeatherCenterState();
}

class _WeatherCenterState extends State<WeatherCenter> {
  // ---- Scope lists (wind-first regions) ----
  final Map<String, List<String>> regionStates = const {
    "Gulf": ["Texas", "Louisiana", "Mississippi", "Alabama", "Florida"],
    "Southeast": [
      "Florida",
      "Georgia",
      "South Carolina",
      "North Carolina",
      "Tennessee",
      "Alabama",
      "Mississippi"
    ],
    "East Coast": [
      "Florida",
      "Georgia",
      "South Carolina",
      "North Carolina",
      "Virginia",
      "Maryland",
      "Delaware",
      "New Jersey",
      "New York",
      "Connecticut",
      "Rhode Island",
      "Massachusetts"
    ],
    "Midwest": [
      "Illinois",
      "Indiana",
      "Ohio",
      "Michigan",
      "Wisconsin",
      "Minnesota",
      "Missouri",
      "Iowa"
    ],
    "West": [
      "California",
      "Oregon",
      "Washington",
      "Nevada",
      "Arizona",
      "Utah",
      "Colorado",
      "New Mexico"
    ],
  };

  // ---- Scope state ----
  ScopeMode _scope = ScopeMode.nationwide;
  String region = "Nationwide";
  String? stateSel;
  int daysOut = 0;

  // ---- Filter state (exclusive) ----
  FilterMode _mode = FilterMode.wind;
  double probability = 35; // Wind slider
  int? _threatOverride; // Threat override; null = Auto(backend)

  // ---- Derived/backend ----
  List<SppRow> _rows = [];
  bool _loading = false;
  bool _hasRun = false;
  String? _runNote;
  int _derivedThreat = 0;
  int _derivedCrews = 0;
  String _derivedStaging = "";
  double? _maxGust;
  double? _maxSustained;
  bool crewsEstimate = true;

  @override
  void initState() {
    super.initState();
    // PIN gate guard
    if (WeatherCenterGate.authorized != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, WeatherCenterGate.route);
      });
    }
  }

  // ---- Helpers ----
  List<String> currentStatesForRegion(String r) =>
      regionStates[r] ?? const <String>[];

  int threatLevelFallback(double p) {
    if (p >= 45) return 3;
    if (p >= 30) return 2;
    if (p >= 20) return 1;
    return 0;
  }

  String threatLabel(int lvl) => switch (lvl) {
        3 => "Level 3",
        2 => "Level 2",
        1 => "Level 1",
        _ => "Level 0"
      };

  Color threatColor(int lvl) => switch (lvl) {
        3 => const Color(0xFFB00020),
        2 => const Color(0xFFFF6A00),
        1 => const Color(0xFFFFC107),
        _ => const Color(0xFF64B5F6),
      };

  int estimateCrewsFallback(double p) {
    final lvl = threatLevelFallback(p);
    const base = [0, 100, 300, 600]; // Nationwide fallback scale
    return base[lvl];
  }

  String _scopeLabel() => (_scope == ScopeMode.state && stateSel != null)
      ? "by State"
      : (_scope == ScopeMode.region && region != "Nationwide")
          ? "by Region"
          : "by Nationwide";

  String _fixText(String s) {
    return s
        .replaceAll("Ã¢â€šÂ¬", "€")
        .replaceAll("â€¢", "•")
        .replaceAll("Ã¢â‚¬â€œ", "–")
        .replaceAll("Ã¢â‚¬â¢", "•")
        .replaceAll("Ã¢â‚¬", "—");
  }

  Future<void> _run() async {
    if (WeatherCenterGate.authorized != true) {
      Navigator.pushReplacementNamed(context, WeatherCenterGate.route);
      return;
    }
    setState(() {
      _loading = true;
      _hasRun = true;
      _runNote = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("Running forecast…"),
          duration: Duration(milliseconds: 900)),
    );

    try {
      // Your backend call (no params)
      final List<Map<String, dynamic>> data = await WxClient.nationalCsv();
      final rows = data.map((e) => SppRow.fromJson(e)).toList()
        ..sort((a, b) =>
            b.predictedCustomersOut.compareTo(a.predictedCustomersOut));

      // Backend threat level
      final lvlFromBackend = rows.isEmpty
          ? 0
          : rows.map((e) => e.threatLevel).reduce((a, b) => a > b ? a : b);

      // Crews by scope
      int crews = 0;
      if (rows.isNotEmpty) {
        if (_scope == ScopeMode.state && stateSel != null) {
          crews = rows
              .where((r) => r.state == stateSel)
              .fold(0, (s, r) => s + r.suggestedCrews);
        } else if (_scope == ScopeMode.region && region != "Nationwide") {
          final states = currentStatesForRegion(region);
          crews = rows
              .where((r) => states.contains(r.state))
              .fold(0, (s, r) => s + r.suggestedCrews);
        } else {
          crews = rows.fold(0, (s, r) => s + r.suggestedCrews);
        }
      }

      // Wind metrics
      final gusts = rows.map((r) => r.maxGust).whereType<double>().toList();
      final susts =
          rows.map((r) => r.maxSustained).whereType<double>().toList();
      final maxGust =
          gusts.isEmpty ? null : gusts.reduce((a, b) => a > b ? a : b);
      final maxSustained =
          susts.isEmpty ? null : susts.reduce((a, b) => a > b ? a : b);

      setState(() {
        _rows = rows;
        probability = rows.isEmpty ? probability : rows.first.prob;
        _derivedThreat = lvlFromBackend;
        _derivedCrews = crews;
        _derivedStaging = rows.isNotEmpty
            ? rows.first.staging
            : "Nationwide posture • maintain rapid-deploy crews at key logistics hubs.";
        _maxGust = maxGust;
        _maxSustained = maxSustained;
        _runNote = rows.isEmpty
            ? "No forecast rows returned for this selection. Adjust scope or days, then try again."
            : null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Forecast updated"),
            duration: Duration(milliseconds: 900)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _runNote = "Error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Badge: in Threat mode respect override; otherwise backend/fallback
    final lvl = (_mode == FilterMode.threat)
        ? (_threatOverride ??
            (_rows.isEmpty ? threatLevelFallback(probability) : _derivedThreat))
        : (_rows.isEmpty ? threatLevelFallback(probability) : _derivedThreat);
    final badgeColor = threatColor(lvl);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Weather Center"),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(.18),
              border: Border.all(color: badgeColor, width: 1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              const Icon(Icons.bolt_rounded, size: 16),
              const SizedBox(width: 6),
              Text(threatLabel(lvl),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ===== Scope =====
            Align(
                alignment: Alignment.centerLeft,
                child: Text("Scope",
                    style: Theme.of(context).textTheme.labelLarge)),
            const SizedBox(height: 8),
            ToggleButtons(
              isSelected: [
                _scope == ScopeMode.nationwide,
                _scope == ScopeMode.region,
                _scope == ScopeMode.state,
              ],
              onPressed: (i) => setState(() {
                _scope = ScopeMode.values[i];
                if (_scope != ScopeMode.region) region = "Nationwide";
                if (_scope != ScopeMode.state) stateSel = null;
              }),
              borderRadius: BorderRadius.circular(12),
              children: const [
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text("Nationwide")),
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text("Region")),
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text("State")),
              ],
            ),
            const SizedBox(height: 8),

            if (_scope == ScopeMode.region) ...[
              DropdownButtonFormField<String>(
                value: region == "Nationwide" ? null : region,
                decoration: const InputDecoration(labelText: "Region"),
                items: regionStates.keys
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setState(() {
                  region = v ?? "Nationwide";
                  stateSel = null;
                }),
              ),
            ],

            if (_scope == ScopeMode.state) ...[
              DropdownButtonFormField<String>(
                value: stateSel,
                decoration: const InputDecoration(labelText: "State"),
                items: regionStates.values
                    .expand((lst) => lst)
                    .toSet()
                    .toList()
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => stateSel = v),
              ),
            ],

            const SizedBox(height: 12),

            // ===== Forecast window =====
            Align(
                alignment: Alignment.centerLeft,
                child: Text("Forecast window",
                    style: Theme.of(context).textTheme.labelLarge)),
            Row(children: [
              const Expanded(child: Text("Days out")),
              Text("${daysOut} d",
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            Slider(
                min: 0,
                max: 10,
                divisions: 10,
                value: daysOut.toDouble(),
                label: daysOut.toString(),
                onChanged: (v) => setState(() => daysOut = v.round())),

            const SizedBox(height: 12),

            // ===== Filter (exclusive) =====
            Align(
                alignment: Alignment.centerLeft,
                child: Text("Filter",
                    style: Theme.of(context).textTheme.labelLarge)),
            ToggleButtons(
              isSelected: [
                _mode == FilterMode.wind,
                _mode == FilterMode.threat
              ],
              onPressed: (i) => setState(() => _mode = FilterMode.values[i]),
              borderRadius: BorderRadius.circular(12),
              children: const [
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text("Wind")),
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text("Threat")),
              ],
            ),
            const SizedBox(height: 12),

            if (_mode == FilterMode.wind) ...[
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      "Wind Outage Probability: ${probability.toStringAsFixed(0)}%")),
              Slider(
                  min: 0,
                  max: 100,
                  divisions: 100,
                  value: probability,
                  onChanged: (v) => setState(() => probability = v)),
            ],

            if (_mode == FilterMode.threat) ...[
              DropdownButtonFormField<String>(
                value: _threatOverride == null
                    ? 'Auto'
                    : 'Level ${_threatOverride}',
                decoration: const InputDecoration(labelText: 'Threat level'),
                items: const [
                  DropdownMenuItem(
                      value: 'Auto', child: Text('Auto (backend)')),
                  DropdownMenuItem(value: 'Level 0', child: Text('Level 0')),
                  DropdownMenuItem(value: 'Level 1', child: Text('Level 1')),
                  DropdownMenuItem(value: 'Level 2', child: Text('Level 2')),
                  DropdownMenuItem(value: 'Level 3', child: Text('Level 3')),
                ],
                onChanged: (v) => setState(() {
                  if (v == null || v == 'Auto')
                    _threatOverride = null;
                  else
                    _threatOverride = int.parse(v.split(' ').last);
                }),
              ),
            ],

            const SizedBox(height: 12),

            // ===== Operational summary =====
            Align(
                alignment: Alignment.centerLeft,
                child: Text("Operational summary",
                    style: Theme.of(context).textTheme.labelLarge)),
            _cardsRow(
              context,
              threat: threatLabel(lvl),
              threatColor: badgeColor,
              crews: _rows.isEmpty
                  ? (crewsEstimate
                      ? "${estimateCrewsFallback(probability)}"
                      : "—")
                  : "$_derivedCrews",
              staging: _fixText(_derivedStaging),
              scopeLabel: stateSel ?? region,
            ),

            // ===== Wind metrics (backend) =====
            if (_maxGust != null || _maxSustained != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(.08)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Max gust: ${_maxGust?.toStringAsFixed(0) ?? '—'}"),
                    Text(
                        "Max sustained: ${_maxSustained?.toStringAsFixed(0) ?? '—'}"),
                  ],
                ),
              ),
            ],

            if (_hasRun &&
                !_loading &&
                (_rows.isEmpty || _runNote != null)) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.04),
                  border: Border.all(color: Colors.white.withOpacity(.08)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_runNote ??
                    "No forecast rows returned for this selection. Adjust scope or days, then try again."),
              ),
            ],

            const SizedBox(height: 12),

            // ===== Top predicted customers out =====
            Align(
                alignment: Alignment.centerLeft,
                child: Text("Top predicted customers out",
                    style: Theme.of(context).textTheme.labelLarge)),
            _BarPreviewCard(
              items: _rows
                  .take(6)
                  .map((r) => {
                        "name": "${r.county} (${r.state})",
                        "out": r.predictedCustomersOut
                      })
                  .toList(),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: DAButton(
                label: "Run Forecast",
                icon: Icons.analytics,
                onPressed: _loading ? null : () => _run(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== UI helpers =====================
  Widget _cardsRow(
    BuildContext context, {
    required String threat,
    required Color threatColor,
    required String crews,
    required String staging,
    required String scopeLabel,
  }) {
    final cards = <Widget>[
      _InfoCard(
          title: "Threat",
          body: threat,
          accent: threatColor,
          subtitle: "Wind outage risk"),
      _InfoCard(
          title: "Suggested Additional Crews",
          body: crews,
          accent: const Color(0xFFFF6A00),
          subtitle: _scopeLabel()),
      _InfoCard(
          title: "Staging",
          body: scopeLabel,
          accent: Colors.tealAccent,
          subtitle: staging),
    ];

    return LayoutBuilder(builder: (ctx, c) {
      if (c.maxWidth < 540) {
        return Column(
          children: cards
              .map((w) =>
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: w))
              .toList(),
        );
      } else {
        return Row(children: [
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.only(right: 12), child: cards[0])),
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.only(right: 12), child: cards[1])),
          Expanded(child: cards[2]),
        ]);
      }
    });
  }
}

// ===================== Support widgets =====================
class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {required this.title,
      required this.body,
      required this.accent,
      required this.subtitle});

  final String title;
  final String body;
  final Color accent;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(.08)),
        boxShadow: const [
          BoxShadow(
              blurRadius: 22,
              spreadRadius: -6,
              offset: Offset(0, 10),
              color: Colors.black54),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
        const SizedBox(height: 6),
        Row(children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(body,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 6),
        Text(subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.white60)),
      ]),
    );
  }
}

class _BarPreviewCard extends StatelessWidget {
  const _BarPreviewCard({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.bar_chart, size: 16),
          SizedBox(width: 6),
          Text("Top predicted customers out",
              style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        SizedBox(
            height: 140, child: CustomPaint(painter: _MiniBarPainter(items))),
      ]),
    );
  }
}

class _MiniBarPainter extends CustomPainter {
  _MiniBarPainter(this.items);
  final List<Map<String, dynamic>> items;

  @override
  void paint(Canvas canvas, Size size) {
    final bars = items.take(6).toList();
    if (bars.isEmpty) return;

    final maxOut = bars
        .map((e) => (e["out"] as int))
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    final barW = size.width / (bars.length * 1.6);
    final paint = Paint()..isAntiAlias = true;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < bars.length; i++) {
      final x = (i * 1.6 + .3) * barW;
      final h = maxOut == 0
          ? 0
          : (bars[i]["out"] as int) / maxOut * (size.height - 28);
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - h - 18, barW, h),
        const Radius.circular(6),
      );
      final shader =
          const LinearGradient(colors: [Color(0xFFFFB15A), Color(0xFFFF6A00)])
              .createShader(r.outerRect);
      paint..shader = shader;
      canvas.drawRRect(r, paint);

      final label = TextSpan(
          text: "${bars[i]["out"]}",
          style: const TextStyle(fontSize: 10, color: Colors.white70));
      textPainter.text = label;
      textPainter.layout(minWidth: 0, maxWidth: barW * 1.5);
      textPainter.paint(canvas, Offset(x - 2, size.height - 16));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
