# ESP32 SmartFarm — MQTT Telemetry Firmware

> PlatformIO project สำหรับ Node-RED Lab 1  
> ส่งข้อมูล sensor ไปยัง MQTT Broker ทุก 5 วินาที

---

## โครงสร้างไฟล์

```
esp32-firmware/
  ├── platformio.ini          ← Project config + dependencies
  ├── include/
  │     └── config.h          ← ★ แก้ WiFi / MQTT / Pins ที่นี่
  ├── src/
  │     └── main.cpp          ← Main firmware
  ├── test/
  │     └── test_payload.py   ← Python simulator (ไม่ต้องใช้ ESP32)
  └── .gitignore
```

---

## ขั้นตอนที่ 1 — ติดตั้ง VS Code + PlatformIO

1. ติดตั้ง [VS Code](https://code.visualstudio.com/)
2. เปิด Extensions (`Ctrl+Shift+X`) → ค้นหา **PlatformIO IDE** → Install
3. รอ PlatformIO ติดตั้ง toolchain (ครั้งแรกใช้เวลา 5–10 นาที)

---

## ขั้นตอนที่ 2 — เปิด Project

```
File → Open Folder → เลือก d:\NodeRed\esp32-firmware
```

PlatformIO จะตรวจพบ `platformio.ini` อัตโนมัติ

---

## ขั้นตอนที่ 3 — แก้ไข config.h

เปิดไฟล์ `include/config.h` แล้วแก้:

```cpp
// WiFi
#define WIFI_SSID       "ชื่อ WiFi ของคุณ"
#define WIFI_PASSWORD   "รหัส WiFi ของคุณ"

// MQTT Broker — เลือก 1 ตัว
// ตัวเลือก A: HiveMQ Public (ไม่ต้องตั้งค่าอะไร)
#define MQTT_HOST   "broker.hivemq.com"

// ตัวเลือก B: Local Mosquitto บน Windows
// #define MQTT_HOST   "192.168.x.x"  ← IP เครื่อง Windows ที่รัน Docker
```

### หา IP Windows สำหรับ Mosquitto Local

```powershell
# PowerShell
ipconfig | findstr "IPv4"
```

---

## ขั้นตอนที่ 4 — Build & Upload

```
# Build เพื่อตรวจ error
Ctrl+Alt+B   หรือ คลิก ✓ ที่ Status Bar ด้านล่าง

# Upload ไปยัง ESP32 (ต่อ USB ก่อน)
Ctrl+Alt+U   หรือ คลิก → ที่ Status Bar

# เปิด Serial Monitor ดู log
Ctrl+Alt+S   หรือ คลิก 🔌 ที่ Status Bar
```

---

## MQTT Topics

| Topic | Direction | Payload |
|-------|-----------|---------|
| `smartfarm/ESP32-FARM-001/telemetry` | PUB (ทุก 5s) | JSON sensor data |
| `smartfarm/ESP32-FARM-001/status` | PUB (ทุก 30s + LWT) | `{"state":"online/offline"}` |
| `smartfarm/ESP32-FARM-001/command` | SUB | `{"relay":1}` หรือ `{"relay":"on"}` |

### ตัวอย่าง Payload — Telemetry

```json
{
    "device": "ESP32-FARM-001",
    "location": "farm",
    "temperature": 28.5,
    "humidity": 65.2,
    "soil_moisture": 42,
    "relay": 0,
    "rssi": -68
}
```

### ตัวอย่าง Command — ควบคุม Relay

```bash
# เปิด relay
mosquitto_pub -h broker.hivemq.com \
    -t "smartfarm/ESP32-FARM-001/command" \
    -m '{"relay":1}'

# ปิด relay
mosquitto_pub -h broker.hivemq.com \
    -t "smartfarm/ESP32-FARM-001/command" \
    -m '{"relay":0}'

# Restart ESP32
mosquitto_pub -h broker.hivemq.com \
    -t "smartfarm/ESP32-FARM-001/command" \
    -m '{"restart":true}'
```

---

## Pin Map

| GPIO | Role | หมายเหตุ |
|------|------|---------|
| 4    | DHT22 Data | ใช้เมื่อ SIMULATE_SENSORS=0 |
| 26   | Relay Output | Active HIGH |
| 34   | Soil Moisture ADC | ใช้เมื่อ SIMULATE_SENSORS=0 |
| 2    | LED_BUILTIN | กระพริบเมื่อส่งข้อมูล |

---

## ทดสอบโดยไม่ต้องใช้ ESP32 (Python Simulator)

```bash
# ติดตั้ง dependency
pip install paho-mqtt

# ส่งข้อมูลไปยัง HiveMQ Public
python test/test_payload.py

# ส่งไปยัง Local Mosquitto
python test/test_payload.py --broker 192.168.1.100

# จำลองหลาย device
python test/test_payload.py --device ESP32-FARM-002

# จำกัดจำนวน messages
python test/test_payload.py --count 30 --interval 2
```

---

## Modes

| ค่า `SIMULATE_SENSORS` | ผล |
|------------------------|-----|
| `1` (default) | ค่า sensor จำลองสุ่มแบบ random walk — ไม่ต้องต่อ hardware |
| `0` | อ่านจาก DHT22 จริง + Soil Moisture sensor จริง |

---

## Serial Output ตัวอย่าง

```
================================================
  ESP32 SmartFarm — MQTT Telemetry
================================================
  Device   : ESP32-FARM-001
  Broker   : broker.hivemq.com:1883
  Telemetry: smartfarm/ESP32-FARM-001/telemetry
  Command  : smartfarm/ESP32-FARM-001/command
  Interval : 5000 ms
  Mode     : SIMULATE (no physical sensor needed)
================================================

[WiFi] Connecting to: MyWiFi
..
[WiFi] Connected!
       SSID : MyWiFi
       IP   : 192.168.1.105
       RSSI : -52 dBm
[MQTT] Connecting to broker.hivemq.com:1883 as ESP32-FARM-001-aabbcc
[MQTT] Connected!
[MQTT] Subscribed: smartfarm/ESP32-FARM-001/command
[PUB] Status: {"device":"ESP32-FARM-001","state":"online","ip":"192.168.1.105","rssi":-52,"uptime_s":3}
[PUB] smartfarm/ESP32-FARM-001/telemetry → {"device":"ESP32-FARM-001","temperature":28.5,"humidity":65.2,...} (148 bytes)
```

---

## Troubleshooting

| อาการ | วิธีแก้ |
|-------|---------|
| Upload ไม่ได้ — `No device found` | กด **BOOT button** ค้างไว้ขณะ upload แล้วปล่อย |
| WiFi ไม่ต่อ — restart loop | ตรวจ SSID/Password ใน config.h |
| MQTT ไม่ต่อ rc=-2 | ตรวจ MQTT_HOST — ถ้าใช้ local ใส่ IP จริงของ host |
| ข้อมูลไม่ถึง Node-RED | ตรวจ topic ให้ตรงกัน ทั้ง ESP32 และ MQTT In node |
| Build error: `DHT.h not found` | PlatformIO ติดตั้ง lib ไม่ครบ — ลอง `pio pkg install` |
