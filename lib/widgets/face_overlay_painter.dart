import 'package:flutter/material.dart';

class FaceOverlayPainter extends CustomPainter {
  final Color borderColor;
  final double borderWidth;
  final double progress;

  FaceOverlayPainter({
    required this.borderColor,
    this.borderWidth = 3.5,
    this.progress = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    // Define biometric face oval
    final ovalWidth = size.width * 0.75;
    final ovalHeight = size.height * 0.45;
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.40),
      width: ovalWidth,
      height: ovalHeight,
    );

    // Cutout background
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, backgroundPaint);

    // Draw oval border guide
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    canvas.drawOval(ovalRect, borderPaint);

    // Draw circular progress arc around oval if progress > 0
    if (progress > 0.0) {
      final progressPaint = Paint()
        ..color = Colors.greenAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth + 1.5
        ..strokeCap = StrokeCap.round;

      final sweepAngle = 2 * 3.141592653589793 * progress.clamp(0.0, 1.0);
      canvas.drawArc(ovalRect, -3.141592653589793 / 2, sweepAngle, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FaceOverlayPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.progress != progress;
  }
}
