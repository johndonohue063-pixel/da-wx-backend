import "package:flutter/material.dart";

class ShopHubScreen extends StatelessWidget {
  const ShopHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Shop")),
      body: const Center(
        child:
            Text("Shop hub placeholder — wire to your real shop when ready."),
      ),
    );
  }
}
