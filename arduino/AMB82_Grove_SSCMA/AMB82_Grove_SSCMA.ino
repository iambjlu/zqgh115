/*


Example guide:
https://www.amebaiot.com/en/amebapro2-amb82-mini-arduino-ble-uart-service/
*/


#include "BLEDevice.h"
#include "gap_le.h"
#include "gap_msg.h"


#define UART_SERVICE_UUID      "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"


#define STRING_BUF_SIZE 100


BLEService UartService(UART_SERVICE_UUID);
BLECharacteristic Rx(CHARACTERISTIC_UUID_RX);
BLECharacteristic Tx(CHARACTERISTIC_UUID_TX);
BLEAdvertData advdata;
BLEAdvertData scndata;
volatile bool notify = false;
volatile uint8_t notifyConnection = 0;


void readCB (BLECharacteristic* chr, uint8_t connID) {
  printf("Characteristic %s read by connection %d \n", chr->getUUID().str(), connID);
}


void writeCB (BLECharacteristic* chr, uint8_t connID) {
  printf("Characteristic %s write by connection %d :\n", chr->getUUID().str(), connID);
  if (chr->getDataLen() > 0) {
    Serial.print("Received string: ");
    Serial.print(chr->readString());
    Serial.println();
  }
}


void notifCB (BLECharacteristic* chr, uint8_t connID, uint16_t cccd) {
  notifyConnection = connID;
  if (cccd & GATT_CLIENT_CHAR_CONFIG_NOTIFY) {
    printf("Notifications enabled on Characteristic %s for connection %d \n", chr->getUUID().str(), connID);
    notify = true;
  } else {
    printf("Notifications disabled on Characteristic %s for connection %d \n", chr->getUUID().str(), connID);
    notify = false;
  }
}


void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("BLE_SIMULATED_7_FIELDS_1HZ_NO_GROVE");


  advdata.addFlags(GAP_ADTYPE_FLAGS_GENERAL | GAP_ADTYPE_FLAGS_BREDR_NOT_SUPPORTED);
  advdata.addCompleteName("AMB82-Radar");
  scndata.addCompleteServices(BLEUUID(UART_SERVICE_UUID));


  Rx.setWriteProperty(true);
  Rx.setWritePermissions(GATT_PERM_WRITE);
  Rx.setWriteCallback(writeCB);
  Rx.setBufferLen(STRING_BUF_SIZE);
  Tx.setReadProperty(true);
  Tx.setReadPermissions(GATT_PERM_READ);
  Tx.setReadCallback(readCB);
  Tx.setNotifyProperty(true);
  Tx.setCCCDCallback(notifCB);
  Tx.setBufferLen(STRING_BUF_SIZE);


  UartService.addCharacteristic(Rx);
  UartService.addCharacteristic(Tx);


  BLE.init();
  BLE.setDeviceName("AMB82-Radar");
  BLE.configAdvert()->setAdvData(advdata);
  BLE.configAdvert()->setScanRspData(scndata);
  BLE.configServer(1);
  BLE.addService(UartService);


  BLE.beginPeripheral();
  uint8_t a[6] = {0};
  BLE.getLocalAddr(a);
  char mac[18];
  snprintf(mac, sizeof(mac), "%02X:%02X:%02X:%02X:%02X:%02X", a[5], a[4], a[3], a[2], a[1], a[0]);
  Serial.print("BLE_MAC="); Serial.println(mac);
}


void sendSimulatedRadar() {
  static unsigned long tick = 0;
  const unsigned long t = tick++ % 12;
  const int left = t < 4 ? 1 : (t < 8 ? 2 : 3);
  const int right = 3 - (int)((t / 3) % 3);
  char line[32];
  snprintf(line, sizeof(line), "%d,%d,%d,%d,%d,%d,%d",
          left, right, left == 3 ? 1 : 0, right == 3 ? 1 : 0,
          t == 3 ? 1 : (t == 9 ? 2 : 0), (t == 6 || t == 7) ? 1 : 0, t == 10 ? 3 : 0);
  Tx.writeString(line);
  Tx.notify(notifyConnection);
  Serial.print("BLE_SEND "); Serial.println(line);
}


void loop() {
  static unsigned long lastSend = 0;
  if (!BLE.connected(0)) notify = false;
  if (notify && BLE.connected(notifyConnection) && millis() - lastSend >= 1000) {
    lastSend = millis();
    sendSimulatedRadar();
  }
  static unsigned long last = 0;
  if (millis() - last >= 2000) {
    last = millis();
    T_GAP_DEV_STATE state = {0};
    le_get_gap_param(GAP_PARAM_DEV_STATE, &state);
    Serial.print("MINIMAL adv="); Serial.print((int)state.gap_adv_state);
    Serial.print(" connected="); Serial.println(BLE.connected(0));
  }
  delay(10);
}
