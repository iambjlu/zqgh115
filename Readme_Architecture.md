# chc115 專案架構文件

## 專案簡介

`chc115` 是一個 Flutter 行動應用，實作「騎乘後方雷達 HUD」（Ride HUD）：
畫面上半部顯示指針式車速儀表與 Google 地圖（依裝置目前位置置中），
下半部則以虛擬道路檢視呈現左右後方來車的威脅程度（安全／注意／危險）與
前方路況（坑洞、障礙物）預警。左下角浮動按鈕可開啟「模擬控制面板」，用來手動調整
車速、左右後方車距／是否逼近、前方三個方向的路況等數值，方便在沒有真實感測
硬體的情況下展示與測試 HUD 的各種狀態。

- 平台：Flutter App（Android、iOS）
- 語言：Dart（SDK `^3.7.2`）
- 主要套件：`google_maps_flutter`、`geolocator`、`flutter_blue_plus`（BLE）、`audioplayers`、`shared_preferences`

## 目錄結構

```
chc115/
├── lib/                        # 應用程式原始碼
│   ├── main.dart                # App 進入點（MaterialApp 設定）
│   ├── models/                  # 純資料模型（不含 Widget）
│   │   ├── simulation_values.dart
│   │   └── vehicle_threat.dart
│   ├── screens/                 # 頁面層（組合各個 widget）
│   │   ├── welcome_screen.dart
│   │   └── ride_hud_screen.dart
│   ├── widgets/                 # 可重用/局部 UI 元件
│   │   ├── map_card.dart
│   │   ├── live_google_map.dart
│   │   ├── road_view.dart
│   │   ├── speed_gauge.dart
│   │   ├── hud_dialog.dart
│   │   └── simulation_sheet.dart
│   ├── services/                # 與 UI 無關的服務層
│   │   ├── alert_notification_service.dart
│   │   └── ble_radar_service.dart
│   └── theme/                   # 視覺樣式
│       └── hud_colors.dart
├── assets/                      # 靜態資源（如 bike.png）
├── arduino/                     # AMB82 板子端程式（AMB82_Grove_SSCMA/）、note.md（工具安裝／編譯上傳筆記）、App接收格式.xlsx
├── test/                        # Widget/單元測試
├── android/ , ios/               # 平台專案（原生殼層、金鑰設定）
└── pubspec.yaml                  # 套件與資源設定
```

## 分層架構

專案採用簡單的四層結構，資料單向由上層流向下層 UI：

```
main.dart
   │  建立 MaterialApp，套用 HudColors 主題，首頁為 WelcomeScreen
   ▼
screens/welcome_screen.dart  ──「連線」／「使用模擬數據繼續」──┐
                                                           ▼
screens/ride_hud_screen.dart      ← 狀態持有者（StatefulWidget）
   │  持有 SimulationValues 狀態；衍生出 List<VehicleThreat>
   ├──> widgets/map_card.dart → widgets/live_google_map.dart
   ├──> widgets/speed_gauge.dart（指針式車速儀表）
   ├──> widgets/road_view.dart（虛擬道路檢視，依 threats/坑洞旗標繪製）
   └──> widgets/simulation_sheet.dart（modal bottom sheet，回傳新的 SimulationValues）
```

### models（資料模型）

- **`SimulationValues`**：不可變（`@immutable`）的模擬面板狀態，包含
  自身車速、左右後方距離與是否逼近、前方三個方向（左前／正前／右前）的路況 `FrontHazard`（無／坑洞／障礙物／坑洞加障礙物，`code` 對應 BLE 的 0／1／2／3，另有 `hasPothole`／`hasObstacle`）。提供
  `copyWith` 供局部更新，並附帶 `demo` 常數作為初始展示資料（車速 20、左後中距離無逼近、右後近距離逼近中、前方三向皆為坑洞加障礙物）。
- **`VehicleThreat`**：依「距離＋是否逼近」推導出的後方車輛威脅資訊。
  - `ThreatThresholds`：安全／注意／危險的距離門檻常數。
  - `level`（`ThreatLevel`：safe/caution/danger）：由距離換算。
  - `arcCount`：依威脅等級決定雷達要畫幾層弧線。
  - `label`：中文方位文字（「左後方」／「右後方」）。

### screens（頁面／狀態管理）

- **`WelcomeScreen`**：App 首頁（`MaterialApp.home`）。「連線」按鈕呼叫
  `BleRadarService.connect()`，成功則 push `RideHudScreen(mode: ble)`，
  失敗時只用 `showHudDialog`（可選取文字）顯示
  `BleRadarService.lastError` 的確切原因（含失敗階段與例外內容）；按鈕依
  `BleRadarService.status` 顯示搜尋中／連線中並停用。
  畫面為全幅深色背景（`_WelcomeBackdrop`：`assets/welcome.jpg` 自行車照片鋪在上方、底部漸層融入黑底、上方壓暗漸層），左上為兩行標題（細體「騎得安心。」、粗體「自行車警示系統」），底部為白色方形「連線」按鈕。
  「使用模擬數據繼續」按鈕預設隱藏，長按「連線」按鈕才會顯示（僅存在
  `_showSimulation` 狀態，不持久化，重開 App 即恢復隱藏），按下後 push
  `RideHudScreen(mode: simulation)`。同一列旁邊還有「除錯模式：開／關」切換
  （同樣長按後才出現），對應 `BleRadarService.debugMode`；開啟後藍牙 HUD
  下方會顯示原始資料面板。
  實作 `WidgetsBindingObserver` 監聽 App lifecycle：App 進入背景（`paused`）
  時若已連線會乾淨斷線、標記 `_reconnectOnResume`；回到前景（`resumed`）
  時以 `popUntil(isFirst)` 關閉所有疊層後回到歡迎頁首頁，若有標記則自動
  重新呼叫 `_connect()`。下拉通知列、系統對話框只會觸發 `inactive`，不會
  處理。

- **`RideHudScreen`**：唯一的頁面，也是狀態持有者。
  - 內部持有 `SimulationValues _sim`（初始為 `demo`）。
  - 由 `_sim` 衍生 `_threats`（`List<VehicleThreat>`）。畫面上不再顯示逼近／坑洞障礙物的文字提示，
    只靠弧形燈條、坑洞圖形、系統通知與提示音呈現。
  - `_openSimulationSheet()` 開啟 `SimulationSheet`，透過 `onChanged`
    回呼以 `setState` 更新 `_sim`，形成單向資料流：
    `SimulationSheet 使用者輸入 → RideHudScreen.setState → 重新計算 threats/alert → 往下傳給 RoadView`。
  - `_applySimulationValues()`：在 `setState` 更新前後比較新舊
    `SimulationValues`，觸發 `services/alert_notification_service.dart`
    的 `AlertNotificationService.notifyHazard()`（系統通知＋一次震動），
    分成三個類別各自呼叫，同類別新通知會覆蓋舊通知（見 services 章節
    的 `HazardCategory`），因此每個類別畫面上永遠只保留最新一則：
    - 距離縮短（`HazardCategory.distanceShortening`）：左右後方只要
      新距離比前一次更近（`leftDistance`／`rightDistance` 變小）就
      觸發一次，不論 `leftApproaching`／`rightApproaching` 開關是否
      開啟；標題為「左（右）後方車輛逐漸接近」。
    - 逼近車輛（`HazardCategory.approaching`）：`leftApproaching`／
      `rightApproaching` 由假變真才觸發一次，避免開關持續開啟時反覆
      通知；標題為「左（右）後方車輛逼近」，內文為「左（右）後方車輛
      正在逼近中」，只敘述目前狀態、不含變換車道等行動建議。
    - 坑洞（`HazardCategory.pothole`）：左前/正前/右前的 `hasPothole` 由無變有才
      觸發一次，避免同一坑洞持續存在時反覆通知；三個方向共用同一個
      通知 id，因此只會保留最新觸發的那一個方向。
    - 障礙物（`HazardCategory.obstacle`）：`hasObstacle` 由無變有才觸發一次，標題為
      「前方左側／中央／右側障礙物」，三個方向共用同一個通知 id。
  - 持續嗶聲：`_updateBeep()` 在每次數據更新與聲音開關變動時，依前方危險算分（左前／右前各 1、正前 2、坑洞加障礙物同方向再 +1），
    無危險則停止；有危險則呼叫 `updateBeep(間隔ms)`，間隔 = `900 − 分數×150`（限制 250～750ms），危險越多越急促。離開頁面時停止。
    目前協定沒有前方距離，日後有距離可在此改為依距離換算。
  - 以 `RideHudMode`（`ble`／`simulation`）決定資料來源。`ble` 模式初始為
    `SimulationValues.empty`（全部安全、車速 0），`initState()` 訂閱
    `BleRadarService.values`，收到的數據（車速沿用目前值）直接餵給
    `_applySimulationValues()`，與模擬面板共用同一條更新／通知比對路徑；
    同時監聽 `status`，藍牙中途斷線（回到 idle）時自動 pop 回歡迎畫面。
    `simulation` 模式使用 `SimulationValues.demo`。
  - 左下角為 `PopupMenuButton` 選單（≡ 圖示的 FAB）：「聲音：開／關」（切換 `AlertNotificationService.soundEnabled`）、「斷線」（藍牙模式會
    先 `BleRadarService.disconnect()`，再回到歡迎畫面）；僅模擬模式額外有
    「模擬控制」項目以開啟 `SimulationSheet`。
  - 藍牙模式的車速改用 GPS：`initState()` 呼叫 `_startGps()`，檢查定位服務與
    權限（必要時請求）後訂閱 `Geolocator.getPositionStream`（`LocationAccuracy.best`），
    `Position.speed`（m/s）換算為 km/h 並四捨五入、低於 1 km/h 視為 0，存入
    `_gpsSpeed` 供 `SpeedGauge` 顯示；未取得定位或權限被拒時顯示「—」。`dispose()`
    取消訂閱。模擬模式仍使用模擬面板的車速滑桿。
  - 除錯模式（`BleRadarService.debugMode` 開啟且為藍牙模式）時，雷達下方多一個
    黑底 `_RawDataPanel`（高 150，底部留白避開左下選單鈕），監聽 `rawLog`
    列出原始資料，可解析為綠字、無法解析為紅字。
  - Android 上 `SpeedGauge` 之上固定多一個 48dp 的 `SizedBox`，避免 heads-up
    系統通知橫幅蓋住車速讀數（iOS 不用系統通知，不需要）。
  - 畫面頂端是 `SpeedGauge`（車速儀表），其下依序為 `MapCard` 與 `RoadView`。

### services（服務層）

- **`HazardCategory`**（`enum`）：`pothole` / `approaching` /
  `distanceShortening` 三個危險事件類別，其 `index` 直接作為
  `flutter_local_notifications`（僅 Android 使用）的通知 id。
- **`AlertNotificationService`**：坑洞、障礙物、車輛逼近等危險事件的提示單例
  （`instance`）。**提示音一律由 App 自己播放**：用 `audioplayers` 的 `AudioPlayer`
  預載內建的 `assets/sounds/beep.wav`（90ms 短嗶），`init()` 設定 `AudioContext`（iOS `playback`、Android alarm 用途且不搶音訊焦點）並 `setSource`，之後每次 `seek(0)`＋`resume()` 播放；
  `soundEnabled`（`ValueNotifier<bool>`）為選單的聲音開關，預設關閉，並以 `shared_preferences` 記住設定（`init()` 讀回、變更時寫入）；`updateBeep(intervalMs)` 以 `Timer.periodic` 持續嗶聲（null 或聲音關閉則停止）；`notifyHazard()` 本身不再出聲，只發通知與震動；
  系統通知本身不再帶聲音。兩平台的畫面提示路徑不同：
  - **Android**：`main.dart` 於 `runApp` 前呼叫 `init()` 建立**無聲**通知頻道
    `ride_hazard_alerts_silent`（`Importance.max`、`playSound: false`，並刪除舊的
    有聲頻道 `ride_hazard_alerts`，因為頻道設定建立後無法修改）並請求通知權限；
    `notifyHazard({category, title, body})` 用 `flutter_local_notifications` 以
    `id: category.index` 顯示高優先權通知（heads-up，僅顯示文字），同時由 App 播放提示音
    並搭配長震動。由於同一 `category` 固定使用同一個通知 id，新通知會直接覆蓋舊通知，
    因此每個類別（坑洞／障礙物／逼近車輛／距離縮短）在系統通知列表中永遠只會保留最新一則。
  - **iOS**：完全不使用 `UNUserNotificationCenter`、不申請通知權限。原因是實測發現
    即使通知權限已授權，App 在前景時系統通知橫幅仍經常不會顯示
    （`interruptionLevel: timeSensitive` 需要額外的時效性通知 entitlement），
    因此 `notifyHazard()` 只播放提示音＋長震動；畫面提示改由
    `RideHudScreen._notifyHazard()` 在 iOS 上額外用 `ScaffoldMessenger`
    顯示浮動 `SnackBar`（`HudColors.danger` 背景、標題+內文兩行文字，
    顯示 3 秒，新警示會先 `hideCurrentSnackBar()` 再顯示；`RideHudScreen` 以 `PopScope` 在開始返回歡迎畫面的瞬間（含手勢返回、斷線）呼叫 `clearSnackBars()` 立即撤銷，`dispose()` 也再清一次，避免掛在全域 `ScaffoldMessenger` 上的 SnackBar 殘留到歡迎畫面），Android 則
    維持只靠系統通知呈現、不疊加 SnackBar。
  - 兩平台都呼叫 `_longVibration()`：連續 3 次 `HapticFeedback
    .heavyImpact()`、中間間隔 150ms，模擬出比單次震動更明顯的長震動感。
  - 兩平台的 `notifyHazard()` 呼叫端（`RideHudScreen`）內容一律只
    敘述目前狀態（如「左後方車輛逐漸接近」），不包含變換車道等行動
    建議。

- **`BleRadarService`**：與 AMB82 板子的 BLE 連線單例。掃描廣播名稱
  `AMB82-Radar`（或 service UUID `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`），
  連線後訂閱 TX characteristic（`6E400003-…`）的 Notify。每筆資料為一行
  ASCII CSV（7 欄，來源為 `arduino/App接收格式.xlsx`）：
  `左後距離,右後距離,左後逼近,右後逼近,左前,正前,右前`。距離 1 遠
  （30m）／2 中（15m）／3 近（5m）／0 沒車（`ThreatThresholds.noVehicleDistance` = 99，與「遠」區分，不畫弧條），逼近 1 有／0 沒有；前方三欄
  0 沒坑沒障礙／1 有坑／2 有障礙／3 有坑有障礙（`FrontHazard.fromCode`）；
  距離欄位為其他值、任何欄位為 9（感測錯誤）或格式不符，整筆視為無效
  （`parse()` 回傳 null，`dataStatus` 變 `invalid`，HUD 顯示「尚無有效資料」）；也接受 7 個連續數字。車速不在協定內。
  `debugMode`（`ValueNotifier<bool>`）開啟時，`_onData` 會把每筆收到的原始資料
  （時間、位元組數、跳脫換行後的文字、是否可解析）加入 `rawLog`（最新在前、
  最多 50 筆，每次 `connect()` 清空），含無法解析的資料。
  由 `parse(line, base)` 轉成 `SimulationValues`
  從 `values` Stream 推送；`status`（`BleRadarStatus`：idle／scanning／
  connecting／connected）為 `ValueNotifier` 供 UI 顯示。連線斷開會自動清理
  回到 idle。每個階段（藍牙檢查、掃描、連線並訂閱）的失敗原因與堆疊都會
  `debugPrint('[BLE] …')`，並記入 `lastError`。連線遇到 Android GATT error 133
  時會斷開、清除 GATT 快取、等 1 秒後自動重試，最多 3 次。`connect()` 需帶 `License.nonprofit`（`flutter_blue_plus` 2.x
  的授權聲明）。Android 需 `BLUETOOTH_SCAN`／`BLUETOOTH_CONNECT`，iOS 需
  `NSBluetoothAlwaysUsageDescription`。

### arduino（板子端）

- **`AMB82_Grove_SSCMA.ino`**：純 BLE UART 服務範例（參考 AmebaPro2 官方
  文件），不再包含 SSCMA 感測器整合。以 `BLEDevice.h` 建立 BLE Peripheral
  （廣播名稱 `AMB82-Radar`，包含 RX／TX 兩個 characteristic，僅 TX 開啟 Notify）。
  App 訂閱 TX characteristic 後，`loop()` 在 Notify 開啟且已連線時每秒呼叫
  `sendSimulatedRadar()` 送出一筆模擬數據（12 步一個循環，涵蓋左側遠→中→近、
  右側近→遠、左前／正前／右前的坑洞、障礙物、兩者並存等狀態），格式見 `BleRadarService`。
  開機時序列埠印出 `BLE_SIMULATED_7_FIELDS_1HZ_NO_GROVE`、`BLE_MAC=…`（輸入 `m`
  目前不支援重印，改為開機自動印出），供核對
  `BleRadarService.deviceMac`（掃描時也會以此 MAC 比對裝置）。草稿放在
  `AMB82_Grove_SSCMA/` 子資料夾（Arduino 要求資料夾與草稿同名）；工具安裝與
  arduino-cli 編譯／上傳指令見 `arduino/note.md`。若要換成真實數據，只需改
  `sendSimulatedRadar()` 內的取值來源。

### widgets（UI 元件）

- **`MapCard`**：純包裝層，將 `LiveGoogleMap` 裁切為圓角卡片（固定高度 150）。
- **`LiveGoogleMap`**：
  - 用 `geolocator` 取得裝置目前位置；若定位失敗（權限被拒/服務關閉）
    或 8 秒內未能取得定位（`Geolocator.getCurrentPosition()` 加上
    `.timeout()`，避免 iOS 在收不到定位訊號時無限期卡在轉圈圈），
    回退到硬編碼的備援座標（南台科技大學一帶）。
  - 用 `google_maps_flutter` 顯示深色地圖（`GoogleMap.style` 套用內建的 `_darkMapStyle` JSON），開啟原生「目前位置」藍點
    （`myLocationEnabled`），並提供右下角「回到目前位置」按鈕重新置中鏡頭。
  - Android/iOS 的 Google Maps API 金鑰分別位於
    `android/local.properties` 與 `ios/Flutter/ApiKeys.xcconfig`（不進版控）。
    版控中附上對應範本 `android/local.properties.example` 與
    `ios/Flutter/ApiKeys.xcconfig.example`（皆為 `MAPS_API_KEY=` 佔位字串），
    換機器/重新取回專案時複製成正式檔名（去掉 `.example`）並貼回真實
    金鑰即可，`android/local.properties` 的 `sdk.dir`／`flutter.sdk` 兩行則
    由本機 IDE／`flutter` 工具在開啟專案或執行指令時自動覆寫為正確路徑。
- **`SpeedGauge`**：車速儀表，仿 BMW 儀表造型。左側 `CustomPainter` 畫 V 形亮面金屬框
  （鉻金屬漸層加外緣亮邊）與向右淡出的深色玻璃面板（底部暖色反光、斜向眩光）；
  刻度為水平短線（車速與 y 座標線性對應，0 在底、`maxSpeed`＝25 km/h 在頂，
  每 1 km/h 一小刻度、每 5 一大刻度附數字）；指針是一條水平的亮綠條，帶光暈與
  左端星芒，依車速以 `TweenAnimationBuilder` 平滑移動（超過上限停在頂端）。
  右側為 104pt 細體大字車速（無資料顯示「—」）與 `km/h`。
- **`HudDialog`**（`showHudDialog`）：深色儀表風對話框，直角深灰面板、粗體標題、
  可選取文字的內文、底部全寬白色方形按鈕；歡迎頁的連線失敗訊息使用它。
  `main.dart` 另以主題統一 Dialog／BottomSheet／PopupMenu／Card／SnackBar 的深色直角風格。
- **`RoadView`**：整個 HUD 的視覺核心，`StatefulWidget` + `LayoutBuilder`（外包 `ClipRect`），
  以針孔透視（`_Cam`）將世界座標（自行車在原點、z 往前）投影到畫面，
  鏡頭在自行車後上方（高 20m、偏俯視），自行車約落在畫面 42% 高處：
  - 道路地面（不畫車道線，避免誤導為三車道視野；只有依車速往鏡頭方向捲動的淡色橫向格線）、前方路況由 `_RoadPainter`
    繪製，遠端以漸層淡出到背景色（先畫淡出再畫路況，遠處弧條不會被蓋暗）；中央疊放車輛圖示（`assets/bike.png`，放大 1.25 倍並在後方墊白色徑向光暈，避免與深色路面融為一體）。
  - 前方三個方向（左前／正前／右前，橫向間隔 2.8m）：坑洞畫成路面上的坑
    （透視橢圓，黃色外框加亮色坑緣，內部由遠端坑壁漸層到近黑的坑底，不與灰色路面
    融為一體），障礙物一律以自行車前方的分段弧形燈條（倒車雷達樣式，立體，分左前／正前／右前三區，有障礙物的區段亮橘色，每區涵蓋 60°）表示；坑洞畫在路面上，位置在各扇區中線方向（右前 30°、正前 90°、左前 150°）的弧條內側（縮小為 0.75 倍，避免壓到車把）；
    純路況提示、不閃爍。
  - 左／右後方來車由 `_CarsPainter` 以立體弧形燈條繪製在自行車後方半圈（9 小段，後方正中央留空，
    右後 5 段、左後 5 段，各涵蓋 90°）：沒車時不顯示；遠亮綠、中亮黃、近亮紅，每側固定 5 段（不隨距離變化），
    距離越近燈條離車身越近；標記為「逼近中」時硬切閃爍，由單一時鐘（`_Clock`，`Ticker`）驅動，
    左右同步（刻意不做透明度補間）。
  - 立體弧形燈條由共用函式 `_arcSegment` 繪製：以車身中心為圓心的橢圓環（半徑略大於車身，後方依距離 5～30m 向外推 0.9～1.7m，距離越近越貼車；前方固定 2.0m），每段以頂面、內外側壁與兩端斷面擠出 0.18m 厚度，
    外側帶光暈。前方障礙物（`_RoadPainter`）沿前方半圈分左前／正前／右前三區，各 3 段，
    因前方沒有距離判斷，一律使用橘色。
    painter 以時鐘作為 `repaint` 來源，捲動與閃爍不需重建整個 widget 樹。
- **`SimulationSheet`**：`StatefulWidget`，以 modal bottom sheet 形式提供：
  - 車速滑桿（`_SliderField`）。
  - 左／右後方車輛的距離下拉選單（近/中/遠/沒車四檔）與逼近開關
    （`_ThreatGroup`，兩側各一組，分別用 `HudColors.safe` / `HudColors.danger`
    作為色標區分）。
  - 前方三個方向各一個路況下拉選單（`_FrontField`：無／坑洞／障礙物／坑洞＋障礙物）。
  - 每次變更都會即時呼叫 `onChanged` 回傳新的 `SimulationValues`，
    由 `RideHudScreen` 接手更新畫面，無内部暫存的「送出」流程。

### theme（樣式）

- **`HudColors`**：集中定義的色彩常數，整體介面採近黑底白字的深色儀表風格
  （`main.dart` 使用 `Brightness.dark` 主題）：
  - `surface` / `panel` / `road` / `ink` 系列：底色、道路色與文字色階。
  - `gauge`：儀表指針綠。
  - `brand` / `brandDim`：僅用於浮動按鈕、模擬面板等互動元件的品牌色（M 藍）。
  - `safe` / `warn` / `danger`（各附一組 `Dim` 淡色版本）：語意色，
    對應威脅等級與坑洞警示。

## 核心資料流

```
使用者操作 SimulationSheet
        │  onChanged(SimulationValues)
        ▼
RideHudScreen._sim  (setState)
        │
        ├─► _threats: List<VehicleThreat>  ──► RoadView（後方弧形燈條閃爍、路面坑洞、前方橘色弧形燈條）
        └─► _sim.bikeSpeed                 ──► SpeedGauge（車速儀表）
```

所有威脅判斷邏輯（安全/注意/危險門檻、弧線層數、方位標籤）都
集中在 `VehicleThreat`，UI 層（`RoadView`、`RideHudScreen`）只負責讀取
衍生後的結果進行繪製，不重複業務邏輯。

## 平台與設定重點

- **地圖金鑰**：`google_maps_flutter` 需要在 Android/iOS 專案內設定
  API 金鑰（見 `LiveGoogleMap` 檔案頂部註解所指路徑），這些檔案通常
  不納入版控，需另外設定。
- **定位權限**：`geolocator` 需要在 `android/app/src/main/AndroidManifest.xml`
  與 `ios/Runner/Info.plist` 中宣告對應的定位權限描述文字。
- **強制直向**：版面為直向設計。`main.dart` 以 `SystemChrome.setPreferredOrientations` 鎖定 `portraitUp`；
  Android `AndroidManifest.xml` 的 MainActivity 設 `screenOrientation="portrait"`；iOS `Info.plist`
  的 `UISupportedInterfaceOrientations`（含 iPad）只保留 Portrait。
- **資源**：`assets/bike.png`、`assets/welcome.jpg` 已在 `pubspec.yaml` 的 `assets:` 區塊註冊
  （整個 `assets/` 目錄）。
- **IDE 並行執行**：`.idea/runConfigurations/main_dart.xml` 設定
  `singleton="false"`（Allow parallel run），在 IntelliJ 先對 Android 按播放、
  再切換裝置對 iPhone 按播放時，兩者會同時執行，不會互相停止。此檔在
  `.gitignore` 內，不隨版控，換機器需在 Run Configuration 勾選
  「Allow parallel run」。

## 測試

- `test/ble_radar_parse_test.dart`：驗證 `BleRadarService.parse()` 的 7 欄解析、9＝錯誤沿用舊值與錯誤格式處理。
- `test/widget_test.dart`：驗證歡迎畫面標題、無 MAC 直連按鈕、「使用模擬數據繼續」預設隱藏且長按「連線」後才出現，進入模擬 HUD 後顯示車速 `20 km/h`，並可由左下選單看到「斷線」與開啟「模擬控制」。

## 延伸開發建議

- 威脅來源目前有兩種：`SimulationSheet` 手動模擬，以及透過
  `BleRadarService` 接收 AMB82 板子送來的（目前仍是模擬的）BLE 數據，
  兩者皆以 `SimulationValues` 進入 `RideHudScreen`。若要改為更貼近真實
  感測器的模型，可把 `SimulationValues` 換成專屬的感測資料模型。
- `RoadView` 的透視參數（鏡頭距離、弧形半徑與厚度）集中在 `_Cam` 與 `_arcSegment`；
  後續若要換成真實坑洞／障礙物造型或更多威脅來源，可在此擴充。
