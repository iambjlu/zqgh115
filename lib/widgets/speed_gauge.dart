import 'package:flutter/material.dart';

import '../theme/hud_colors.dart';

/// 車速儀表：左側 V 形刻度尺（0 在底、[maxSpeed] 在頂）加一根綠色指針，
/// 右側是大字車速。指針會平滑移動；超過 [maxSpeed] 時指針停在頂端。
class SpeedGauge extends StatelessWidget {
  const SpeedGauge({super.key, required this.speed});

  final int? speed;

  /// 刻度尺上限（km/h）。
  static const double maxSpeed = 25;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final target = (speed ?? 0).clamp(0, maxSpeed).toDouble();
    return SizedBox(
      height: 176,
      child: Row(
        children: [
          const SizedBox(width: 12),
          SizedBox(
            width: 190,
            height: 176,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: target),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              builder: (context, value, _) =>
                  CustomPaint(painter: _GaugePainter(value)),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    speed?.toString() ?? '—',
                    style: textTheme.displayLarge?.copyWith(
                      fontSize: 104,
                      height: 1,
                      fontWeight: FontWeight.w300,
                      color: HudColors.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text('km/h',
                    style: textTheme.titleMedium?.copyWith(color: HudColors.inkDim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 仿 BMW 儀表的 V 形金屬框＋玻璃面板：左側為亮面金屬邊框，
/// 內側是向右淡出的深色玻璃（底部帶暖色反光），刻度為水平短線，
/// 指針是一條水平、帶光暈與星芒的綠色亮條。車速與 y 座標成線性對應（0 在底、max 在頂）。
class _GaugePainter extends CustomPainter {
  _GaugePainter(this.value);

  final double value;

  static const _bezel = 16.0; // 金屬框的水平寬度

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final wr = w * 0.62; // V 形上下兩端的 x
    final hm = h * 0.5; // 轉折點的 y
    const max = SpeedGauge.maxSpeed;
    final yBottom = h - 8;
    const yTop = 8.0;
    double yOf(double v) => yBottom - (yBottom - yTop) * v / max;
    double xOuter(double y) => y <= hm ? wr * (1 - y / hm) : wr * (y - hm) / (h - hm);
    double xInner(double y) => xOuter(y) + _bezel;

    final outer = [Offset(wr, 0), Offset(0, hm), Offset(wr, h)];
    final inner = [Offset(wr + _bezel, 0), Offset(_bezel, hm), Offset(wr + _bezel, h)];

    // 玻璃面板：從內框往右延伸並淡出。
    final glass = Path()
      ..moveTo(inner[0].dx, 0)
      ..lineTo(inner[1].dx, inner[1].dy)
      ..lineTo(inner[2].dx, h)
      ..lineTo(w, h)
      ..lineTo(w, 0)
      ..close();
    final glassRect = Rect.fromLTWH(0, 0, w, h);
    canvas.save();
    canvas.clipPath(glass);
    canvas.drawRect(
      glassRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF2A3647), Color(0xFF151B24), Color(0x00151B24)],
          stops: [0, 0.55, 1],
        ).createShader(glassRect),
    );
    // 底部暖色反光
    canvas.drawRect(
      glassRect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.bottomLeft,
          radius: 0.75,
          colors: const [Color(0x88FF9A66), Color(0x33C0507A), Color(0x00000000)],
          stops: const [0, 0.45, 1],
        ).createShader(glassRect),
    );
    // 斜向玻璃眩光
    final glare = Path()
      ..moveTo(_bezel, hm * 0.55)
      ..lineTo(wr * 0.9, 0)
      ..lineTo(wr * 1.25, 0)
      ..lineTo(_bezel + 12, hm * 0.85)
      ..close();
    canvas.drawPath(glare, Paint()..color = const Color(0x12FFFFFF));
    canvas.restore();

    // 金屬框：上亮下暗的鉻金屬漸層，外緣一條亮邊。
    final bezel = Path()
      ..moveTo(outer[0].dx, outer[0].dy)
      ..lineTo(outer[1].dx, outer[1].dy)
      ..lineTo(outer[2].dx, outer[2].dy)
      ..lineTo(inner[2].dx, inner[2].dy)
      ..lineTo(inner[1].dx, inner[1].dy)
      ..lineTo(inner[0].dx, inner[0].dy)
      ..close();
    canvas.drawPath(
      bezel,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF4F7FB),
            Color(0xFF8D98A8),
            Color(0xFF3A414C),
            Color(0xFFB8C2D0),
            Color(0xFF59616D),
          ],
          stops: [0, 0.3, 0.52, 0.75, 1],
        ).createShader(Rect.fromLTWH(0, 0, wr + _bezel, h)),
    );
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xCCFFFFFF);
    canvas.drawPath(
      Path()
        ..moveTo(outer[0].dx, outer[0].dy)
        ..lineTo(outer[1].dx, outer[1].dy)
        ..lineTo(outer[2].dx, outer[2].dy),
      edge,
    );
    canvas.drawPath(
      Path()
        ..moveTo(inner[0].dx, inner[0].dy)
        ..lineTo(inner[1].dx, inner[1].dy)
        ..lineTo(inner[2].dx, inner[2].dy),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0x66000000),
    );

    // 刻度：水平短線自內框向右，每 5 一大刻度附數字。
    final tick = Paint()..strokeWidth = 1.5;
    for (var i = 0; i <= max.toInt(); i++) {
      final y = yOf(i.toDouble());
      final x = xInner(y) + 4;
      final major = i % 5 == 0;
      tick.color = major ? HudColors.ink : const Color(0x99FFFFFF);
      canvas.drawLine(Offset(x, y), Offset(x + (major ? 13 : 7), y), tick);
      if (major) {
        final tp = TextPainter(
          text: TextSpan(
            text: '$i',
            style: TextStyle(
              color: HudColors.ink.withValues(alpha: 0.85),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 20, y - tp.height / 2));
      }
    }

    // 指針：水平亮綠條，橫跨金屬框並深入玻璃，帶光暈與星芒。
    final y = yOf(value);
    final x0 = xOuter(y) - 6;
    final x1 = xInner(y) + 22;
    final bar = Rect.fromLTRB(x0, y - 2.5, x1, y + 2.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar.inflate(3), const Radius.circular(4)),
      Paint()
        ..color = HudColors.gauge.withValues(alpha: 0.75)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar, const Radius.circular(2.5)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF9CFF8F), Color(0xFF3FCF4F)],
        ).createShader(bar),
    );
    canvas.drawLine(
      Offset(x0 + 3, y),
      Offset(x1 - 3, y),
      Paint()
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.9),
    );
    // 星芒（左端）
    final flare = Offset(x0 + 2, y);
    final flarePaint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawLine(flare - const Offset(9, 0), flare + const Offset(9, 0), flarePaint..strokeWidth = 1.2);
    canvas.drawLine(flare - const Offset(0, 8), flare + const Offset(0, 8), flarePaint..strokeWidth = 1.2);
    canvas.drawCircle(flare, 2.2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.value != value;
}
