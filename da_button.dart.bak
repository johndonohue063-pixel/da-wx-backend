import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class DABtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final double? width;
  final String bgAsset;
  final bool useSlice;
  final double edgeFraction;

  const DABtn({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.width,
    this.bgAsset = 'assets/ui/da_button.png',
    this.useSlice = false, // default = cover
    this.edgeFraction = 0.12, // used only if useSlice
  });

  @override
  State<DABtn> createState() => _DABtnState();
}

class _DABtnState extends State<DABtn> {
  ui.Image? _img;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.useSlice) return;
    final provider = AssetImage(widget.bgAsset);
    provider.resolve(createLocalImageConfiguration(context)).addListener(
          ImageStreamListener((info, _) {
            if (mounted && _img == null) setState(() => _img = info.image);
          }, onError: (_, __) {
            if (mounted) setState(() => _img = null);
          }),
        );
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    final bg = widget.useSlice ? _sliceBg(radius) : _coverBg(radius);

    final plate = Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: const Color(0xFFFF6A00), width: 1),
        boxShadow: const [
          BoxShadow(
              color: Color(0x99000000), blurRadius: 16, offset: Offset(0, 8))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          bg,
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  widget.label,
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
      onTap: widget.onPressed,
      borderRadius: radius,
      child: widget.width == null
          ? SizedBox(width: double.infinity, child: plate)
          : SizedBox(width: widget.width, child: plate),
    );
  }

  Widget _coverBg(BorderRadius radius) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        image: DecorationImage(
          image: AssetImage(widget.bgAsset),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          alignment: Alignment.center,
        ),
      ),
    );
  }

  Widget _sliceBg(BorderRadius radius) {
    if (_img == null) return _coverBg(radius);
    final double w = _img!.width.toDouble();
    final double h = _img!.height.toDouble();

    final double capX =
        ((w * widget.edgeFraction).clamp(1.0, w / 2 - 1.0)) as double;
    final double capY =
        ((h * widget.edgeFraction).clamp(1.0, h / 2 - 1.0)) as double;
    final double centerW = ((w - 2 * capX).clamp(1.0, w - 2.0)) as double;
    final double centerH = ((h - 2 * capY).clamp(1.0, h - 2.0)) as double;

    final Rect center = Rect.fromLTWH(capX, capY, centerW, centerH);

    return Image.asset(
      widget.bgAsset,
      fit: BoxFit.fill,
      centerSlice: center,
      filterQuality: FilterQuality.high,
    );
  }
}
