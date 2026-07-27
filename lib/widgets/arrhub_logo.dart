import 'package:flutter/material.dart';

/// The ArrHub triangular "spoke-cut" brand mark, mirroring the desktop lockup
/// (ArrHubDesktop's AppLogo.vue) so the two apps share one identity. Painted in a
/// single [color]; defaults to the theme's accent so the mark tracks the user's
/// chosen color, exactly like the desktop lockup (which is all currentColor).
class ArrHubMark extends StatelessWidget {
  /// Rendered height in logical pixels. Width is 1.2× this (the mark's aspect).
  final double size;
  final Color? color;

  const ArrHubMark({super.key, this.size = 32, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return CustomPaint(
      size: Size(size * 1.2, size),
      painter: _ArrHubMarkPainter(c),
    );
  }
}

class _ArrHubMarkPainter extends CustomPainter {
  final Color color;
  _ArrHubMarkPainter(this.color);

  // Design space matches the desktop SVG viewBox "20 -10 240 200".
  static const double _vbX = 20, _vbY = -10, _vbW = 240, _vbH = 200;
  static const Offset _hub = Offset(140, 120);
  static const Offset _apex = Offset(140, 4.5);
  static const Offset _right = Offset(240, 177.7);
  static const Offset _left = Offset(40, 177.7);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.height / _vbH); // height drives the scale; width is 1.2× it
    canvas.translate(-_vbX, -_vbY);

    // Cut the spokes out of the triangle by clearing on an isolated layer —
    // the direct analogue of the SVG mask used on desktop.
    canvas.saveLayer(const Rect.fromLTWH(_vbX, _vbY, _vbW, _vbH), Paint());

    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    canvas.drawPath(
      Path()
        ..moveTo(_apex.dx, _apex.dy)
        ..lineTo(_right.dx, _right.dy)
        ..lineTo(_left.dx, _left.dy)
        ..close(),
      fill,
    );

    final cut = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawLine(_hub, _apex, cut);
    canvas.drawLine(_hub, _right, cut);
    canvas.drawLine(_hub, _left, cut);
    canvas.drawCircle(
      _hub,
      10.5,
      Paint()
        ..blendMode = BlendMode.clear
        ..isAntiAlias = true,
    );

    canvas.restore(); // saveLayer
    canvas.restore(); // scale/translate
  }

  @override
  bool shouldRepaint(_ArrHubMarkPainter old) => old.color != color;
}

/// The mark plus the "ArrHub" wordmark, laid out horizontally — the in-app
/// equivalent of the desktop sidebar lockup.
class ArrHubLogo extends StatelessWidget {
  final double markSize;
  final Color? color;

  const ArrHubLogo({super.key, this.markSize = 30, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ArrHubMark(size: markSize, color: c),
        SizedBox(width: markSize * 0.42),
        Text(
          'ArrHub',
          style: TextStyle(
            color: c,
            fontSize: markSize * 0.92,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}
