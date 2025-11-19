import 'package:flutter/material.dart';

class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Store')),
      body: const Center(
        child: Text(
          'Store coming soon',
          style: TextStyle(color: Color(0xFFFF6A00), fontSize: 18),
        ),
      ),
    );
  }
}
