import 'package:flutter/material.dart';

class SafeHome extends StatelessWidget {
  const SafeHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Divergent Alliance'),
      ),
      body: const Center(
        child: Text(
          'Build is healthy. Weather modules are quarantined for repair.',
          style: TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
