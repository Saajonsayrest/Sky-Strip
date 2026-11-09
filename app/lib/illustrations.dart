import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bridge.dart';
import 'settings_sheet.dart';
import 'theme.dart';

/// Widget colours (same as `Palette` in Renderer.kt).
abstract final class WidgetPalette {
  static const dayClear = Color(0xFF3BC2FF);
  static const dayCloudy = Color(0xFFC2C2C2);
  static const nightClear = Color(0xFF0059B3);
  static const nightCloudy = Color(0xFF6B6B6B);
  static const rain = Color(0xFF008AF4);
  static const ramp = [
    Color(0xFFDA00FF), Color(0xFFBF40FF), Color(0xFF8A54FF), Color(0xFF5E6EFF), Color(0xFF337EFF),
    Color(0xFF00B0FF), Color(0xFF00BCD4), Color(0xFF00BFA5), Color(0xFF52D400), Color(0xFFEEC800),
    Color(0xFFFFA000), Color(0xFFFF6F00), Color(0xFFFF3D3D), Color(0xFFFF3B7C), Color(0xFFFF30C4),
  ];

  static Color temp(double celsius) {
    final pos = (celsius + 28) / 5;
    if (pos <= 0) return ramp.first;
    if (pos >= ramp.length - 1) return ramp.last;
    final i = pos.floor();
    return Color.lerp(ramp[i], ramp[i + 1], pos - i)!;
  }

  static Color sky(double sun, double cloud) => Color.lerp(
        Color.lerp(nightClear, nightCloudy, cloud)!,
        Color.lerp(dayClear, dayCloudy, cloud)!,
        sun,
      )!;
}

/// The grey rounded box every tour picture sits in.
class PictureCard extends StatelessWidget {
  const PictureCard({super.key, required this.child, this.height = 260});

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.of(context).pictureCard,
          borderRadius: BorderRadius.circular(28),
        ),
        child: child,
      );
}

/// The real widget, drawn by the widget code with a sample forecast.
class WidgetPreview extends StatefulWidget {
  const WidgetPreview({super.key, required this.bridge, this.fahrenheit});

  final Bridge bridge;
  /// Null: follow the phone's region (°F in the US).
  final bool? fahrenheit;

  @override
  State<WidgetPreview> createState() => _WidgetPreviewState();
}

class _WidgetPreviewState extends State<WidgetPreview> {
  Future<dynamic>? _png;
  Brightness? _for;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    if (_png == null || _for != b) {
      _for = b;
      final f = widget.fahrenheit ??
          defaultSettings(Localizations.localeOf(context)).fahrenheit;
      _png = widget.bridge.preview(width: 352, height: 117, dark: b == Brightness.dark, fahrenheit: f);
    }
    return Center(
      child: FutureBuilder(
        future: _png,
        builder: (context, snap) => snap.data == null
            ? const SizedBox(width: 352, height: 117)
            : Image.memory(snap.data!, width: 352, height: 117, fit: BoxFit.contain),
      ),
    );
  }
}

TextStyle _label(Color color) => outfit(19, weight: 600, color: color);

/// Temperature page: coloured columns under a rising curve, "cold" and "hot".
class TemperaturePicture extends StatelessWidget {
  const TemperaturePicture({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 28),
      child: Column(children: [
        Expanded(child: CustomPaint(size: Size.infinite, painter: _TempPainter(AppColors.of(context).pictureCard))),
        const SizedBox(height: 8),
        Row(children: [
          Text('cold', style: _label(WidgetPalette.temp(-8))),
          const Spacer(),
          Text('hot', style: _label(WidgetPalette.temp(33))),
        ]),
      ]),
    );
  }
}

class _TempPainter extends CustomPainter {
  _TempPainter(this.card);
  final Color card;

  // Curve height 0..1 at each column end: flat and cold, then a steep warm-up, then gentle.
  static const _points = [0.0, 0.25, 0.5, 0.62, 0.72, 0.76, 1.0];
  static const _heights = [0.15, 0.27, 0.42, 0.72, 0.9, 0.92, 1.0];

  double _h(double t) {
    for (var i = 1; i < _points.length; i++) {
      if (t <= _points[i]) {
        final f = (t - _points[i - 1]) / (_points[i] - _points[i - 1]);
        return _heights[i - 1] + (_heights[i] - _heights[i - 1]) * f;
      }
    }
    return _heights.last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const n = 40;
    final w = size.width / n;
    final gap = 3.0;
    final top = gap + 1;
    for (var i = 0; i < n; i++) {
      final x0 = (i * w).roundToDouble();
      final x1 = ((i + 1) * w).roundToDouble();
      final yl = top + (1 - _h(i / n)) * (size.height - top);
      final yr = top + (1 - _h((i + 1) / n)) * (size.height - top);
      final t = -8 + 41 * (i / (n - 1));
      canvas.drawPath(
        Path()
          ..moveTo(x0, yl)
          ..lineTo(x1, yr)
          ..lineTo(x1, size.height)
          ..lineTo(x0, size.height)
          ..close(),
        Paint()..color = WidgetPalette.temp(t),
      );
    }
    final line = Path()..moveTo(0, top + (1 - _h(0)) * (size.height - top) - gap);
    for (var i = 1; i <= n; i++) {
      line.lineTo(i * w, top + (1 - _h(i / n)) * (size.height - top) - gap);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(_TempPainter old) => old.card != card;
}

/// Cloud cover & daylight page: a sky band from clear night to cloudy night with sun up and down.
class SkyPicture extends StatelessWidget {
  const SkyPicture({super.key});

  @override
  Widget build(BuildContext context) {
    final grey = AppColors.of(context).muted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
      child: Column(children: [
        Row(children: [
          Text('clear night', style: outfit(16, weight: 600, color: WidgetPalette.nightClear)),
          const Spacer(),
          Text('cloudy day', style: outfit(16, weight: 600, color: WidgetPalette.dayCloudy)),
          const SizedBox(width: 76),
        ]),
        const SizedBox(height: 6),
        const Expanded(child: CustomPaint(size: Size.infinite, painter: _SkyPainter())),
        const SizedBox(height: 6),
        Row(children: [
          const SizedBox(width: 80),
          Text('clear day', style: outfit(16, weight: 600, color: WidgetPalette.dayClear)),
          const Spacer(),
          Text('cloudy night', style: outfit(16, weight: 600, color: grey)),
        ]),
      ]),
    );
  }
}

class _SkyPainter extends CustomPainter {
  const _SkyPainter();

  // (sun 0..1, cloud 0..1, share of the width)
  static const _cols = [
    (0.0, 0.0, 0.2), (0.5, 0.0, 0.07), (1.0, 0.0, 0.13), (1.0, 0.25, 0.07), (1.0, 0.45, 0.07),
    (1.0, 0.65, 0.07), (1.0, 1.0, 0.13), (0.5, 1.0, 0.07), (0.0, 1.0, 0.19),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    var x = 0.0;
    for (final (sun, cloud, share) in _cols) {
      final w = share * size.width;
      canvas.drawRect(Rect.fromLTWH(x.roundToDouble(), 0, w.roundToDouble() + 1, size.height),
          Paint()..color = WidgetPalette.sky(sun, cloud));
      x += w;
    }
    // Sunrise and sunset marks: small sun over the horizon with an arrow.
    final marks = [(0.235, true), (0.765, false)];
    final p = Paint()
      ..color = const Color(0xFFFFA000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final (at, up) in marks) {
      final cx = at * size.width;
      final cy = size.height * 0.5;
      canvas.drawLine(Offset(cx - 9, cy + 9), Offset(cx + 9, cy + 9), p);
      canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy + 9), radius: 5), math.pi, math.pi, false, p);
      final y0 = up ? cy : cy - 16;
      final y1 = up ? cy - 16 : cy;
      canvas.drawLine(Offset(cx, y0), Offset(cx, y1), p);
      canvas.drawLine(Offset(cx - 4, y1 + (up ? 4 : -4)), Offset(cx, y1), p);
      canvas.drawLine(Offset(cx + 4, y1 + (up ? 4 : -4)), Offset(cx, y1), p);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => false;
}

/// Rain & snow page: one to four dots, each with its name turned on its side.
class RainPicture extends StatelessWidget {
  const RainPicture({super.key});

  @override
  Widget build(BuildContext context) {
    const names = ['light rain', 'moderate rain', 'heavy rain', 'violent rain'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < 4; i++)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(children: [
                for (var k = 0; k <= i; k++)
                  Container(
                    width: 30,
                    height: 30,
                    margin: const EdgeInsets.only(bottom: 5),
                    decoration: const BoxDecoration(color: WidgetPalette.rain, shape: BoxShape.circle),
                  ),
              ]),
              const SizedBox(width: 6),
              RotatedBox(
                quarterTurns: 3,
                child: Text(names[i], style: outfit(15, weight: 600, color: WidgetPalette.rain)),
              ),
            ]),
        ],
      ),
    );
  }
}

/// Wind page: a staircase of arrows from 1 (light air) to 12 (hurricane).
class WindPicture extends StatelessWidget {
  const WindPicture({super.key});

  @override
  Widget build(BuildContext context) {
    const grey = Color(0xFF9E9E9E);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
      child: Column(children: [
        Align(alignment: Alignment.centerRight, child: Text('hurricane', style: _label(grey))),
        const Expanded(child: CustomPaint(size: Size.infinite, painter: _WindPainter(grey))),
        Align(alignment: Alignment.centerLeft, child: Text('light air', style: _label(grey))),
      ]),
    );
  }
}

class _WindPainter extends CustomPainter {
  const _WindPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 12;
    final w = size.width / n;
    final step = size.height / n;
    final arrowH = step * 0.55;
    final p = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      final x0 = i * w + w * 0.08;
      final x1 = (i + 1) * w - w * 0.08;
      for (var k = 1; k <= i + 1; k++) {
        final cy = size.height - step * (k - 0.5);
        canvas.drawPath(
          Path()
            ..moveTo(x0, cy - arrowH / 2)
            ..lineTo(x1, cy)
            ..lineTo(x0, cy + arrowH / 2)
            ..close(),
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WindPainter old) => old.color != color;
}
