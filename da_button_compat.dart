import 'package:flutter/material.dart';

class DAButton extends StatelessWidget {
  const DAButton({
    super.key,
    this.onPressed,
    this.onLongPress,
    required this.child,
    this.height = 56,
    this.width,
    this.asset = 'assets/ui/button_bg.png',
    this.centerSlice = const Rect.fromLTWH(64, 64, 896, 896),
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.borderColor = const Color(0xFFFF7A00),
  });

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final Widget child;
  final double height;
  final double? width;
  final String asset;
  final Rect centerSlice;
  final BorderRadius borderRadius;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          onLongPress: onLongPress,
          borderRadius: borderRadius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(color: borderColor, width: 1),
              image: DecorationImage(
                image: AssetImage(asset),
                fit: BoxFit.fill,
                // centerSlice: centerSlice,  // <-- comment this for a second
                filterQuality: FilterQuality.high,
              ),

            ),
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
