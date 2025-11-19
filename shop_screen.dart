import 'package:flutter/material.dart';

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shop')),
      body: const Center(
        child: Text(
          'Shop is being wired up and will be available soon.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}