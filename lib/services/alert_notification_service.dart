import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 危險事件的分類，每一類在系統通知中各自固定一個通知 id，
/// 因此同一類的新通知會直接覆蓋舊通知，畫面上只會保留該類最新的一則。
enum HazardCategory {
  pothole, // 坑洞：左前/正前/右前共用同一則通知
  approaching, // 逼近車輛：左右後方共用同一則通知
  distanceShortening, // 距離縮短：左右後方共用同一則通知
  obstacle, // 障礙物：左前/正前/右前共用同一則通知
}

/// 坑洞、障礙物、車輛逼近等危險事件的警示單例。
///
/// 提示音一律由 App 自己播放（`audioplayers` 播放內建的 `assets/sounds/beep.wav` 短音），
/// 不使用系統通知的聲音：音訊 session 設為 `playback`，iOS 即使手機切成靜音
/// （響鈴/靜音切換鍵）也會照常出聲。
/// Android：仍會發出系統通知（max importance + heads-up）顯示文字，但通知頻道
/// 為無聲（`playSound: false`），聲音交給 App 播放。
/// iOS：不申請通知權限、不使用 `UNUserNotificationCenter`（前景時系統通知橫幅
/// 不一定會顯示），畫面上由 `RideHudScreen` 改用 SnackBar 顯示。
/// 兩平台都搭配一段較長的觸覺震動（連續多次 `heavyImpact`），讓騎士即使
/// 沒看螢幕也能感知警示。
class AlertNotificationService {
  AlertNotificationService._();

  static final AlertNotificationService instance = AlertNotificationService._();

  // 舊的 'ride_hazard_alerts' 頻道建立時帶有通知音，頻道設定建立後無法修改，
  // 因此改用新的無聲頻道 id，並在 init() 刪除舊頻道。
  static const _legacyChannelId = 'ride_hazard_alerts';
  static const _channelId = 'ride_hazard_alerts_silent';
  static const _channelName = '騎乘危險警示';
  static const _channelDescription = '坑洞、障礙物與車輛逼近的即時警示通知';
  static const _beepAsset = 'sounds/beep.wav';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _player = AudioPlayer();

  /// 聲音開關（選單控制），關閉時不發出任何提示音（震動與通知不受影響）。
  /// 預設關閉，設定會用 `shared_preferences` 記住（`init()` 讀回、變更時寫入）。
  final ValueNotifier<bool> soundEnabled = ValueNotifier(false);
  static const _soundPrefKey = 'sound_enabled';

  Timer? _beepTimer;
  int _beepIntervalMs = 0;
  bool _beepReady = false;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      soundEnabled.value = prefs.getBool(_soundPrefKey) ?? false;
      soundEnabled.addListener(() {
        prefs.setBool(_soundPrefKey, soundEnabled.value);
      });
    } catch (e) {
      debugPrint('[Sound] 讀取聲音設定失敗：$e');
    }
    // playback 類別會忽略 iOS 的靜音切換鍵，確保警示音一定聽得到。
    try {
      await _player.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
          android: const AudioContextAndroid(
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.none, // 不搶其他 App 的音訊焦點
          ),
        ),
      );
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSource(AssetSource(_beepAsset));
      _beepReady = true;
    } catch (e) {
      debugPrint('[Sound] 初始化提示音失敗：$e');
    }
    if (Platform.isIOS) return; // iOS 不使用系統通知，見上方類別註解。
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.deleteNotificationChannel(channelId: _legacyChannelId);

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.max,
            playSound: false, // 提示音由 App 播放
            enableVibration: false, // 震動由 HapticFeedback 統一觸發，避免重複震動
          ),
        );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  // Android：用同一個 category 固定同一個通知 id 呼叫 _plugin.show，讓新通知
  // 直接覆蓋舊通知，達到「該類別只保留最新一則」的效果。
  // 兩平台都由 App 播放提示音；iOS 不發系統通知，畫面上的 SnackBar 由呼叫端
  // （RideHudScreen）另外處理，因為此服務沒有 BuildContext。
  Future<void> notifyHazard({
    required HazardCategory category,
    required String title,
    required String body,
  }) async {
    if (Platform.isIOS) {
      await _longVibration();
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      playSound: false,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    );

    await _plugin.show(
      id: category.index,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
    await _longVibration();
  }

  /// 依目前路況更新持續的嗶嗶聲。[intervalMs] 為嗶聲間隔（越小越急促），
  /// null 表示沒有路況、停止發聲。聲音關閉時一律停止。
  void updateBeep(int? intervalMs) {
    if (intervalMs == null || !soundEnabled.value) {
      _beepTimer?.cancel();
      _beepTimer = null;
      _beepIntervalMs = 0;
      return;
    }
    if (_beepTimer != null && _beepIntervalMs == intervalMs) return;
    _beepTimer?.cancel();
    _beepIntervalMs = intervalMs;
    _beep();
    _beepTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) => _beep(),
    );
  }

  Future<void> _beep() async {
    try {
      if (!_beepReady) {
        await _player.setSource(AssetSource(_beepAsset));
        _beepReady = true;
      }
      await _player.seek(Duration.zero);
      await _player.resume();
    } catch (e) {
      debugPrint('[Sound] 播放提示音失敗：$e');
    }
  }

  // 連續三次重擊震動、中間間隔 150ms，模擬出比單次 heavyImpact 更長的震動感。
  Future<void> _longVibration() async {
    for (var i = 0; i < 3; i++) {
      HapticFeedback.heavyImpact();
      if (i < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
  }
}
