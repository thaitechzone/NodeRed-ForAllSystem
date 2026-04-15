// ============================================================
//  ESP32 SmartFarm — MQTT Telemetry Simulator
//  สำหรับทดสอบ Node-RED Lab 1: MQTT → InfluxDB → Grafana
//
//  Flow:
//    ESP32 ──publish──► MQTT Broker ──subscribe──► Node-RED
//                                              ──► InfluxDB
//                                              ──► Grafana
//
//  Topics:
//    PUB  smartfarm/<DEVICE_ID>/telemetry  → sensor data (JSON)
//    PUB  smartfarm/<DEVICE_ID>/status     → online/offline
//    SUB  smartfarm/<DEVICE_ID>/command    → relay control
// ============================================================

#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include "config.h"

#if !SIMULATE_SENSORS
  #include <DHT.h>
  DHT dht(DHT_PIN, DHT_TYPE);
#endif

// ────────────────────────────────────────────────────────────
//  Global Objects
// ────────────────────────────────────────────────────────────
WiFiClient   wifiClient;
PubSubClient mqttClient(wifiClient);

// ────────────────────────────────────────────────────────────
//  State Variables
// ────────────────────────────────────────────────────────────
bool  relayState        = false;
float simTemperature    = 28.0f;
float simHumidity       = 65.0f;
float simSoilMoisture   = 45.0f;

unsigned long lastPublishTime  = 0;
unsigned long lastStatusTime   = 0;
unsigned long lastReconnectTime = 0;

// ────────────────────────────────────────────────────────────
//  Forward Declarations
// ────────────────────────────────────────────────────────────
void  connectWiFi();
bool  connectMQTT();
void  publishTelemetry();
void  publishStatus(const char* state);
void  mqttCallback(char* topic, byte* payload, unsigned int length);
float readTemperature();
float readHumidity();
float readSoilMoisture();
void  setRelay(bool state);
void  printBanner();

// ============================================================
//  setup()
// ============================================================
void setup() {
    Serial.begin(SERIAL_BAUD);
    delay(500);
    printBanner();

    // Relay pin
    pinMode(RELAY_PIN, OUTPUT);
    digitalWrite(RELAY_PIN, LOW);
    pinMode(LED_BUILTIN, OUTPUT);

    // Real sensor init
#if !SIMULATE_SENSORS
    dht.begin();
    DBGLN("[Sensor] DHT22 initialized on GPIO " + String(DHT_PIN));
    pinMode(SOIL_PIN, INPUT);
#endif

    // WiFi
    connectWiFi();

    // MQTT
    mqttClient.setServer(MQTT_HOST, MQTT_PORT);
    mqttClient.setCallback(mqttCallback);
    mqttClient.setKeepAlive(60);
    mqttClient.setBufferSize(512);

    connectMQTT();
}

// ============================================================
//  loop()
// ============================================================
void loop() {
    // ── WiFi Watchdog ────────────────────────────────────────
    if (WiFi.status() != WL_CONNECTED) {
        DBGLN("[WiFi] Disconnected — reconnecting...");
        connectWiFi();
    }

    // ── MQTT Watchdog ────────────────────────────────────────
    if (!mqttClient.connected()) {
        unsigned long now = millis();
        if (now - lastReconnectTime >= MQTT_RECONNECT_MS) {
            lastReconnectTime = now;
            DBGLN("[MQTT] Disconnected — reconnecting...");
            connectMQTT();
        }
    }

    mqttClient.loop();  // ต้องเรียกทุก loop เพื่อรับข้อมูล

    // ── Publish Telemetry ────────────────────────────────────
    unsigned long now = millis();

    if (now - lastPublishTime >= PUBLISH_INTERVAL_MS) {
        lastPublishTime = now;
        publishTelemetry();
    }

    // ── Publish Status (Heartbeat) ──────────────────────────
    if (now - lastStatusTime >= STATUS_INTERVAL_MS) {
        lastStatusTime = now;
        publishStatus("online");
    }

    // ── Simulate Sensor Drift (ค่าขยับทีละน้อยทุก loop) ────
#if SIMULATE_SENSORS
    simTemperature  += (random(-5, 6) * 0.1f);
    simHumidity     += (random(-3, 4) * 0.1f);
    simSoilMoisture += (random(-2, 3) * 0.5f);

    simTemperature  = constrain(simTemperature,  18.0f, 40.0f);
    simHumidity     = constrain(simHumidity,     30.0f, 95.0f);
    simSoilMoisture = constrain(simSoilMoisture, 10.0f, 90.0f);
#endif
}

// ============================================================
//  WiFi Connection
// ============================================================
void connectWiFi() {
    DBGF("\n[WiFi] Connecting to: %s\n", WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED) {
        if (millis() - start > WIFI_TIMEOUT_MS) {
            DBGLN("[WiFi] Timeout! Restarting...");
            ESP.restart();
        }
        delay(500);
        DBG(".");
    }

    DBGLN();
    DBGF("[WiFi] Connected!\n");
    DBGF("       SSID : %s\n", WiFi.SSID().c_str());
    DBGF("       IP   : %s\n", WiFi.localIP().toString().c_str());
    DBGF("       RSSI : %d dBm\n", WiFi.RSSI());
}

// ============================================================
//  MQTT Connection
// ============================================================
bool connectMQTT() {
    // สร้าง unique client ID = DEVICE_ID + MAC address 4 ตัวท้าย
    String mac = WiFi.macAddress();
    mac.replace(":", "");
    String clientId = String(DEVICE_ID) + "-" + mac.substring(8);

    DBGF("[MQTT] Connecting to %s:%d as %s\n",
         MQTT_HOST, MQTT_PORT, clientId.c_str());

    // Last Will Message — จะส่งอัตโนมัติเมื่อ disconnect ผิดปกติ
    String willTopic = String(TOPIC_STATUS);
    String willMsg   = "{\"device\":\"" DEVICE_ID "\",\"state\":\"offline\"}";

    bool connected;
    if (strlen(MQTT_USER) > 0) {
        connected = mqttClient.connect(
            clientId.c_str(),
            MQTT_USER, MQTT_PASS,
            willTopic.c_str(), 1, true, willMsg.c_str()
        );
    } else {
        connected = mqttClient.connect(
            clientId.c_str(),
            nullptr, nullptr,
            willTopic.c_str(), 1, true, willMsg.c_str()
        );
    }

    if (connected) {
        DBGLN("[MQTT] Connected!");

        // Subscribe คำสั่งควบคุม
        mqttClient.subscribe(TOPIC_COMMAND, 1);
        DBGF("[MQTT] Subscribed: %s\n", TOPIC_COMMAND);

        // ประกาศ online
        publishStatus("online");
        return true;
    } else {
        DBGF("[MQTT] Failed, rc=%d — will retry in %d ms\n",
             mqttClient.state(), MQTT_RECONNECT_MS);
        return false;
    }
}

// ============================================================
//  Publish Telemetry
// ============================================================
void publishTelemetry() {
    if (!mqttClient.connected()) return;

    float temp        = readTemperature();
    float humi        = readHumidity();
    float soil        = readSoilMoisture();
    int   rssi        = WiFi.RSSI();

    // ── สร้าง JSON ──────────────────────────────────────────
    // ใช้ JsonDocument แบบ static size เพื่อประหยัด heap
    JsonDocument doc;

    doc["device"]        = DEVICE_ID;
    doc["location"]      = LOCATION;
    doc["temperature"]   = round(temp * 10.0f) / 10.0f;   // 1 ทศนิยม
    doc["humidity"]      = round(humi * 10.0f) / 10.0f;
    doc["soil_moisture"] = (int)soil;
    doc["relay"]         = relayState ? 1 : 0;
    doc["rssi"]          = rssi;

    // ── Serialize ───────────────────────────────────────────
    char buf[256];
    size_t len = serializeJson(doc, buf, sizeof(buf));

    // ── Publish ─────────────────────────────────────────────
    bool ok = mqttClient.publish(TOPIC_TELEMETRY, buf, false);

    // ── LED blink เมื่อส่งสำเร็จ ────────────────────────────
    if (ok) {
        digitalWrite(LED_BUILTIN, HIGH);
        delay(50);
        digitalWrite(LED_BUILTIN, LOW);

        DBGF("[PUB] %s → %s (%d bytes)\n",
             TOPIC_TELEMETRY, buf, (int)len);
    } else {
        DBGLN("[PUB] FAILED — buffer full or disconnected");
    }
}

// ============================================================
//  Publish Status
// ============================================================
void publishStatus(const char* state) {
    if (!mqttClient.connected()) return;

    JsonDocument doc;
    doc["device"]   = DEVICE_ID;
    doc["state"]    = state;
    doc["ip"]       = WiFi.localIP().toString();
    doc["rssi"]     = WiFi.RSSI();
    doc["uptime_s"] = millis() / 1000;

    char buf[200];
    serializeJson(doc, buf, sizeof(buf));

    // retain=true ทำให้ broker เก็บ message ล่าสุดไว้
    mqttClient.publish(TOPIC_STATUS, buf, true);
    DBGF("[PUB] Status: %s\n", buf);
}

// ============================================================
//  MQTT Callback — รับคำสั่งจาก Node-RED / N8N
// ============================================================
void mqttCallback(char* topic, byte* payload, unsigned int length) {
    // แปลง payload เป็น null-terminated string
    char msg[256];
    length = min(length, (unsigned int)(sizeof(msg) - 1));
    memcpy(msg, payload, length);
    msg[length] = '\0';

    DBGF("[SUB] Topic: %s | Payload: %s\n", topic, msg);

    // ── Parse JSON Command ───────────────────────────────────
    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, msg);

    if (err) {
        DBGF("[SUB] JSON parse error: %s\n", err.c_str());
        return;
    }

    // ── คำสั่ง relay ────────────────────────────────────────
    // รับได้ทั้ง:
    //   {"relay": 1}       → เปิด
    //   {"relay": 0}       → ปิด
    //   {"relay": "on"}    → เปิด
    //   {"relay": "off"}   → ปิด
    if (doc["relay"].is<int>()) {
        setRelay(doc["relay"].as<int>() == 1);
    } else if (doc["relay"].is<const char*>()) {
        String r = doc["relay"].as<String>();
        r.toLowerCase();
        setRelay(r == "on" || r == "true" || r == "1");
    }

    // ── คำสั่ง restart ──────────────────────────────────────
    if (doc["restart"].as<bool>()) {
        DBGLN("[CMD] Restart command received!");
        publishStatus("restarting");
        delay(500);
        ESP.restart();
    }
}

// ============================================================
//  Sensor Readings
// ============================================================
float readTemperature() {
#if SIMULATE_SENSORS
    return simTemperature;
#else
    float t = dht.readTemperature();
    return isnan(t) ? simTemperature : t;
#endif
}

float readHumidity() {
#if SIMULATE_SENSORS
    return simHumidity;
#else
    float h = dht.readHumidity();
    return isnan(h) ? simHumidity : h;
#endif
}

float readSoilMoisture() {
#if SIMULATE_SENSORS
    return simSoilMoisture;
#else
    // ADC: 0 (เปียก/short) → 4095 (แห้ง/open)
    // แปลงเป็น % (0=แห้ง, 100=เปียก)
    int raw = analogRead(SOIL_PIN);
    float pct = map(raw, 4095, 0, 0, 100);
    return constrain(pct, 0.0f, 100.0f);
#endif
}

// ============================================================
//  Relay Control
// ============================================================
void setRelay(bool state) {
    relayState = state;
    digitalWrite(RELAY_PIN, state ? HIGH : LOW);
    digitalWrite(LED_BUILTIN, state ? HIGH : LOW);

    DBGF("[RELAY] %s\n", state ? "ON" : "OFF");

    // Feedback publish
    JsonDocument doc;
    doc["device"] = DEVICE_ID;
    doc["relay"]  = state ? 1 : 0;
    doc["source"] = "command";

    char buf[128];
    serializeJson(doc, buf, sizeof(buf));
    mqttClient.publish(TOPIC_TELEMETRY, buf, false);
}

// ============================================================
//  Banner
// ============================================================
void printBanner() {
    DBGLN("\n================================================");
    DBGLN("  ESP32 SmartFarm — MQTT Telemetry");
    DBGLN("================================================");
    DBGF("  Device   : %s\n",   DEVICE_ID);
    DBGF("  Broker   : %s:%d\n", MQTT_HOST, MQTT_PORT);
    DBGF("  Telemetry: %s\n",   TOPIC_TELEMETRY);
    DBGF("  Command  : %s\n",   TOPIC_COMMAND);
    DBGF("  Interval : %d ms\n", PUBLISH_INTERVAL_MS);
#if SIMULATE_SENSORS
    DBGLN("  Mode     : SIMULATE (no physical sensor needed)");
#else
    DBGLN("  Mode     : REAL SENSOR (DHT22 + Soil Moisture)");
    DBGF("  DHT Pin  : GPIO%d\n", DHT_PIN);
    DBGF("  Soil Pin : GPIO%d\n", SOIL_PIN);
#endif
    DBGLN("================================================\n");
}
