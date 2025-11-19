import 'package:flutter/material.dart';
import '../widgets/da_button_compat.dart';

class WeatherCenterGate extends StatelessWidget {
  const WeatherCenterGate({super.key});

  void _runForecast(BuildContext context) {
    debugPrint('Run Forecast from WeatherCenterGate');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Weather Center')),
      body: const Center(child: Text('Filters go here')),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: DAButton(
            onPressed: () => _runForecast(context),
            child: const Text('Run Forecast'),
          ),
        ),
      ),
    );
  }
}
