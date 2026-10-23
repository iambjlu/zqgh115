import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/welcome_screen.dart';
import 'services/alert_notification_service.dart';
import 'theme/hud_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 版面為直向設計，強制鎖定直向避免跑版。
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await AlertNotificationService.instance.init();
  runApp(const RideHudApp());
}

class RideHudApp extends StatelessWidget {
  const RideHudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'chc11509',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: HudColors.surface,
        dialogTheme: const DialogThemeData(
          backgroundColor: HudColors.panel,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(3))),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: HudColors.panel,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(3))),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: HudColors.panel,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(3))),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1D2025),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(3))),
        ),
        snackBarTheme: const SnackBarThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(3))),
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: HudColors.brand,
          brightness: Brightness.dark,
        ),
      ),
      home: const WelcomeScreen(),
    );
  }
}
