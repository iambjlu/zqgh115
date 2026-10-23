import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/simulation_values.dart';
import '../models/vehicle_threat.dart';

enum BleRadarStatus { idle, scanning, connecting, connected }

enum RadarDataStatus { waiting, receiving, stale, invalid }

/// Current firmware sends one complete 13-byte ASCII CSV per notification.
/// It contains simulated values, not inference results or measured distances.
class BleRadarService {
  BleRadarService._();
  static final instance = BleRadarService._();
  static const deviceName = 'AMB82-Radar';
  static const deviceMac = '00:E0:4C:0F:60:67';
  static final serviceUuid = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final txUuid = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E');
  final status = ValueNotifier<BleRadarStatus>(BleRadarStatus.idle);
  final dataStatus = ValueNotifier<RadarDataStatus>(RadarDataStatus.waiting);
  final receivedCount = ValueNotifier<int>(0);
  final rawPacket = ValueNotifier<String>('');
  final lastError = ValueNotifier<String?>(null);
  // 除錯模式：HUD 下方列出收到的原始資料（含無法解析者），由歡迎畫面開關。
  final debugMode = ValueNotifier<bool>(false);
  final rawLog = ValueNotifier<List<String>>(const []);
  static const _rawLogLimit = 50;
  final _values = StreamController<SimulationValues>.broadcast();
  Stream<SimulationValues> get values => _values.stream;
  SimulationValues _latest = SimulationValues.empty;
  SimulationValues get latest => _latest;
  BluetoothDevice? _device;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _dataSub;
  Timer? _staleTimer;
  bool _busy = false;

  Future<void> connect({bool direct = false}) async {
    if (_busy || status.value != BleRadarStatus.idle) return;
    _busy = true;
    var stage = '檢查藍牙狀態';
    lastError.value = null;
    receivedCount.value = 0;
    rawPacket.value = '';
    rawLog.value = const [];
    dataStatus.value = RadarDataStatus.waiting;
    status.value = direct ? BleRadarStatus.connecting : BleRadarStatus.scanning;
    try {
      if (!await FlutterBluePlus.isSupported) {
        throw StateError('手機不支援 BLE');
      }
      if (Platform.isAndroid) await FlutterBluePlus.turnOn();
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 10));
      stage = '掃描裝置';
      BluetoothDevice device;
      if (direct && Platform.isAndroid) {
        device = BluetoothDevice.fromId(deviceMac);
      } else {
        final found = Completer<BluetoothDevice?>();
        String? scanError;
        _scanSub = FlutterBluePlus.onScanResults.listen(
          (results) {
            for (final r in results) {
              // Do not select arbitrary devices exposing the generic UART UUID.
              if (r.advertisementData.advName == deviceName ||
                  (Platform.isAndroid &&
                      r.device.remoteId.str.toUpperCase() == deviceMac)) {
                if (!found.isCompleted) found.complete(r.device);
              }
            }
          },
          onError: (Object error) {
            scanError = error.toString();
            if (!found.isCompleted) found.complete(null);
          },
        );
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
        try {
          final result = await found.future.timeout(
            const Duration(seconds: 12),
          );
          if (result == null) throw StateError('掃描失敗：$scanError');
          device = result;
        } on TimeoutException {
          throw StateError('未找到 $deviceName。請重啟板子、關閉 nRF Connect 的連線，並確認藍牙權限。');
        } finally {
          await FlutterBluePlus.stopScan();
          await _scanSub?.cancel();
          _scanSub = null;
        }
      }
      stage = '連線並訂閱 Notify';
      await _connectTo(device);
      debugPrint('[BLE] 已連線：${device.remoteId.str}');
    } catch (e, st) {
      lastError.value = '連線失敗（階段：$stage）\n$e';
      debugPrint('[BLE] 連線失敗（階段：$stage）：$e\n$st');
      await disconnect();
    } finally {
      _busy = false;
    }
  }

  Future<void> _connectTo(BluetoothDevice device) async {
    status.value = BleRadarStatus.connecting;
    _device = device;
    // Android 的 GATT error 133 多為舊連線／快取殘留或剛掃描完立刻連線，
    // 斷開、清快取、稍等後重試通常可恢復。
    const maxAttempts = 3;
    for (var attempt = 1; ; attempt++) {
      try {
        debugPrint(
          '[BLE] connect 嘗試 $attempt/$maxAttempts：${device.remoteId.str}',
        );
        await device.connect(
          license: License.nonprofit,
          timeout: const Duration(seconds: 15),
          mtu: null,
        );
        break;
      } on FlutterBluePlusException catch (e) {
        debugPrint('[BLE] connect 嘗試 $attempt 失敗：$e');
        if (attempt >= maxAttempts || e.code != 133) {
          throw StateError(
            '$e（已嘗試 $attempt 次；Android 133 通常是 GATT 連線建立失敗，'
            '請重啟 AMB82、關閉手機藍牙再開啟後重試）',
          );
        }
        await device.disconnect().catchError((_) {});
        if (Platform.isAndroid)
          await device.clearGattCache().catchError((_) {});
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    // Subscribe after connect: its initial disconnected event must not cancel
    // an in-progress connection. Every reconnection rediscovers the service.
    _connSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        lastError.value = 'AMB82 已斷線，請確認供電後重新連線。';
        debugPrint('[BLE] 連線中斷');
        unawaited(disconnect());
      }
    });
    final services = await device.discoverServices();
    final tx =
        services
            .where((s) => s.uuid == serviceUuid)
            .expand((s) => s.characteristics)
            .where((c) => c.uuid == txUuid)
            .firstOrNull;
    if (tx == null || !tx.properties.notify) {
      throw StateError('裝置沒有預期的雷達 TX Notify 服務');
    }
    _dataSub = tx.onValueReceived.listen(_onData);
    await tx.setNotifyValue(true);
    if (_device != device || !device.isConnected) {
      throw StateError('訂閱通知時裝置已斷線');
    }
    status.value = BleRadarStatus.connected;
    _armStaleTimer();
  }

  void _armStaleTimer() {
    _staleTimer?.cancel();
    _staleTimer = Timer(const Duration(seconds: 5), () {
      dataStatus.value = RadarDataStatus.stale;
    });
  }

  void _onData(List<int> data) {
    final raw = utf8.decode(data, allowMalformed: true);
    final text = raw.trim();
    rawPacket.value = text;
    final parsed = parse(text, _latest);
    if (debugMode.value) _appendRawLog(raw, data.length, parsed != null);
    if (parsed == null) {
      dataStatus.value = RadarDataStatus.invalid;
      debugPrint('[BLE] 收到無法解析的資料：$text');
      return;
    }
    _latest = parsed;
    receivedCount.value++;
    dataStatus.value = RadarDataStatus.receiving;
    _armStaleTimer();
    _values.add(parsed);
  }

  // 新的在最前面；換行等不可見字元以跳脫字串顯示，方便看出分包問題。
  void _appendRawLog(String text, int bytes, bool ok) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final time =
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
    final shown = text.replaceAll('\n', r'\n').replaceAll('\r', r'\r');
    final line = '$time  [$bytes B]  $shown  ${ok ? '✓' : '✗ 無法解析'}';
    rawLog.value = [line, ...rawLog.value].take(_rawLogLimit).toList();
  }

  /// 解析一行 7 欄資料，欄位依序為：
  /// 左後距離、右後距離（0 沒車／1 遠／2 中／3 近）、左後逼近、右後逼近、
  /// 左前、正前、右前（0 沒坑沒障礙／1 有坑／2 有障礙／3 有坑有障礙）；任何欄位為 9 代表感測錯誤，
  /// 整筆資料無效，不把舊值當成新資料。欄位以逗號分隔，也接受 7 個連續數字。
  /// 格式不符回傳 null。車速不在此協定內，沿用 [base.bikeSpeed]。
  @visibleForTesting
  static SimulationValues? parse(String line, SimulationValues base) {
    final text = line.trim();
    final parts =
        text.contains(',')
            ? text.split(',').map((e) => e.trim()).toList()
            : text.split('');
    if (parts.length != 7) return null;
    final n = parts.map(int.tryParse).toList();
    if (n.any((e) => e == null)) return null;

    double? distance(int code) => switch (code) {
      0 => ThreatThresholds.noVehicleDistance, // 沒車（與「遠」區分）
      1 => 30.0, // 遠
      2 => 15.0, // 中
      3 => 5.0, // 近
      _ => null,
    };
    bool? flag(int code) => switch (code) {
      1 => true,
      0 => false,
      _ => null,
    };

    final left = distance(n[0]!);
    final right = distance(n[1]!);
    final la = flag(n[2]!);
    final ra = flag(n[3]!);
    final fl = FrontHazard.fromCode(n[4]!);
    final fc = FrontHazard.fromCode(n[5]!);
    final fr = FrontHazard.fromCode(n[6]!);
    if ([left, right, la, ra, fl, fc, fr].contains(null)) return null;
    return base.copyWith(
      leftDistance: left,
      rightDistance: right,
      leftApproaching: la,
      rightApproaching: ra,
      frontLeft: fl,
      frontCenter: fc,
      frontRight: fr,
    );
  }

  Future<void> disconnect() async {
    final device = _device;
    _device = null;
    _staleTimer?.cancel();
    _staleTimer = null;
    await _connSub?.cancel();
    _connSub = null;
    await _dataSub?.cancel();
    _dataSub = null;
    await _scanSub?.cancel();
    _scanSub = null;
    await FlutterBluePlus.stopScan().catchError((_) {});
    await device?.disconnect().catchError((_) {});
    _latest = SimulationValues.empty;
    dataStatus.value = RadarDataStatus.waiting;
    status.value = BleRadarStatus.idle;
  }
}
