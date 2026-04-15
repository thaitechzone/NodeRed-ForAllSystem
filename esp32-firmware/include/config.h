#pragma once

// ============================================================
//  config.h — แก้ไขค่าตรงนี้ก่อน Flash ทุกครั้ง
// ============================================================

// ────────────────────────────────────────────────────────────
//  WiFi Credentials
// ────────────────────────────────────────────────────────────
#define WIFI_SSID       "Casa_Thalar"
#define WIFI_PASSWORD   "casa1234"

// ────────────────────────────────────────────────────────────
//  Device Identity
//  DEVICE_ID ใช้เป็น MQTT Client ID และ topic path
//  เช่น topic = smartfarm/ESP32-FARM-001/telemetry
// ────────────────────────────────────────────────────────────
#define DEVICE_ID       "ESP32-FARM-001"
#define LOCATION        "farm"

// ────────────────────────────────────────────────────────────
//  MQTT Broker — เลือก 1 ตัวเลือก (comment อีกตัว)
// ────────────────────────────────────────────────────────────

// ตัวเลือก A: HiveMQ Public Broker (ไม่ต้องตั้ง server เอง)
#define MQTT_HOST       "192.168.1.121"
#define MQTT_PORT       1883
#define MQTT_USER       ""          // ไม่ต้อง auth
#define MQTT_PASS       ""

// ตัวเลือก B: Local Mosquitto (Docker บน Windows)
// แก้ IP เป็น IP ของเครื่อง Windows ที่รัน Docker
// #define MQTT_HOST    "192.168.1.100"
// #define MQTT_PORT    1883
// #define MQTT_USER    ""
// #define MQTT_PASS    ""

// ────────────────────────────────────────────────────────────
//  MQTT Topics
// ────────────────────────────────────────────────────────────
#define TOPIC_TELEMETRY "smartfarm/" DEVICE_ID "/telemetry"
#define TOPIC_STATUS    "smartfarm/" DEVICE_ID "/status"
#define TOPIC_COMMAND   "smartfarm/" DEVICE_ID "/command"  // SUB

// ────────────────────────────────────────────────────────────
//  Sensor Mode
//  SIMULATE_SENSORS = 1  → ใช้ค่าสุ่ม (ไม่ต้องต่อ sensor จริง)
//  SIMULATE_SENSORS = 0  → ใช้ DHT22 + Soil Moisture จริง
// ────────────────────────────────────────────────────────────
#define SIMULATE_SENSORS  1

// Real Sensor Pins (ใช้เมื่อ SIMULATE_SENSORS = 0)
#define DHT_PIN           4     // GPIO4 — DHT22 Data
#define DHT_TYPE          DHT22
#define SOIL_PIN          34    // GPIO34 — ADC (Soil Moisture Analog)
#define RELAY_PIN         26    // GPIO26 — Relay Control Output

// ────────────────────────────────────────────────────────────
//  Timing
// ────────────────────────────────────────────────────────────
#define PUBLISH_INTERVAL_MS   5000    // ส่ง telemetry ทุก 5 วินาที
#define STATUS_INTERVAL_MS    30000   // ส่ง status ทุก 30 วินาที
#define WIFI_TIMEOUT_MS       15000   // timeout รอ WiFi
#define MQTT_RECONNECT_MS     5000    // รอก่อน reconnect

// ────────────────────────────────────────────────────────────
//  Built-in LED (ESP32 = GPIO2; not always defined by framework)
// ────────────────────────────────────────────────────────────
#ifndef LED_BUILTIN
  #define LED_BUILTIN 2
#endif

// ────────────────────────────────────────────────────────────
//  Serial Debug
// ────────────────────────────────────────────────────────────
#define SERIAL_BAUD     115200
#define DEBUG_ENABLED   1

#if DEBUG_ENABLED
  #define DBG(x)    Serial.print(x)
  #define DBGLN(x)  Serial.println(x)
  #define DBGF(...) Serial.printf(__VA_ARGS__)
#else
  #define DBG(x)
  #define DBGLN(x)
  #define DBGF(...)
#endif
