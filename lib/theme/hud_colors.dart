import 'package:flutter/material.dart';

/// 深色儀表風 HUD 配色：近黑底、白字，車速儀表與道路檢視使用中性灰階，
/// 只有語意色（安全/注意/危險）與儀表指針綠帶有顏色。
class HudColors {
  HudColors._();

  // 主畫面：近黑底
  static const Color surface = Color(0xFF0A0B0D);
  static const Color panel = Color(0xFF15171B);
  static const Color road = Color(0xFF2B2F36);
  static const Color hairline = Color(0x24FFFFFF);

  static const Color ink = Color(0xFFFFFFFF);
  static const Color inkDim = Color(0xFFA1A7B1);
  static const Color inkFaint = Color(0xFF5E646E);

  // 儀表指針綠
  static const Color gauge = Color(0xFF6BD968);

  // 品牌色：僅用於浮動按鈕與模擬面板等互動元件
  static const Color brand = Color(0xFF0066B1);
  static const Color brandDim = Color(0x1F0066B1);

  // 語意色：安全 / 注意 / 危險
  static const Color safe = Color(0xFF3DD16F);
  static const Color safeDim = Color(0x293DD16F);
  static const Color warn = Color(0xFFF5B83A);
  static const Color warnDim = Color(0x29F5B83A);
  static const Color danger = Color(0xFFFF4B3E);
  static const Color dangerDim = Color(0x29FF4B3E);
}
