# AMB82 mini 藍牙雷達：安裝與使用筆記

## 已安裝的東西（macOS，已完成）

| 項目 | 版本 | 安裝方式 |
|---|---|---|
| arduino-cli | 1.5.1 | `brew install arduino-cli` |
| 板子套件 Realtek AmebaPro2 | **4.0.3** | `arduino-cli core install realtek:AmebaPro2@4.0.3` |
| 函式庫 Seeed Arduino SSCMA | 1.0.3 | `arduino-cli lib install "Seeed Arduino SSCMA@1.0.3"`（ArduinoJson 7.4.3 為其相依） |
| adb | 已有 | `/opt/homebrew/bin/adb` |

板子套件的索引網址必須用 Realtek 新倉庫（舊的 `ambiot/ambpro2_arduino` 下載會 404）：

```
arduino-cli config add board_manager.additional_urls \
  https://github.com/Ameba-AIoT/ameba-arduino-pro2/raw/main/Arduino_package/package_realtek_amebapro2_index.json
```

為什麼是 4.0.3：草稿需要 `SERIAL_ONE_UART_MODIFIABLE_BAUD_RATE`（Grove 用 921600 baud），4.0.3 內建該巨集。4.0.4／4.0.5 的下載檔目前已失效。

## 草稿位置與程式修改

- 草稿：`arduino/AMB82_Grove_SSCMA/AMB82_Grove_SSCMA.ino`（Arduino 規定資料夾名稱要等於草稿名稱，所以從 `arduino/` 移進子資料夾）
- 為了能編譯，草稿頂端加了：
  - `#undef printf/sprintf` 並補宣告：`Arduino.h` 把 `printf` 改名成 `dbg_printf`，會讓 ArduinoJson 的 `<ostream>` 編譯失敗。
  - `printHelp / connectGrove / inferOnce` 的前置宣告（arduino-cli 沒自動產生）。
- BLE：廣播名稱 `AMB82-Radar`，Notify characteristic `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`（service `6E400001-…`）。App 訂閱後，板子每秒送一筆**模擬**資料。

## 編譯與上傳（在 `arduino/` 目錄執行）

```
FQBN=realtek:AmebaPro2:Ameba_AMB82-MINI
HOOK="--build-property recipe.hooks.prebuild.2.pattern.macosx=true --build-property recipe.hooks.prebuild.3.pattern.macosx=true"

arduino-cli compile --fqbn $FQBN $HOOK AMB82_Grove_SSCMA
arduino-cli upload  --fqbn $FQBN -p /dev/cu.usbserial-10 AMB82_Grove_SSCMA
```

- `HOOK` 是必要的：Realtek 的 `ino_validation`／`nn_model_update` 工具為 Arduino IDE 設計，在 arduino-cli 底下會當掉（`IndexError`）。這兩步只是檢查與 NN 模型更新，本專案用不到，所以關掉。若改用 Arduino IDE 則不需要。
- 板子序列埠是 `/dev/cu.usbserial-10`（`usbmodem…` 是 Samsung 手機）；埠號可能變，用 `arduino-cli board list` 確認。
- 若上傳出現 `ping fail`／`Uart boot fail`：板子沒進**下載模式**。作法：按住板上 **UART_DOWNLOAD**（BOOT）鍵不放 → 按一下 **RESET** → 放開 UART_DOWNLOAD，再執行 upload。上傳完成後再按一次 RESET 啟動。

## 監看板子輸出

```
arduino-cli monitor -p /dev/cu.usbserial-10 -c baudrate=115200
```

開機後依序會印出 `BLE_STARTING`、`BLE_MAC=XX:XX:XX:XX:XX:XX`、`BLE_ADVERTISING name=AMB82-Radar`。序列埠輸入 `m` 可隨時再印一次 MAC（App 掃描時也會以 `BleRadarService.deviceMac`（目前 `00:E0:4C:0F:60:67`）比對裝置，換板子時請核對）。
手機連上後會出現 `BLE_NOTIFY ON`；手機連上後出現 `BLE_NOTIFY ON` 與每秒一行 `BLE_SEND 1,3,0,1,0,0,0`。

## App 接收格式（`App接收格式.xlsx`）

一行 7 欄、逗號分隔：`左後距離,右後距離,左後逼近,右後逼近,左前坑,正前坑,右前坑`

| 欄位 | 值 |
|---|---|
| 左／右後距離 | 1 遠、2 中、3 近 |
| 逼近、坑 | 1 有、0 沒有 |
| 任何欄位 | 9 = 錯誤（App 沿用該欄上一次的值） |

範例 `3,1,1,0,1,0,1`：左後近、右後遠、左後逼近、右後不逼近、左前有坑、正前無坑、右前有坑。
車速不在協定內，藍牙模式下顯示 0。

## 手機（Samsung SM-G973F，Android 12）

```
cd .. && flutter build apk --debug
adb -s RF8M312XDQN install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s RF8M312XDQN shell am start -n com.example.chc115/.MainActivity
```

App 的 BLE 權限（附近裝置、定位）首次連線時會跳出，請按允許；手機藍牙需開啟。

## App 操作流程

1. 開啟 App 先看到歡迎畫面。
2. 按「連線」：搜尋 `AMB82-Radar`（最多 10 秒），連上後進入 HUD，畫面由板子數據驅動。找不到會顯示錯誤，可再按一次。
3. 左下角選單（≡）→「斷線」：中斷藍牙並回到歡迎畫面。藍牙中途斷線（板子斷電、離開範圍）也會自動回到歡迎畫面。
4. 長按歡迎畫面的「連線」按鈕，底下會出現小字「使用模擬數據繼續」（重開 App 會再度隱藏）；按它：用原本的模擬數據進入 HUD，選單裡多一項「模擬控制」可手動調整數值。
