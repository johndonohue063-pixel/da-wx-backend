import 'package:flutter/material.dart';

class ShopUnderConstruction extends StatelessWidget {
  const ShopUnderConstruction({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Shop')),
      body: const Center(
        child: Text(
          'Our shop is being wired up. Under construction.',
          style: TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
