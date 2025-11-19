import 'package:flutter/material.dart';

Widget truckHeroSafe() => Image.asset(
      'assets/images/TRUCK_HERO.PNG',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Image.asset(
        'assets/images/TRUCK_HERO.png',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF000000), Color(0xFF0C0C0C)],
            ),
          ),
        ),
      ),
    );
