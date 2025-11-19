import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";
import "gate_config.dart";

class PinGate extends StatefulWidget {
  final Widget protectedChild;
  const PinGate({super.key, required this.protectedChild});
  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> {
  final _c = TextEditingController();
  String? _err;
  bool _checking = true;
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final sp = await SharedPreferences.getInstance();
    if (sp.getBool("weather_gate_ok") ?? false) {
      _go();
    } else {
      setState(() => _checking = false);
    }
  }

  Future<void> _submit() async {
    if (_c.text.trim() == GateConfig.weatherPin) {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool("weather_gate_ok", true);
      _go();
    } else {
      setState(() => _err = "Incorrect PIN");
    }
  }

  void _go() {
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => widget.protectedChild));
  }

  @override
  Widget build(BuildContext context) {
    if (_checking)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text("Enter Access PIN")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          TextField(
              controller: _c,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: InputDecoration(labelText: "PIN", errorText: _err),
              onSubmitted: (_) => _submit()),
          const SizedBox(height: 16),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                  icon: const Icon(Icons.lock_open),
                  label: const Text("Unlock"),
                  onPressed: _submit)),
        ]),
      ),
    );
  }
}
