import 'package:flutter/material.dart';
import 'weather_center_pro.dart';
import 'weather_center_gate.dart';

class CastleLanding extends StatelessWidget {
  const CastleLanding({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Truck hero background
          const Image(
            image: AssetImage('assets/images/truck_hero.jpg'),
            fit: BoxFit.cover,
          ),
          // dark gradient overlay for legibility
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54, Colors.black87],
                stops: [0.4, 0.75, 1.0],
              ),
            ),
          ),
          // Bottom buttons
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: _orangeButton(
                        label: 'Default',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const WeatherCenterPro()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _glassButton(
                        label: 'Gateway PIN',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const WeatherCenterGate()),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _orangeButton({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFFFF7A00),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Text(label,
          style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black),
        ),
      ),
    );
  }

  static Widget _glassButton({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Text(label,
          style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
    );
  }
}
