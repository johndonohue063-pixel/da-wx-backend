import 'package:flutter/material.dart';

class DAHybridButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool fullWidth;
  final double height;

  const DAHybridButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.fullWidth = true,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: Colors.black),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
            letterSpacing: .6,
            fontSize: 16,
          ),
        ),
      ],
    );

    return Opacity(
      opacity: onPressed == null ? .55 : 1,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: height,
          width: fullWidth ? double.infinity : null,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black87, blurRadius: 10, offset: Offset(0, 6))
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Row(children: const [_OilSide(), _BoardSide()]),
              Container(color: Colors.black.withValues(alpha: 0.04)),
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6600),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black, width: 1),
                  ),
                  child: chip,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OilSide extends StatelessWidget {
  const _OilSide();
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A1A1A), Color(0xFF000000)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: CustomPaint(painter: _OilGrunge()),
        ),
      );
}

class _BoardSide extends StatelessWidget {
  const _BoardSide();
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF7A24), Color(0xFFFF6600)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: CustomPaint(painter: _BoardTrace()),
        ),
      );
}

class _OilGrunge extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final stripe = Paint()..color = const Color(0x22000000);
    for (double y = 0; y < s.height; y += 6) {
      c.drawRect(Rect.fromLTWH(0, y, s.width, 2), stripe);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BoardTrace extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final trace = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1.2;
    for (double x = s.width * 0.22; x < s.width; x += 16) {
      c.drawLine(Offset(x, 6), Offset(x, s.height - 6), trace);
    }
    final pad = Paint()..color = const Color(0x99FFFFFF);
    for (double y = 10; y < s.height; y += 14) {
      c.drawCircle(Offset(s.width * 0.76, y), 1.6, pad);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
