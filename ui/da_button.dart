import 'package:flutter/material.dart';

class DABtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final double? width; // optional, pass on landing for a plate-sized button

  const DABtn({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);

    final button = Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: radius,
        // visible base even if the image is dark on the left
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF181818), Color(0xFFFF6A00)],
        ),
        border: Border.all(color: Color(0xFFFF6A00), width: 1),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // your oil/circuit PNG
          Image.asset(
            'assets/ui/da_button.png',
            fit: BoxFit.cover,
            opacity: const AlwaysStoppedAnimation(0.85),
            errorBuilder: (_, __, ___) => const SizedBox.shrink(), // keep gradient base
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    fontSize: 16,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return InkWell(
      onTap: onPressed,
      borderRadius: radius,
      child: width == null
          ? SizedBox(width: double.infinity, child: button) // full width by default
          : SizedBox(width: width, child: button),          // fixed plate width if provided
    );
  }
}
