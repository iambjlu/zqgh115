import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/simulation_values.dart';
import '../models/vehicle_threat.dart';
import '../theme/hud_colors.dart';

/// 虛擬道路檢視：鏡頭在自行車後上方往前看，自行車位於道路中間，
/// 左右後方來車與前方障礙物都以立體弧形燈條環繞在自行車前後（後方依距離黃／紅、前方一律橘色），
/// 前方坑洞畫成路面上的坑。標記為「逼近中」的後方弧條會硬切閃爍
/// （無淡入淡出），左右共用同一個時鐘，節奏永遠同步。
/// 地面橫向格線依車速往後捲動，營造行進感（刻意不畫車道線）。
class RoadView extends StatefulWidget {
  const RoadView({
    super.key,
    required this.threats,
    required this.speedKmh,
    this.frontLeft = FrontHazard.none,
    this.frontCenter = FrontHazard.none,
    this.frontRight = FrontHazard.none,
  });

  final List<VehicleThreat> threats;
  final double speedKmh;
  final FrontHazard frontLeft;
  final FrontHazard frontCenter;
  final FrontHazard frontRight;

  @override
  State<RoadView> createState() => _RoadViewState();
}

/// 單一時鐘：累計路面捲動距離與閃爍相位，painter 以它作為 repaint 來源，
/// 不需每個 frame 重建整個 widget 樹。
class _Clock extends ChangeNotifier {
  double scroll = 0; // 公尺，0~gridPeriod
  bool blinkVisible = true;

  void tick(double dt, double elapsedMs, double speedMps) {
    scroll = (scroll + speedMps * dt) % _Cam.gridPeriod;
    blinkVisible = (elapsedMs ~/ 220).isEven;
    notifyListeners();
  }
}

class _RoadViewState extends State<RoadView>
    with SingleTickerProviderStateMixin {
  final _clock = _Clock();
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      _clock.tick(dt, elapsed.inMilliseconds.toDouble(), widget.speedKmh / 3.6);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final cam = _Cam(size);
        final bikeCenter = cam.p(0, 0, 0);
        final bikeHeight = _Cam.bikeLength * cam.scaleAt(0) * 1.25;
        final bikeWidth = bikeHeight * 542 / 1072;
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _RoadPainter(
                  clock: _clock,
                  frontLeft: widget.frontLeft,
                  frontCenter: widget.frontCenter,
                  frontRight: widget.frontRight,
                ),
              ),
              // 車身後方的白色光暈與橢圓底盤，讓自行車從深色路面上浮出來。
              Positioned(
                left: bikeCenter.dx - bikeWidth * 1.3,
                top: bikeCenter.dy - bikeHeight * 0.75,
                width: bikeWidth * 2.6,
                height: bikeHeight * 1.5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.55),
                        Colors.white.withValues(alpha: 0.18),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: bikeCenter.dx - bikeWidth / 2,
                top: bikeCenter.dy - bikeHeight / 2,
                width: bikeWidth,
                height: bikeHeight,
                child: Image.asset('assets/bike.png', fit: BoxFit.contain),
              ),
              CustomPaint(
                painter: _CarsPainter(clock: _clock, threats: widget.threats),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 針孔透視：世界座標 x 往右、h 往上、z 往前（公尺，自行車在原點），
/// 鏡頭在自行車後方 [camBehind] 公尺、高度 [camHeight] 公尺（偏俯視），
/// 地平線位置依版面算出，讓自行車落在畫面約 42% 高處。
class _Cam {
  _Cam(Size size)
    : cx = size.width / 2,
      f = size.width * 7,
      yh = size.height * 0.42 - size.width * 7 * camHeight / camBehind;

  static const double camBehind = 100;
  static const double camHeight = 20;
  static const double gridPeriod = 6;
  static const double bikeLength = 2.4;
  static const double roadHalf = 5.2;

  final double cx;
  final double f;
  final double yh;
  double get hc => camHeight;

  Offset p(double x, double h, double z) {
    final dz = z + camBehind;
    return Offset(cx + f * x / dz, yh + f * (hc - h) / dz);
  }

  double scaleAt(double z) => f / (z + camBehind);
}


Path _poly(List<Offset> pts) {
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final p in pts.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

Color _shade(Color c, double lightnessDelta) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness + lightnessDelta).clamp(0.0, 1.0))
      .toColor();
}

const _arcSegs = 9;
const _frontOrange = Color(0xFFFF8A1F);

/// 前方弧條內緣離車身的間距（前方沒有距離資料，固定值）。
const _frontGap = 2.0;

/// 鏡頭是低角度俯視（地面縱深被壓縮約 1/5），而自行車圖是正上方視角；
/// 弧條縱向半徑乘上此係數補償，才能在畫面上真的包住車圖。
const _arcZK = 4.5;

/// 自行車周圍的立體弧形燈條中的一小段（倒車雷達樣式）：以車身中心為圓心的橢圓環，
/// 沿前方（[rear] 為 false）或後方半圈分成 [total] 段（前方 9 段＝左前／正前／右前各 60°，
/// 後方 10 段＝左後／右後各 90°），第 [k] 段由右到左。
/// [gapMeters] 為燈條內緣離車身的額外距離（越近越貼車）。以 [top] 為頂面色、
/// 較暗的側面墊出厚度，外側帶光暈。
void _arcSegment(
  Canvas canvas,
  _Cam cam,
  int k, {
  required bool rear,
  required Color top,
  required double gapMeters,
  int total = _arcSegs,
}) {
  const gap = 0.05; // 段與段之間的縫（弧度）
  const height = 0.18;
  // 內緣橢圓半徑：略大於車身（寬約 1.5m、長約 3m），再加上距離造成的外推。
  final rx0 = 0.9 + gapMeters, rz0 = 1.65 + gapMeters;
  final rx1 = rx0 + 0.45, rz1 = rz0 + 0.5;
  final sign = rear ? -1.0 : 1.0;
  Offset pt(bool outer, double a, double h) => cam.p(
    (outer ? rx1 : rx0) * math.cos(a),
    h,
    sign * _arcZK * (outer ? rz1 : rz0) * math.sin(a),
  );
  final a0 = k * math.pi / total + gap;
  final a1 = (k + 1) * math.pi / total - gap;
  const n = 4;
  List<Offset> edge(bool outer, double h) => [
    for (var j = 0; j <= n; j++) pt(outer, a0 + (a1 - a0) * j / n, h),
  ];
  Path quad(List<Offset> lowA, List<Offset> highA) =>
      _poly([...lowA, ...highA.reversed]);

  final outerLow = edge(true, 0), outerHigh = edge(true, height);
  final innerLow = edge(false, 0), innerHigh = edge(false, height);
  final topPath = _poly([...outerHigh, ...innerHigh.reversed]);

  canvas.drawPath(
    topPath,
    Paint()
      ..color = top.withValues(alpha: 0.7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
  );
  final side = Paint()..color = _shade(top, -0.25);
  canvas.drawPath(quad(outerLow, outerHigh), side);
  canvas.drawPath(quad(innerLow, innerHigh), side);
  // 兩端斷面
  for (final j in [0, n]) {
    canvas.drawPath(
      _poly([outerLow[j], outerHigh[j], innerHigh[j], innerLow[j]]),
      Paint()..color = _shade(top, -0.15),
    );
  }
  canvas.drawPath(topPath, Paint()..color = top);
  canvas.drawPath(
    topPath,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.round
      ..color = _shade(top, 0.22),
  );
}

class _RoadPainter extends CustomPainter {
  _RoadPainter({
    required this.clock,
    required this.frontLeft,
    required this.frontCenter,
    required this.frontRight,
  }) : super(repaint: clock);

  final _Clock clock;
  final FrontHazard frontLeft;
  final FrontHazard frontCenter;
  final FrontHazard frontRight;

  static const _zNear = -60.0;
  static const _zFar = 3000.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cam = _Cam(size);
    const half = _Cam.roadHalf;

    canvas.drawPath(
      _poly([
        cam.p(-half, 0, _zNear),
        cam.p(half, 0, _zNear),
        cam.p(half, 0, _zFar),
        cam.p(-half, 0, _zFar),
      ]),
      Paint()..color = HudColors.road,
    );

    // 不畫車道線（避免誤導成三車道視野）；改用橫向淡色格線依車速往鏡頭方向捲動，
    // 只表現地面與行進感。
    final grid =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = HudColors.ink.withValues(alpha: 0.10);
    for (var k = -12; k < 80; k++) {
      final z = k * _Cam.gridPeriod - clock.scroll;
      if (z < _zNear) continue;
      canvas.drawLine(cam.p(-half, 0, z), cam.p(half, 0, z), grid);
    }

    // 遠端淡出到背景色，避免道路在地平線硬切。先畫淡出、再畫路況，
    // 遠處的弧條與坑洞才不會被淡出漸層蓋暗。
    final fadeRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.4);
    canvas.drawRect(
      fadeRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [HudColors.surface, Color(0x000A0B0D)],
        ).createShader(fadeRect),
    );

    // 前方路況，左前 / 正前 / 右前：坑洞是畫在路面上的坑、障礙物是自行車前方的弧形燈條，
    // 兩者並存時坑洞與弧形燈條同時顯示。
    // 坑洞放在各自扇區中線方向（右前 30°、正前 90°、左前 150°），位於弧條內側。
    final hazards = [frontLeft, frontCenter, frontRight];
    const pitAngles = [5 * math.pi / 6, math.pi / 2, math.pi / 6]; // 對應 hazards 順序
    const pitRx = 0.9 + _frontGap - 0.45;
    const pitRz = _arcZK * (1.65 + _frontGap) - 1.8;
    for (var i = 0; i < 3; i++) {
      if (hazards[i].hasPothole) {
        _pit(
          canvas,
          cam,
          pitRx * math.cos(pitAngles[i]),
          pitRz * math.sin(pitAngles[i]),
          scale: 0.75,
        );
      }
    }
    // 障礙物：自行車前方的分段弧形燈條（倒車雷達樣式），左前／正前／右前各一區。
    // 前方沒有距離判斷，一律用橘色。sectorOn 順序為左前、正前、右前；k 0..2 右前、3..5 正前、6..8 左前。
    for (var k = 0; k < _arcSegs; k++) {
      if (hazards[2 - k ~/ 3].hasObstacle) {
        _arcSegment(
          canvas,
          cam,
          k,
          rear: false,
          top: _frontOrange,
          gapMeters: _frontGap,
        );
      }
    }

  }

  /// 坑洞：畫在路面上的一個坑——黃色外框加較亮的坑緣，內部是由遠端坑壁（亮）
  /// 漸層到坑底（近黑），不會與灰色路面融為一體。
  void _pit(Canvas canvas, _Cam cam, double x, double z, {double scale = 1}) {
    // 地面在畫面上被透視壓扁，z 方向放大約 2 倍，坑看起來才像坑而不是細環。
    const zStretch = 2.0;
    Path ring(double r, [double dz = 0]) {
      final pts = [
        for (var i = 0; i < 36; i++)
          cam.p(
            x + r * math.cos(i * math.pi / 18),
            0,
            z + dz + zStretch * r * math.sin(i * math.pi / 18),
          ),
      ];
      return _poly(pts);
    }

    final rim = ring(1.0 * scale);
    canvas.drawPath(rim, Paint()..color = const Color(0xFF555B66));
    canvas.drawPath(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = HudColors.warn,
    );
    final hole = ring(0.74 * scale);
    final bounds = hole.getBounds();
    canvas.drawPath(
      hole,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF454B55), Color(0xFF0B0C0F), Color(0xFF020203)],
          stops: [0, 0.45, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(covariant _RoadPainter old) =>
      old.frontLeft != frontLeft ||
      old.frontCenter != frontCenter ||
      old.frontRight != frontRight;
}

/// 左／右後方來車：自行車後方的立體弧形燈條（倒車雷達樣式）。沒車不顯示；
/// 遠亮綠、中亮黃、近亮紅，每側固定 4 段，標記為「逼近中」時硬切閃爍。
class _CarsPainter extends CustomPainter {
  _CarsPainter({required this.clock, required this.threats})
    : super(repaint: clock);

  final _Clock clock;
  final List<VehicleThreat> threats;

  Color _colorFor(ThreatLevel level) => switch (level) {
    ThreatLevel.safe => HudColors.safe,
    ThreatLevel.caution => HudColors.warn,
    ThreatLevel.danger => HudColors.danger,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final cam = _Cam(size);
    for (final t in threats) {
      if (!t.hasVehicle) continue; // 沒車不畫；遠（安全）畫綠色
      // 逼近中：硬切閃爍（左右共用同一個時鐘，節奏同步）。
      if (t.isApproaching && !clock.blinkVisible) continue;
      final left = t.side == ThreatSide.left;
      // 後半圈分 10 段（各 18°），k 由右到左 0..9：右後 0..4（90°）、左後 5..9（90°）。
      // 不論距離，塊數固定 5 段，距離只影響顏色與離車遠近。
      final order = left ? [5, 6, 7, 8, 9] : [0, 1, 2, 3, 4];
      const count = 5;
      // 距離 5m 離車身 0.9m、30m 外推到 1.7m：越近燈條越靠車。
      final gap = 0.9 + (t.distanceMeters.clamp(5, 30) - 5) / 25 * 0.8;
      for (final k in order.take(count)) {
        _arcSegment(
          canvas,
          cam,
          k,
          rear: true,
          top: _colorFor(t.level),
          gapMeters: gap,
          total: 10,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CarsPainter old) => old.threats != threats;
}
