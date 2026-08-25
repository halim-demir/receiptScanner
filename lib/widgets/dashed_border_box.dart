import 'package:flutter/material.dart';

/// Draws a dashed rounded-rectangle outline, matching the teal dashed
/// viewfinder frame on the camera screen.
class DashedBorderBox extends StatelessWidget {
  const DashedBorderBox({
    super.key,
    required this.width,
    required this.height,
    required this.color,
    this.borderRadius = 16,
    this.strokeWidth = 2,
    this.dashWidth = 8,
    this.gapWidth = 6,
    this.child,
  });

  final double width;
  final double height;
  final Color color;
  final double borderRadius;
  final double strokeWidth;
  final double dashWidth;
  final double gapWidth;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _DashedRRectPainter(
          color: color,
          radius: borderRadius,
          strokeWidth: strokeWidth,
          dashWidth: dashWidth,
          gapWidth: gapWidth,
        ),
        child: child,
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dashWidth,
    required this.gapWidth,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashWidth;
  final double gapWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gapWidth;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashWidth != dashWidth ||
        oldDelegate.gapWidth != gapWidth;
  }
}
