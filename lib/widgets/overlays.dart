import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Dims everything except an ID-card-shaped window, with corner guides.
class CardFramePainter extends CustomPainter {
  CardFramePainter({required this.frame, required this.color});

  final Rect frame;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(frame, const Radius.circular(14));
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rrect);
    canvas.drawPath(mask, Paint()..color = Colors.black.withValues(alpha: 0.62));

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final r = frame.inflate(4);
    const len = 30.0;
    canvas
      ..drawPath(Path()..moveTo(r.left, r.top + len)..lineTo(r.left, r.top)..lineTo(r.left + len, r.top), p)
      ..drawPath(Path()..moveTo(r.right - len, r.top)..lineTo(r.right, r.top)..lineTo(r.right, r.top + len), p)
      ..drawPath(Path()..moveTo(r.right, r.bottom - len)..lineTo(r.right, r.bottom)..lineTo(r.right - len, r.bottom), p)
      ..drawPath(Path()..moveTo(r.left + len, r.bottom)..lineTo(r.left, r.bottom)..lineTo(r.left, r.bottom - len), p);
  }

  @override
  bool shouldRepaint(CardFramePainter old) => old.frame != frame || old.color != color;
}

/// Dims everything except a face oval, ringed by one segment per liveness
/// challenge. Passed segments turn green; the active one takes [highlight].
class FaceOvalPainter extends CustomPainter {
  FaceOvalPainter({
    required this.oval,
    required this.total,
    required this.completed,
    required this.highlight,
  });

  final Rect oval;
  final int total;
  final int completed;
  final Color highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(oval);
    canvas.drawPath(mask, Paint()..color = Colors.black.withValues(alpha: 0.7));

    if (total == 0) return;
    final ring = oval.inflate(12);
    const gap = 0.14;
    final segment = 2 * math.pi / total;
    for (var i = 0; i < total; i++) {
      final color = i < completed
          ? AppColors.verified
          : i == completed
              ? highlight
              : Colors.white.withValues(alpha: 0.22);
      canvas.drawArc(
        ring,
        -math.pi / 2 + i * segment + gap / 2,
        segment - gap,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(FaceOvalPainter old) =>
      old.oval != oval ||
      old.total != total ||
      old.completed != completed ||
      old.highlight != highlight;
}
