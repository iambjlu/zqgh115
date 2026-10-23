import 'package:flutter/foundation.dart';

/// 車輛前方某個方向的路況：沒有 / 坑洞 / 障礙物 / 坑洞加障礙物。
/// [code] 對應 BLE 協定的 0 / 1 / 2 / 3。
enum FrontHazard {
  none(0),
  pothole(1),
  obstacle(2),
  both(3);

  const FrontHazard(this.code);

  final int code;

  bool get hasPothole => this == pothole || this == both;
  bool get hasObstacle => this == obstacle || this == both;

  static FrontHazard? fromCode(int code) {
    for (final h in values) {
      if (h.code == code) return h;
    }
    return null;
  }
}

/// 模擬面板目前的數值狀態：自身車速、左右後方車輛的距離（下拉選單挑選）
/// 與是否正在逼近（開關），以及前方三個方向（左前／正前／右前）的路況（坑洞、障礙物）。
@immutable
class SimulationValues {
  const SimulationValues({
    required this.bikeSpeed,
    required this.leftDistance,
    required this.leftApproaching,
    required this.rightDistance,
    required this.rightApproaching,
    required this.frontLeft,
    required this.frontCenter,
    required this.frontRight,
  });

  static const demo = SimulationValues(
    bikeSpeed: 20,
    leftDistance: 15, // 中
    leftApproaching: false,
    rightDistance: 5, // 近
    rightApproaching: true,
    frontLeft: FrontHazard.both,
    frontCenter: FrontHazard.both,
    frontRight: FrontHazard.both,
  );


  /// 藍牙模式剛進入、尚未收到任何數據時的初始畫面：全部安全、無警示。
  static const empty = SimulationValues(
    bikeSpeed: 0,
    leftDistance: 99, // 沒車
    leftApproaching: false,
    rightDistance: 99,
    rightApproaching: false,
    frontLeft: FrontHazard.none,
    frontCenter: FrontHazard.none,
    frontRight: FrontHazard.none,
  );

  final double bikeSpeed;
  final double leftDistance;
  final bool leftApproaching;
  final double rightDistance;
  final bool rightApproaching;
  final FrontHazard frontLeft;
  final FrontHazard frontCenter;
  final FrontHazard frontRight;

  SimulationValues copyWith({
    double? bikeSpeed,
    double? leftDistance,
    bool? leftApproaching,
    double? rightDistance,
    bool? rightApproaching,
    FrontHazard? frontLeft,
    FrontHazard? frontCenter,
    FrontHazard? frontRight,
  }) {
    return SimulationValues(
      bikeSpeed: bikeSpeed ?? this.bikeSpeed,
      leftDistance: leftDistance ?? this.leftDistance,
      leftApproaching: leftApproaching ?? this.leftApproaching,
      rightDistance: rightDistance ?? this.rightDistance,
      rightApproaching: rightApproaching ?? this.rightApproaching,
      frontLeft: frontLeft ?? this.frontLeft,
      frontCenter: frontCenter ?? this.frontCenter,
      frontRight: frontRight ?? this.frontRight,
    );
  }
}
