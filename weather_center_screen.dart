import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../../data/weather_service.dart';

enum Units { imperial, metric }

class WeatherFilters {
  final Units units;
  final int hours;
  final bool precipOnly;
  final double windMinMph;
  final bool alertsOnly;

  const WeatherFilters({
    this.units = Units.imperial,
    this.hours = 24,
    this.precipOnly = false,
    this.windMinMph = 0,
    this.alertsOnly = false,
  });

  WeatherFilters copyWith({
    Units? units,
    int? hours,
    bool? precipOnly,
    double? windMinMph,
    bool? alertsOnly,
  }) =>
      WeatherFilters(
        units: units ?? this.units,
        hours: hours ?? this.hours,
        precipOnly: precipOnly ?? this.precipOnly,
        windMinMph: windMinMph ?? this.windMinMph,
        alertsOnly: alertsOnly ?? this.alertsOnly,
      );
}

class WeatherCenterScreen extends StatefulWidget {
  const WeatherCenterScreen({super.key});

  @override
  State<WeatherCenterScreen> createState() => _WeatherCenterScreenState();
}

class _WeatherCenterScreenState extends State<WeatherCenterScreen> {
  final _nws = NwsService();
  WeatherFilters _filters = const WeatherFilters();
  bool _loading = true;
  String? _error;
  List<NwsPeriod> _hourly = const [];
  List<NwsPeriod> _forecast = const [];
  List<NwsAlert> _alerts = const [];
  double? _lat;
  double? _lon;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final locEnabled = await Geolocator.isLocationServiceEnabled();
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
      if (!locEnabled || (perm == LocationPermission.denied || perm == LocationPermission.deniedForever)) {
        throw Exception('Location permission is required for accurate weather.');
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _lat = pos.latitude;
      _lon = pos.longitude;

      final p = await _nws.getPoint(_lat!, _lon!);
      final forecast = await _nws.getForecast(p.forecastUrl);
      final hourly = await _nws.getHourly(p.hourlyUrl);
      final alerts = await _nws.getActiveAlerts(_lat!, _lon!);

      setState(() {
        _forecast = forecast;
        _hourly = hourly;
        _alerts = alerts;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<NwsPeriod> _applyFilters(List<NwsPeriod> src) {
    final now = DateTime.now().toUtc();
    final limit = now.add(Duration(hours: _filters.hours));
    bool isWindAbove(String windSpeedStr, double mphMin) {
      final nums = RegExp(r'(\d+(\.\d+)?)')
          .allMatches(windSpeedStr)
          .map((m) => double.tryParse(m.group(0)!) ?? 0)
          .toList();
      final maxVal = nums.isEmpty ? 0 : nums.reduce(max);
      return maxVal >= mphMin;
    }

    return src.where((p) {
      if (p.startTime.isAfter(limit)) return false;
      if (_filters.precipOnly && ((p.pop ?? 0) <= 0)) return false;
      if (_filters.windMinMph > 0 && !isWindAbove(p.windSpeed, _filters.windMinMph)) return false;
      return true;
    }).toList();
  }

  String _fmtTemp(int? t, String unit) {
    if (t == null) return '--';
    if (_filters.units == Units.imperial) {
      return '$tÂ°F';
    } else {
      final c = unit == 'F' ? ((t - 32) * 5 / 9).round() : t;
      return '$cÂ°C';
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE h a');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather Center'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: [
                    if (_alerts.isNotEmpty)
                      MaterialBanner(
                        backgroundColor: Colors.amber.shade100,
                        content: Text(
                          _alerts.map((a) => a.event).toSet().join(' â€¢ '),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        actions: [
                          TextButton(
                            child: const Text('Details'),
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                showDragHandle: true,
                                isScrollControlled: true,
                                builder: (ctx) => ListView.separated(
                                  padding: const EdgeInsets.all(16),
                                  itemBuilder: (_, i) {
                                    final a = _alerts[i];
                                    return ListTile(
                                      title: Text(a.headline),
                                      subtitle: Text(a.description),
                                    );
                                  },
                                  separatorBuilder: (_, __) => const Divider(),
                                  itemCount: _alerts.length,
                                ),
                              );
                            },
                          )
                        ],
                      ),
                    _FiltersBar(
                      value: _filters,
                      onChanged: (v) => setState(() => _filters = v),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Next ${_filters.hours} hours',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._applyFilters(_hourly).map((p) {
                            return ListTile(
                              leading: Icon(
                                (p.pop ?? 0) >= 50 ? Icons.umbrella : Icons.wb_sunny_outlined,
                              ),
                              title: Text('${df.format(p.startTime.toLocal())} â€¢ ${p.shortForecast}'),
                              subtitle: Text('Wind ${p.windDirection} ${p.windSpeed}'
                                  '${(p.pop ?? 0) > 0 ? ' â€¢ POP ${(p.pop ?? 0).round()}%' : ''}'),
                              trailing: Text(_fmtTemp(p.temperature, p.temperatureUnit)),
                            );
                          }),
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text('Extended', style: Theme.of(context).textTheme.titleMedium),
                          ),
                          const SizedBox(height: 8),
                          ..._applyFilters(_forecast).map((p) => ListTile(
                                title: Text('${p.name}: ${p.shortForecast}'),
                                trailing: Text(_fmtTemp(p.temperature, p.temperatureUnit)),
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _FiltersBar extends StatelessWidget {
  final WeatherFilters value;
  final ValueChanged<WeatherFilters> onChanged;
  const _FiltersBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        DropdownButton<int>(
          value: value.hours,
          onChanged: (h) => onChanged(value.copyWith(hours: h)),
          items: const [6, 12, 24, 48, 72]
              .map((h) => DropdownMenuItem<int>(value: h, child: Text('$h h')))
              .toList(),
        ),
        ChoiceChip(
          label: const Text('Imperial'),
          selected: value.units == Units.imperial,
          onSelected: (_) => onChanged(value.copyWith(units: Units.imperial)),
        ),
        ChoiceChip(
          label: const Text('Metric'),
          selected: value.units == Units.metric,
          onSelected: (_) => onChanged(value.copyWith(units: Units.metric)),
        ),
        FilterChip(
          label: const Text('Precip only'),
          selected: value.precipOnly,
          onSelected: (s) => onChanged(value.copyWith(precipOnly: s)),
        ),
        FilterChip(
          label: Text('Wind â‰¥ ${value.windMinMph.round()} mph'),
          selected: value.windMinMph > 0,
          onSelected: (s) => onChanged(value.copyWith(windMinMph: s ? 20 : 0)),
          onDeleted: value.windMinMph > 0 ? () => onChanged(value.copyWith(windMinMph: 0)) : null,
        ),
        FilterChip(
          label: const Text('Alerts only'),
          selected: value.alertsOnly,
          onSelected: (s) => onChanged(value.copyWith(alertsOnly: s)),
        ),
      ],
    );
  }
}