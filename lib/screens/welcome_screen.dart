import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ble_radar_service.dart';
import '../theme/hud_colors.dart';
import '../widgets/hud_dialog.dart';
import 'ride_hud_screen.dart';

/// 啟動後的歡迎畫面：按「連線」搜尋並連上 AMB82 雷達模組後進入 HUD（藍牙數據），
/// App 離開（進入背景）再回來時，會回到此畫面；離開前若已連線，回來後自動重新連線。
/// 「使用模擬數據繼續」預設隱藏，長按「連線」按鈕才會顯示（不存檔，重開 App 即恢復隱藏）。
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with WidgetsBindingObserver {
  final _ble = BleRadarService.instance;
  bool _showSimulation = false;
  // 只有真正進入背景（paused）才算「離開」；下拉通知列、系統對話框只會 inactive，不處理。
  bool _wasPaused = false;
  bool _reconnectOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
      // 已連線就先乾淨斷線，回來時再重連（HUD 會因斷線自動關閉）。
      _reconnectOnResume = _ble.status.value == BleRadarStatus.connected;
      if (_reconnectOnResume) unawaited(_ble.disconnect());
    } else if (state == AppLifecycleState.resumed && _wasPaused) {
      _wasPaused = false;
      _returnToWelcome();
    }
  }

  void _returnToWelcome() {
    if (!mounted) return;
    // 關掉 HUD、選單、對話框等所有疊在歡迎頁上的畫面。
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (_reconnectOnResume) {
      _reconnectOnResume = false;
      unawaited(_connect());
    }
  }

  Future<void> _connect() async {
    await _ble.connect();
    if (!mounted) return;
    if (_ble.status.value == BleRadarStatus.connected) {
      await _openHud(RideHudMode.ble);
    } else {
      await _showError(_ble.lastError.value ?? '連線未完成，請重試');
    }
  }

  Future<void> _showError(String error) =>
      showHudDialog(context, title: '藍牙連線失敗', message: error);

  Future<void> _openHud(RideHudMode mode) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RideHudScreen(mode: mode)),
    );
    // 只在仍連線時才斷線，避免誤斷剛重新發起的連線。
    if (mode == RideHudMode.ble && _ble.status.value == BleRadarStatus.connected) {
      await _ble.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final titleStyle = textTheme.displaySmall?.copyWith(
      fontSize: 38,
      height: 1.25,
      color: HudColors.ink,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: HudColors.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _WelcomeBackdrop(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ValueListenableBuilder<BleRadarStatus>(
                  valueListenable: _ble.status,
                  builder: (context, status, _) {
                    final busy = status == BleRadarStatus.scanning || status == BleRadarStatus.connecting;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: MediaQuery.sizeOf(context).height * 0.02),
                        Text('騎得安心。', style: titleStyle?.copyWith(fontWeight: FontWeight.w300)),
                        Text('自行車警示系統', style: titleStyle?.copyWith(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton(
                            onPressed: busy ? null : _connect,
                            onLongPress: busy ? null : () => setState(() => _showSimulation = true),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              disabledBackgroundColor: Colors.white70,
                              disabledForegroundColor: Colors.black54,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                            ),
                            child: Text(
                              switch (status) {
                                BleRadarStatus.scanning => '搜尋中…',
                                BleRadarStatus.connecting => '連線中…',
                                _ => '連線',
                              },
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        // 固定保留高度，顯示/隱藏時不會讓上方版面位移。
                        SizedBox(
                          height: 72,
                          width: double.infinity,
                          child: _showSimulation
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    TextButton(
                                      onPressed: busy ? null : () => _openHud(RideHudMode.simulation),
                                      child: Text('使用模擬數據繼續',
                                          style: textTheme.bodyMedium?.copyWith(
                                              color: HudColors.ink, fontWeight: FontWeight.w600)),
                                    ),
                                    ValueListenableBuilder<bool>(
                                      valueListenable: _ble.debugMode,
                                      builder: (context, on, _) => TextButton(
                                        onPressed: () => _ble.debugMode.value = !on,
                                        child: Text('除錯模式：${on ? '開' : '關'}',
                                            style: textTheme.bodySmall?.copyWith(
                                                color: on ? HudColors.danger : HudColors.inkDim)),
                                      ),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 歡迎頁背景：自行車照片鋪在上方、底部漸層融入黑底，
/// 上方另有壓暗漸層讓標題清楚可讀；底部留給按鈕。
class _WelcomeBackdrop extends StatelessWidget {
  const _WelcomeBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: 150,
          child: Image.asset(
            'assets/welcome.jpg',
            fit: BoxFit.cover,
            alignment: const Alignment(-0.45, 0),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Color(0x00000000), Color(0x00000000), Color(0xFF0A0B0D), Color(0xFF0A0B0D)],
              stops: [0, 0.3, 0.55, 0.82, 1],
            ),
          ),
        ),
      ],
    );
  }
}
