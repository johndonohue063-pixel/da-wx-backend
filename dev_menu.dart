import 'package:flutter/material.dart';
import '../ui/da_button.dart';
import 'truck_landing.dart';
import 'weather_center.dart';
import 'weather_center_pro.dart';
import 'weather_center_restored.dart';
import 'shop_under_construction.dart';

class DevMenu extends StatelessWidget {
  const DevMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Divergent Alliance')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DAButton(
                label: 'Truck Landing',
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TruckLanding()))),
            DAButton(
                label: 'Weather Center',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const WeatherCenterGate()))),
            DAButton(
                label: 'Weather Center Pro',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const WeatherCenterPro()))),
            DAButton(
                label: 'Weather Center Restored',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const WeatherCenterRestored()))),
            DAButton(
                label: 'Shop',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ShopUnderConstruction()))),
          ],
        ),
      ),
    );
  }
}
