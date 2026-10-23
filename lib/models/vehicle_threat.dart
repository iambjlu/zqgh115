import 'package:flutter/material.dart';

enum ThreatSide { left, right }

enum ThreatLevel { safe, caution, danger }

/// 偵測門檻：距離達到 [safeDistance] 視為安全，
/// 低於 [cautionDistance] 視為危險，中間為注意。
class ThreatThresholds {
  static const double safeDistance = 25; // 公尺
  static const double cautionDistance = 10; // 公尺

  /// 「沒車」的距離值（遠 30m 以外的哨兵值），用來和「遠」區分：沒車不畫、遠畫綠色。
  static const double noVehicleDistance = 99; // 公尺
}

@immutable
class VehicleThreat {
  const VehicleThreat({
    required this.side,
    required this.distanceMeters,
    required this.isApproaching,
  });

  final ThreatSide side;
  final double distanceMeters;
  final bool isApproaching;

  /// 該側是否偵測到車輛（距離為「沒車」哨兵值時為 false）。
  bool get hasVehicle => distanceMeters < ThreatThresholds.noVehicleDistance;

  ThreatLevel get level {
    if (distanceMeters >= ThreatThresholds.safeDistance) return ThreatLevel.safe;
    if (distanceMeters >= ThreatThresholds.cautionDistance) return ThreatLevel.caution;
    return ThreatLevel.danger;
  }

  /// 該側顯示的偵測弧線數量：越安全弧線越多、越危險弧線越少越貼近。
  int get arcCount {
    switch (level) {
      case ThreatLevel.safe:
        return 3;
      case ThreatLevel.caution:
        return 2;
      case ThreatLevel.danger:
        return 1;
    }
  }

  String get label => side == ThreatSide.left ? '左後方' : '右後方';
}
