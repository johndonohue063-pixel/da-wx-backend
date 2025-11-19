import 'package:flutter/material.dart';

class RuggedButton extends StatelessWidget {
  const RuggedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 52,
    this.fullWidth = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final double height;
  final bool fullWidth;

  static const _orange = Color(0xFFFF6A00);

  @override
  Widget build(BuildContext context) {
    final child = Container(
      height: height,
      constraints:
          fullWidth ? const BoxConstraints(minWidth: double.infinity) : null,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _orange, width: 1),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 16, offset: Offset(0, 10)),
          BoxShadow(color: Color(0x33FF6A00), blurRadius: 30, spreadRadius: 1),
        ],
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.45, 0.46, 1.0],
          colors: [
            Color(0xFF0E0E0E),
            Color(0xFF151515),
            Color(0xFF1C1C1C),
            Color(0xFF0D0D0D),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.06),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.10)
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                ],
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4)),
              ],
            ),
          ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        splashColor: _orange.withValues(alpha: 0.15),
        highlightColor: _orange.withValues(alpha: 0.07),
        child: child,
      ),
    );
  }
}
