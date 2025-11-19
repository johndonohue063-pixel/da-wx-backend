import "dart:math";
import "package:flutter/material.dart";

class SparkTitle extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double sparkDensity;
  final Duration cycle;
  const SparkTitle(
      {super.key,
      required this.text,
      this.style,
      this.sparkDensity = 0.5,
      this.cycle = const Duration(seconds: 2)});
  @override
  State<SparkTitle> createState() => _SparkTitleState();
}

class _SparkTitleState extends State<SparkTitle>
    with SingleTickerProviderStateMixin {
  Widget _g(String s, TextStyle st, double spread, Color c) {
    return Text(
      s,
      style: st.copyWith(
        foreground: (Paint()
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, spread)
          ..color = c),
      ),
    );
  }

  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.cycle)..repeat();
  final _r = Random();
  late final List<_S> _s = List.generate(
      90,
      (_) => _S(
          _r.nextDouble(),
          0.5 + (_r.nextDouble() - 0.5) * 0.6,
          1 + _r.nextDouble() * 2.6,
          0.4 + _r.nextDouble() * 1.6,
          _r.nextDouble()));
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = (widget.style ?? const TextStyle()).copyWith(
        fontSize: (widget.style?.fontSize ?? 28),
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
        color: Colors.white);
    return AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          return Stack(clipBehavior: Clip.none, children: [
            _g(widget.text, base, 18,
                const Color(0xFFFF6A00).withValues(alpha: 0.22)),
            _g(widget.text, base, 6,
                const Color(0xFFFF6A00).withValues(alpha: 0.55)),
            ShaderMask(
                shaderCallback: (r) {
                  final pos = ((t * 1.1) % 1.0) * r.width;
                  return LinearGradient(colors: [
                    Colors.white70,
                    Colors.white,
                    const Color(0xFFFFE3C0),
                    Colors.white,
                    Colors.white70
                  ], stops: [
                    0,
                    0.45,
                    0.5,
                    0.55,
                    1
                  ]).createShader(Rect.fromLTWH(
                      pos - r.width * 0.15, 0, r.width * 0.3, r.height));
                },
                blendMode: BlendMode.plus,
                child: Text(widget.text,
                    style: base.copyWith(color: Colors.white70))),
            Opacity(
                opacity: 0.35 + 0.65 * (0.5 + 0.5 * sin(2 * pi * t * 3)),
                child: Text(widget.text,
                    style: base.copyWith(color: const Color(0xFFFFEFD7)))),
            IgnorePointer(
                child: CustomPaint(painter: _P(_s, t, widget.sparkDensity))),
          ]);
        });
  }
}

class _S {
  final double u, v, size, speed, life;
  _S(this.u, this.v, this.size, this.speed, this.life);
}

class _P extends CustomPainter {
  final List<_S> s;
  final double t;
  final double d;
  const _P(this.s, this.t, this.d);
  @override
  void paint(Canvas c, Size z) {
    final blur = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (int i = 0, drawn = 0; i < s.length; i++) {
      if (drawn / s.length > d) break;
      final sp = s[i];
      final tt = (t * sp.speed + sp.life) % 1.0,
          f = tt < 0.5 ? tt * 2 : (1 - (tt - 0.5) * 2);
      final x = sp.u * z.width + sin(tt * 12) * 6,
          y = z.height * sp.v + cos(tt * 10) * 4;
      blur.color = const Color(0xFFFFD6A3).withOpacity(0.25 + 0.75 * f);
      c.drawCircle(Offset(x, y), sp.size * (0.6 + 0.8 * f), blur);
      final core = Paint()
        ..color = const Color(0xFFFF6A00).withOpacity(0.35 + 0.65 * f);
      c.drawCircle(Offset(x, y), sp.size * 0.35, core);
      drawn++;
    }
  }

  @override
  bool shouldRepaint(covariant _P o) => o.t != t || o.d != d;
}
