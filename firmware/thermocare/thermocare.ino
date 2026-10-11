/* ThermoCare — Arduino UNO R4 WiFi, MLX90614, DS3231, LCD 0x27.
   Raw infrared surface temperature; no core-temperature conversion or diagnosis.
   RTC stores UTC. RAM history retains 120 one-minute samples until power loss.
*/
#include <Wire.h>
#include <WiFiS3.h>
#include <Adafruit_MLX90614.h>
#include <RTClib.h>
#include <LiquidCrystal_I2C.h>
#include <math.h>
#include <EEPROM.h>
#include "arduino_secrets.h"

Adafruit_MLX90614 mlx;
RTC_DS3231 rtc;
LiquidCrystal_I2C lcd(0x27, 16, 2);
WiFiServer server(80);
const uint16_t HISTORY_SIZE = 120;
struct Sample { float objectC; float ambientC; uint32_t epoch; uint32_t takenMs; uint32_t sequence; };
void printSample(WiFiClient &client, const Sample &sample);
Sample history[HISTORY_SIZE];
Sample latest = {};
uint16_t historyCount = 0;
uint16_t historyNext = 0;
uint32_t sequence = 0;
uint32_t lastRead = 0;
uint32_t lastRecord = 0;
uint32_t lastWiFiAttempt = 0;
uint32_t lastSensorRetry = 0;
uint32_t homeWaitStarted = 0;
uint32_t lastNetworkReport = 0;
bool accessPointMode = false;
bool sensorPresent = false;
bool sensorOK = false;
bool rtcPresent = false;
bool clockValid = false;
bool serving = false;
char deviceId[24] = "uno-r4";
char bootId[32] = "";

void lcdLine(uint8_t row, String text) {
  lcd.setCursor(0, row);
  while (text.length() < 16) text += ' ';
  lcd.print(text.substring(0, 16));
}

void readSensor() {
  if (!sensorPresent && millis() - lastSensorRetry >= 5000) {
    lastSensorRetry = millis();
    sensorPresent = mlx.begin();
  }
  if (!sensorPresent) { sensorOK = false; return; }
  float objectC = mlx.readObjectTempC();
  float ambientC = mlx.readAmbientTempC();
  sensorOK = isfinite(objectC) && isfinite(ambientC) && objectC >= -70 && objectC <= 380 && ambientC >= -40 && ambientC <= 125;
  if (!sensorOK) { sensorPresent = false; return; }
  latest = {objectC, ambientC, rtcPresent && clockValid ? rtc.now().unixtime() : 0, millis(), ++sequence};
  if (historyCount == 0 || millis() - lastRecord >= 60000) {
    history[historyNext] = latest;
    historyNext = (historyNext + 1) % HISTORY_SIZE;
    if (historyCount < HISTORY_SIZE) ++historyCount;
    lastRecord = millis();
  }
}

void updateLcd() {
  lcdLine(0, sensorOK ? "Surface:" + String(latest.objectC, 1) + " C" : "Sensor error");
  const int status = WiFi.status();
  if (status == WL_CONNECTED || (accessPointMode && (status == WL_AP_LISTENING || status == WL_AP_CONNECTED))) {
    // Alternate IP and UTC time. The IP fits in one 16-character LCD line.
    if (accessPointMode && (millis() / 5000) % 2 == 1) lcdLine(1, "WiFi: ThermoCare");
    else if ((millis() / 5000) % 2 == 0 || !clockValid) lcdLine(1, WiFi.localIP().toString());
    else {
      DateTime now = rtc.now();
      char timeText[17];
      snprintf(timeText, sizeof(timeText), "%02d:%02d:%02d UTC", now.hour(), now.minute(), now.second());
      lcdLine(1, timeText);
    }
  } else lcdLine(1, accessPointMode ? "WiFi AP retry" : "Joining WiFi...");
}

void startAccessPoint() {
  if (serving) { server.end(); serving = false; }
  WiFi.disconnect();
  accessPointMode = true;
  // Match the default UNO R4 AP subnet with an explicit, stable address.
  WiFi.config(IPAddress(192, 168, 4, 1));
  WiFi.beginAP(SECRET_AP_SSID, SECRET_AP_PASS);
  lastWiFiAttempt = millis();
  Serial.println("Presentation WiFi: " SECRET_AP_SSID);
  updateLcd();
}

void reportNetwork() {
  Serial.print("ThermoCare mode="); Serial.print(accessPointMode ? "presentation" : "home");
  Serial.print(" ip="); Serial.print(WiFi.localIP());
  Serial.print(" sensor="); Serial.print(sensorOK ? "OK" : "NOT_FOUND");
  Serial.print(" rtc="); Serial.println(rtcPresent ? (clockValid ? "SET" : "NEEDS_TIME_SYNC") : "NOT_FOUND");
  lastNetworkReport = millis();
}

void headers(WiFiClient &client, int status) {
  client.println(status == 200 ? "HTTP/1.1 200 OK" : status == 503 ? "HTTP/1.1 503 Service Unavailable" : "HTTP/1.1 400 Bad Request");
  client.println("Content-Type: application/json");
  client.println("Access-Control-Allow-Origin: *");
  client.println("Access-Control-Allow-Methods: GET, OPTIONS");
  client.println("Access-Control-Allow-Private-Network: true");
  client.println("Cache-Control: no-store");
  client.println("Connection: close");
  client.println();
}

void printSample(WiFiClient &client, const Sample &sample) {
  char epochText[16];
  if (sample.epoch) snprintf(epochText, sizeof(epochText), "%lu", (unsigned long)sample.epoch);
  else strcpy(epochText, "null");
  char json[300];
  snprintf(json, sizeof(json), "{\"device_id\":\"%s\",\"boot_id\":\"%s\",\"sequence\":%lu,\"sensor_ok\":true,\"object_c\":%.2f,\"ambient_c\":%.2f,\"epoch\":%s,\"age_ms\":%lu}",
    deviceId, bootId, (unsigned long)sample.sequence, sample.objectC, sample.ambientC, epochText, (unsigned long)(millis() - sample.takenMs));
  client.print(json);
}

void serveClient() {
  WiFiClient client = server.available();
  if (!client) return;
  // Bound request size and duration, avoiding an unbounded String or blocked sensor loop.
  char request[192];
  size_t length = 0;
  bool complete = false;
  const uint32_t started = millis();
  while (client.connected() && millis() - started < 500) {
    if (!client.available()) { delay(1); continue; }
    char ch = client.read();
    if (ch == '\n') { complete = true; break; }
    if (ch != '\r') {
      if (length >= sizeof(request) - 1) break;
      request[length++] = ch;
    }
  }
  request[length] = '\0';
  // Consume headers through the blank line before responding; closing with
  // unread request bytes can truncate the response on some TCP stacks.
  bool headersComplete = false;
  bool blankLine = true;
  uint16_t headerBytes = 0;
  while (complete && client.connected() && millis() - started < 500 && headerBytes < 4096) {
    if (!client.available()) { delay(1); continue; }
    char ch = client.read(); ++headerBytes;
    if (ch == '\n') {
      if (blankLine) { headersComplete = true; break; }
      blankLine = true;
    } else if (ch != '\r') blankLine = false;
  }
  String line(request);
  if (!complete || !headersComplete) { headers(client, 400); client.print("{\"error\":\"request_too_long_or_incomplete\"}"); }
  else if (line.startsWith("OPTIONS ")) { headers(client, 200); client.print("{}"); }
  else if (line.startsWith("GET /api/temperature ")) {
    headers(client, sensorOK ? 200 : 503);
    if (sensorOK) printSample(client, latest);
    else client.print("{\"sensor_ok\":false,\"error\":\"check_sensor_wiring\"}");
  } else if (line.startsWith("GET /api/history ")) {
    headers(client, 200); client.print('[');
    for (uint16_t i = 0; i < historyCount; ++i) {
      if (i) client.print(',');
      uint16_t index = (historyNext + HISTORY_SIZE - historyCount + i) % HISTORY_SIZE;
      printSample(client, history[index]);
    }
    client.print(']');
  } else if (line.startsWith("GET /api/time?epoch=")) {
    String raw = line.substring(20, line.indexOf(' ', 4));
    bool digits = raw.length() == 10;
    for (unsigned int i = 0; i < raw.length(); ++i) if (raw[i] < '0' || raw[i] > '9') digits = false;
    uint32_t epoch = strtoul(raw.c_str(), nullptr, 10);
    if (!rtcPresent || !digits || epoch < 1704067200UL || epoch > 4102444799UL) {
      headers(client, 400); client.print("{\"error\":\"rtc_unavailable_or_invalid_epoch\"}");
    } else {
      rtc.adjust(DateTime(epoch)); clockValid = true;
      // Backfill only samples taken before the clock was initialized in this boot.
      for (uint16_t i = 0; i < historyCount; ++i) {
        if (!history[i].epoch) history[i].epoch = epoch - (uint32_t)(millis() - history[i].takenMs) / 1000;
      }
      readSensor();
      headers(client, 200); client.print("{\"ok\":true}");
    }
  } else if (line.startsWith("GET /api/health ")) {
    headers(client, 200); client.print("{\"firmware\":\"1.1.0\",\"device_id\":\""); client.print(deviceId);
    client.print("\",\"network_mode\":\""); client.print(accessPointMode ? "presentation" : "home");
    client.print("\",\"rtc_ok\":"); client.print(rtcPresent && clockValid ? "true" : "false");
    client.print(",\"sensor_ok\":"); client.print(sensorOK ? "true" : "false"); client.print('}');
  } else { headers(client, 400); client.print("{\"error\":\"unknown_endpoint\"}"); }
  delay(2);
  client.stop();
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_BUILTIN, OUTPUT);
  // Deliberately do not wait for Serial: standalone startup must work without a PC.
  Wire.begin();
  Wire.setClock(100000);
  lcd.init(); lcd.backlight();
  lcdLine(0, "ThermoCare"); lcdLine(1, "Starting...");
  sensorPresent = mlx.begin();
  rtcPresent = rtc.begin();
  clockValid = rtcPresent && !rtc.lostPower() && rtc.now().unixtime() >= 1704067200UL;
  // An EEPROM boot counter gives stable deduplication across fast restarts,
  // including when the RTC has not yet been set.
  uint32_t bootCounter = 0;
  // UNO R4 has emulated EEPROM; initialized below through helper.
  bootCounter = nextBootCounter();
  snprintf(bootId, sizeof(bootId), "%lu", (unsigned long)bootCounter);
  readSensor();
  WiFi.setTimeout(1000);
  homeWaitStarted = millis();
  Serial.println("Joining configured home WiFi; presentation AP will start if unavailable.");
  WiFi.begin(SECRET_SSID, SECRET_PASS);
  lastWiFiAttempt = millis();
}

void loop() {
  uint32_t now = millis();
  if (now - lastRead >= 1000) { lastRead = now; readSensor(); updateLcd(); }
  const int status = WiFi.status();
  const bool ready = (!accessPointMode && status == WL_CONNECTED) ||
    (accessPointMode && (status == WL_AP_LISTENING || status == WL_AP_CONNECTED));
  digitalWrite(LED_BUILTIN, ready ? HIGH : LOW);
  if (ready) {
    if (!accessPointMode) homeWaitStarted = now;
    if (!serving) {
      byte mac[6]; WiFi.macAddress(mac);
      snprintf(deviceId, sizeof(deviceId), "uno-%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
      server.begin(); serving = true;
      reportNetwork();
      updateLcd();
    }
    serveClient();
    if (now - lastNetworkReport >= 15000) reportNetwork();
  } else {
    if (serving) { server.end(); serving = false; }
    if (accessPointMode) {
      if (now - lastWiFiAttempt >= 15000) startAccessPoint();
    } else if (now - homeWaitStarted >= 20000) {
      startAccessPoint();
    } else if (now - lastWiFiAttempt >= 10000) {
      lastWiFiAttempt = now; WiFi.begin(SECRET_SSID, SECRET_PASS);
    }
  }
}

uint32_t nextBootCounter() {
  const uint32_t magic = 0x54484D31;
  uint32_t storedMagic, counter;
  EEPROM.get(0, storedMagic); EEPROM.get(4, counter);
  if (storedMagic != magic || counter == 0xFFFFFFFFUL) counter = 0;
  ++counter;
  EEPROM.put(0, magic); EEPROM.put(4, counter);
  return counter;
}
