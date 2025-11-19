// lib/screens/weather_probe.dart
import 'package:flutter/material.dart';
import '../services/wx_api.dart'; // relative import avoids package-name mismatch

class WeatherProbe extends StatefulWidget {
  const WeatherProbe({super.key});
  @override
  State<WeatherProbe> createState() => _WeatherProbeState();
}

class _WeatherProbeState extends State<WeatherProbe> {
  String status = 'checking...';
  List<Map<String, dynamic>> rows = const [];

  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    final h = await WxApi.health();
    final data =
        await WxApi.national(windMph: 35, horizonHours: 48, state: 'TX');
    setState(() {
      status = 'health: ' + h;
      rows = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Probe')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(status),
              const SizedBox(height: 12),
              Text('rows: '),
            ],
          ),
        ),
      ),
    );
  }
}
