# ESP32 MQTT Tester — เอกสารการทดสอบ Node-RED Flow

> **อุปกรณ์:** ESP32-FARM-001-NATTAPHOL-PALM  
> **โปรเจกต์:** SmartFarm — ระบบควบคุม Relay ผ่าน MQTT  
> **ไฟล์ Flow:** `flows/smartfarm-esp32-control.json`  
> **วันที่สร้าง:** 2026-04-09  
> **สถานะ:** ทดสอบจริงแล้ว — SUB และ PUB ทำงานได้สมบูรณ์

---

## สารบัญ

1. [ภาพรวมระบบ](#1-ภาพรวมระบบ)
2. [การตั้งค่า MQTT Broker](#2-การตั้งค่า-mqtt-broker)
3. [โครงสร้าง Topic](#3-โครงสร้าง-topic)
4. [โครงสร้าง Flow ใน Node-RED](#4-โครงสร้าง-flow-ใน-node-red)
5. [รายละเอียด Nodes แต่ละตัว](#5-รายละเอียด-nodes-แต่ละตัว)
6. [รูปแบบข้อมูล JSON](#6-รูปแบบข้อมูล-json)
7. [วิธี Import Flow เข้า Node-RED](#7-วิธี-import-flow-เข้า-node-red)
8. [ขั้นตอนการทดสอบ](#8-ขั้นตอนการทดสอบ)
9. [การตรวจสอบผลลัพธ์](#9-การตรวจสอบผลลัพธ์)
10. [ตารางสรุปการทดสอบ](#10-ตารางสรุปการทดสอบ)
11. [การแก้ไขปัญหาเบื้องต้น](#11-การแก้ไขปัญหาเบื้องต้น)

---

## 1. ภาพรวมระบบ

```
┌─────────────────────────────────────────────────────────────┐
│                        Node-RED                             │
│                                                             │
│  [Inject Buttons]  ──►  [MQTT Out]  ──►  topic: /control   │
│                                                             │
│  [MQTT In Telemetry]  ──►  [Debug]  ◄──  topic: /telemetry │
│  [MQTT In Status]     ──►  [Debug]  ◄──  topic: /status    │
└───────────────────────────┬─────────────────────────────────┘
                            │  MQTT over TCP (port 1883)
                ┌───────────▼───────────┐
                │   broker.hivemq.com   │
                │   (Public Broker)     │
                └───────────┬───────────┘
                            │
                ┌───────────▼───────────┐
                │  ESP32-FARM-001       │
                │  NATTAPHOL-PALM       │
                │                       │
                │  relay1 → Pump        │
                │  relay2 → Fan         │
                │  relay3 → Heater      │
                └───────────────────────┘
```

**การทำงานโดยย่อ:**
- Node-RED ทำหน้าที่เป็น **MQTT Client** เชื่อมต่อกับ Public Broker
- **Publish** คำสั่งควบคุม relay ไปยัง ESP32 ผ่าน topic `/control`
- **Subscribe** รับข้อมูลเซ็นเซอร์จาก ESP32 ผ่าน topic `/telemetry` และ `/status`

---

## 2. การตั้งค่า MQTT Broker

| พารามิเตอร์ | ค่า |
|------------|-----|
| **Broker Host** | `broker.hivemq.com` |
| **Port** | `1883` (TCP ไม่เข้ารหัส) |
| **Client ID** | `nodered-smartfarm-001` |
| **Protocol Version** | MQTT v3.1.1 |
| **Keep Alive** | 60 วินาที |
| **Clean Session** | `true` (ไม่เก็บ session เก่า) |
| **TLS/SSL** | ปิด (ใช้ port 1883) |
| **Username / Password** | ไม่ต้องใช้ (Public Broker) |

> **หมายเหตุ:** `broker.hivemq.com` เป็น Public MQTT Broker ใช้งานได้ฟรี ไม่ต้องสมัคร  
> ข้อมูลทุกอย่างเป็น **สาธารณะ** — ห้ามส่งข้อมูลที่ sensitive ผ่าน broker นี้

---

## 3. โครงสร้าง Topic

Topic ทั้งหมดอยู่ใต้ namespace: `smartfarm/ESP32-FARM-001-NATTAPHOL-PALM/`

### 3.1 Subscribe Topics (Node-RED รับข้อมูล)

| Topic | ทิศทาง | คำอธิบาย |
|-------|--------|-----------|
| `smartfarm/ESP32-FARM-001-NATTAPHOL-PALM/telemetry` | ESP32 → Node-RED | ข้อมูลเซ็นเซอร์ เช่น อุณหภูมิ ความชื้น |
| `smartfarm/ESP32-FARM-001-NATTAPHOL-PALM/status` | ESP32 → Node-RED | สถานะอุปกรณ์ เช่น online/offline, สถานะ relay |

### 3.2 Publish Topics (Node-RED ส่งคำสั่ง)

| Topic | ทิศทาง | คำอธิบาย |
|-------|--------|-----------|
| `smartfarm/ESP32-FARM-001-NATTAPHOL-PALM/control` | Node-RED → ESP32 | คำสั่งควบคุม relay |

### 3.3 ความหมายของ Topic Structure

```
smartfarm / ESP32-FARM-001-NATTAPHOL-PALM / telemetry
    │               │                           │
    │               │                           └── ประเภทข้อมูล
    │               └── Device ID (ชื่อเฉพาะของ ESP32)
    └── Namespace โปรเจกต์
```

---

## 4. โครงสร้าง Flow ใน Node-RED

Flow ถูกจัดแบ่งเป็น **2 ส่วนหลัก** บน Tab ชื่อ `SmartFarm ESP32`:

```
Tab: SmartFarm ESP32
│
├── ส่วนที่ 1: SUBSCRIBE (รับข้อมูลจาก ESP32)
│   ├── [SUB: Telemetry]  ──►  [Debug: Telemetry Data]
│   └── [SUB: Status]     ──►  [Debug: Device Status]
│
└── ส่วนที่ 2: PUBLISH (ส่งคำสั่งไปยัง ESP32)
    ├── [Inject: ALL Relays ON]    ─┐
    ├── [Inject: ALL Relays OFF]    ├──►  [PUB: Control]
    ├── [Inject: Pump ON only]      │
    ├── [Inject: Fan ON only]       │
    └── [Inject: Heater ON only]   ─┘
```

**จำนวน Node ทั้งหมด:** 12 nodes (รวม comment nodes)

---

## 5. รายละเอียด Nodes แต่ละตัว

### 5.1 MQTT Broker Configuration Node

```
Node ID   : broker-hivemq
Node Type : mqtt-broker
```

Node นี้เป็น **config node** (ไม่แสดงบน canvas) ใช้ร่วมกันโดย MQTT In/Out ทุกตัว

| ค่าสำคัญ | รายละเอียด |
|----------|-----------|
| `autoConnect: true` | เชื่อมต่ออัตโนมัติเมื่อ deploy |
| `cleansession: true` | ล้าง session เก่าทุกครั้งที่ต่อใหม่ |
| `keepalive: 60` | ส่ง PING ทุก 60 วินาทีเพื่อรักษา connection |

---

### 5.2 MQTT In — SUB: Telemetry

```
Node ID   : mqtt-in-telemetry
Node Type : mqtt in
Topic     : smartfarm/ESP32-FARM-001-NATTAPHOL-PALM/telemetry
QoS       : 1
Datatype  : json (auto-parse)
```

- รับข้อมูล telemetry จาก ESP32
- **QoS 1** = มีการ acknowledge รับรองว่าข้อความถึงอย่างน้อยหนึ่งครั้ง
- `datatype: json` → Node-RED จะ parse JSON อัตโนมัติ ไม่ต้องใช้ JSON node เพิ่ม
- Output: `msg.payload` จะเป็น JavaScript object พร้อมใช้งาน

---

### 5.3 MQTT In — SUB: Status

```
Node ID   : mqtt-in-status
Node Type : mqtt in
Topic     : smartfarm/ESP32-FARM-001-NATTAPHOL-PALM/status
QoS       : 1
Datatype  : json (auto-parse)
```

- รับข้อมูลสถานะอุปกรณ์จาก ESP32
- การตั้งค่าเหมือน Telemetry node ทุกประการ แต่คนละ topic

---

### 5.4 Debug Nodes (Telemetry Data / Device Status)

```
Node Type    : debug
complete     : payload
tosidebar    : true   (แสดงใน Debug panel ด้านขวา)
tostatus     : true   (แสดงค่าล่าสุดใต้ node บน canvas)
```

- **tosidebar:** ดูข้อมูลแบบ real-time ใน Debug panel (แท็บแมลงสาบ)
- **tostatus:** เห็นค่าล่าสุดได้ทันทีบน flow canvas โดยไม่ต้องเปิด panel

---

### 5.5 Inject Nodes (ปุ่มทดสอบ)

```
Node Type    : inject
payloadType  : json
repeat       : (ว่าง — กดเองทีละครั้ง)
once         : false
```

มี 5 ปุ่ม แต่ละปุ่มส่ง JSON ต่างกัน:

| ชื่อปุ่ม | relay1_pump | relay2_fan | relay3_heater |
|---------|-------------|------------|---------------|
| ALL Relays ON | `true` | `true` | `true` |
| ALL Relays OFF | `false` | `false` | `false` |
| Pump ON only | `true` | `false` | `false` |
| Fan ON only | `false` | `true` | `false` |
| Heater ON only | `false` | `false` | `true` |

---

### 5.6 MQTT Out — PUB: Control

```
Node ID   : mqtt-out-control
Node Type : mqtt out
Topic     : smartfarm/ESP32-FARM-001-NATTAPHOL-PALM/control
QoS       : 1
Retain    : false
```

- รับ `msg.payload` จาก Inject node แล้วส่งออกเป็น MQTT message
- **Retain: false** = Broker ไม่เก็บข้อความค้างไว้ ESP32 จะได้รับเฉพาะเมื่อ online อยู่
- **QoS 1** = มั่นใจว่าข้อความถึง Broker อย่างน้อยหนึ่งครั้ง

---

## 6. รูปแบบข้อมูล JSON

### 6.1 Publish — คำสั่งควบคุม Relay (Node-RED → ESP32)

**ควบคุมทุก relay พร้อมกัน:**
```json
{
  "command": "relay_control",
  "relays": {
    "relay1_pump": true,
    "relay2_fan": true,
    "relay3_heater": true
  }
}
```

**ปิดทุก relay:**
```json
{
  "command": "relay_control",
  "relays": {
    "relay1_pump": false,
    "relay2_fan": false,
    "relay3_heater": false
  }
}
```

**ฟิลด์อธิบาย:**

| ฟิลด์ | ชนิด | คำอธิบาย |
|-------|------|----------|
| `command` | string | ประเภทคำสั่ง — ปัจจุบันใช้ `"relay_control"` |
| `relays.relay1_pump` | boolean | `true` = เปิดปั๊มน้ำ, `false` = ปิด |
| `relays.relay2_fan` | boolean | `true` = เปิดพัดลม, `false` = ปิด |
| `relays.relay3_heater` | boolean | `true` = เปิดฮีตเตอร์, `false` = ปิด |

---

### 6.2 Subscribe — ข้อมูล Telemetry (ESP32 → Node-RED)

**Topic:** `smartfarm/ESP32-FARM-001-NATTAPHOL-PALM/telemetry`

**ตัวอย่างข้อมูลจริงที่รับได้:**
```json
{
  "board_id": "ESP32-FARM-001-NATTAPHOL-PALM",
  "timestamp": 99648422,
  "rssi": -56,
  "sensors": {
    "water_temp": 26.4,
    "air_temp": 30.1,
    "air_humidity": 70.8,
    "water_overflow": false,
    "water_dry": false
  },
  "relays": {
    "relay1_pump": true,
    "relay2_fan": true,
    "relay3_heater": true
  }
}
```

**คำอธิบาย Fields:**

| Field | ชนิด | หน่วย | คำอธิบาย |
|-------|------|-------|----------|
| `board_id` | string | — | Device ID ของ ESP32 |
| `timestamp` | number | ms | เวลาที่ส่ง (millis ตั้งแต่บูต) |
| `rssi` | number | dBm | ความแรงสัญญาณ WiFi (ยิ่งใกล้ 0 ยิ่งดี) |
| `sensors.water_temp` | float | °C | อุณหภูมิน้ำ |
| `sensors.air_temp` | float | °C | อุณหภูมิอากาศ |
| `sensors.air_humidity` | float | % | ความชื้นอากาศ |
| `sensors.water_overflow` | boolean | — | `true` = น้ำล้น |
| `sensors.water_dry` | boolean | — | `true` = น้ำแห้ง/หมด |
| `relays.relay1_pump` | boolean | — | สถานะปั๊มน้ำปัจจุบัน |
| `relays.relay2_fan` | boolean | — | สถานะพัดลมปัจจุบัน |
| `relays.relay3_heater` | boolean | — | สถานะฮีตเตอร์ปัจจุบัน |

> **หมายเหตุ:** `timestamp` เป็นค่า `millis()` ของ ESP32 (นับตั้งแต่บูต) ไม่ใช่ Unix timestamp  
> ตัวอย่าง: `99648422 ms` ≈ บูตมาแล้ว ~27.7 ชั่วโมง

---

### 6.3 Subscribe — ข้อมูล Status (ESP32 → Node-RED)

**Topic:** `smartfarm/ESP32-FARM-001-NATTAPHOL-PALM/status`

**ตัวอย่างข้อมูลจริงที่รับได้:**
```json
{
  "board_id": "ESP32-FARM-001-NATTAPHOL-PALM",
  "status": "online",
  "ip": "192.168.1.7",
  "firmware": "1.0.0",
  "uptime": 99739,
  "timestamp": 99739959
}
```

**คำอธิบาย Fields:**

| Field | ชนิด | คำอธิบาย |
|-------|------|----------|
| `board_id` | string | Device ID ของ ESP32 |
| `status` | string | สถานะ: `"online"` / `"offline"` |
| `ip` | string | IP address ของ ESP32 บน LAN |
| `firmware` | string | เวอร์ชัน firmware ที่รันอยู่ |
| `uptime` | number | เวลาที่รันมาแล้ว (วินาที นับตั้งแต่บูต) |
| `timestamp` | number | เวลาที่ส่ง (millis ตั้งแต่บูต) |

> **หมายเหตุ:** `uptime: 99739` วินาที ≈ 27.7 ชั่วโมงหลังบูต  
> `ip: "192.168.1.7"` สามารถใช้ OTA update หรือ web interface ได้หากมีในอนาคต

---

## 7. วิธี Import Flow เข้า Node-RED

### ขั้นตอน

1. เปิด Node-RED ในเบราว์เซอร์ (โดยทั่วไป `http://localhost:1880`)

2. คลิกเมนู **☰** (มุมบนขวา) → เลือก **Import**

3. ในหน้าต่าง Import ให้คลิก **"select a file to import"**

4. เลือกไฟล์: `flows/smartfarm-esp32-control.json`

5. เลือกตำแหน่ง: **"new flow"** (แนะนำ) หรือ **"current flow"**

6. คลิก **Import**

7. Flow จะปรากฏบน canvas → คลิก **Deploy** (ปุ่มแดงมุมบนขวา)

> **ตรวจสอบ:** หลัง Deploy จะเห็นสถานะ **"connected"** ใต้ MQTT nodes หากเชื่อมต่อ Broker สำเร็จ

---

## 8. ขั้นตอนการทดสอบ

### 8.1 ทดสอบการเชื่อมต่อ Broker

1. หลัง Deploy ตรวจดูใต้ node `SUB: Telemetry` และ `SUB: Status`
2. ต้องเห็นข้อความ **"connected"** (สีเขียว)
3. หากเห็น **"disconnected"** หรือ **"error"** ให้ตรวจสอบ [การแก้ไขปัญหา](#11-การแก้ไขปัญหาเบื้องต้น)

---

### 8.2 ทดสอบ Subscribe (รับข้อมูลจาก ESP32)

1. เปิด **Debug panel** (คลิกไอคอนแมลงสาบ แท็บด้านขวา)
2. รอให้ ESP32 ส่งข้อมูลมา หรือใช้ MQTT client อื่น publish ข้อมูลทดสอบ
3. ตรวจว่าข้อมูลปรากฏใน Debug panel

**ทดสอบด้วย MQTT client ภายนอก (เช่น MQTTX):**
```
Broker  : broker.hivemq.com:1883
Publish : smartfarm/ESP32-FARM-001-NATTAPHOL-PALM/telemetry
Payload : {"board_id":"ESP32-FARM-001-NATTAPHOL-PALM","timestamp":99648422,"rssi":-56,"sensors":{"water_temp":26.4,"air_temp":30.1,"air_humidity":70.8,"water_overflow":false,"water_dry":false},"relays":{"relay1_pump":true,"relay2_fan":true,"relay3_heater":true}}
```

---

### 8.3 ทดสอบ Publish (ส่งคำสั่งไปยัง ESP32)

ทดสอบตามลำดับดังนี้:

**ขั้นที่ 1 — เปิด ALL Relays**
- คลิกปุ่ม **[ALL Relays ON]**
- ตรวจสอบว่า ESP32 ตอบสนอง (ไฟ LED relay ติด)

**ขั้นที่ 2 — ทดสอบทีละ relay**
- คลิก **[Pump ON only]** → relay1 ต้องทำงาน, relay2 และ relay3 ต้องหยุด
- คลิก **[Fan ON only]** → relay2 ต้องทำงาน, relay1 และ relay3 ต้องหยุด
- คลิก **[Heater ON only]** → relay3 ต้องทำงาน, relay1 และ relay2 ต้องหยุด

**ขั้นที่ 3 — ปิดทุก relay**
- คลิก **[ALL Relays OFF]**
- ตรวจสอบว่า relay ทุกตัวหยุดทำงาน

---

### 8.4 ทดสอบ Round-Trip (ครบวงจร)

ทดสอบว่า ESP32 รับคำสั่งแล้วส่ง status กลับมา:

1. คลิก **[ALL Relays ON]**
2. รอสักครู่
3. ตรวจดู Debug panel ที่ **Device Status** ว่า ESP32 ส่ง status กลับมาหรือไม่
4. ค่า `relay1_pump`, `relay2_fan`, `relay3_heater` ใน status ควรเป็น `true` ทั้งหมด

---

## 9. การตรวจสอบผลลัพธ์

### 9.1 Debug Panel

เปิดที่แท็บ **Debug** (ไอคอนแมลงสาบ) ด้านขวามือ

**Telemetry:**
```
▼ msg.payload (Object)
  ├── board_id: "ESP32-FARM-001-NATTAPHOL-PALM"
  ├── timestamp: 99648422
  ├── rssi: -56
  ├── sensors (Object)
  │   ├── water_temp: 26.4
  │   ├── air_temp: 30.1
  │   ├── air_humidity: 70.8
  │   ├── water_overflow: false
  │   └── water_dry: false
  └── relays (Object)
      ├── relay1_pump: true
      ├── relay2_fan: true
      └── relay3_heater: true
```

**Status:**
```
▼ msg.payload (Object)
  ├── board_id: "ESP32-FARM-001-NATTAPHOL-PALM"
  ├── status: "online"
  ├── ip: "192.168.1.7"
  ├── firmware: "1.0.0"
  ├── uptime: 99739
  └── timestamp: 99739959
```

- กรองดูเฉพาะ node ที่ต้องการโดยคลิกที่ชื่อ node ด้านบน

---

### 9.2 Node Status (บน Canvas)

แต่ละ node จะแสดงสถานะใต้ชื่อ:

| สถานะ | ความหมาย |
|-------|---------|
| `connected` (สีเขียว) | เชื่อมต่อ Broker สำเร็จ |
| `disconnected` (สีแดง) | ขาดการเชื่อมต่อ |
| `connecting` (สีเหลือง) | กำลังพยายามเชื่อมต่อ |
| ค่าข้อมูลล่าสุด | Debug node แสดง payload ล่าสุดที่รับได้ |

---

### 9.3 ตรวจสอบด้วย MQTT Client ภายนอก

ใช้ **MQTTX** หรือ **MQTT Explorer** เพื่อยืนยัน:

```
Subscribe : smartfarm/ESP32-FARM-001-NATTAPHOL-PALM/control
```

กด Inject button ใน Node-RED → ต้องเห็นข้อความใน MQTT client ภายนอก

---

## 10. ตารางสรุปการทดสอบ

| # | กรณีทดสอบ | วิธีทดสอบ | ผลที่คาดหวัง | ผ่าน/ไม่ผ่าน |
|---|-----------|-----------|--------------|-------------|
| 1 | เชื่อมต่อ Broker | Deploy flow | สถานะ "connected" | ✅ |
| 2 | Subscribe Telemetry | รับจาก ESP32 จริง | ข้อมูล sensors + relays ปรากฏใน Debug panel | ✅ |
| 3 | Subscribe Status | รับจาก ESP32 จริง | board_id, status, ip, firmware ปรากฏใน Debug panel | ✅ |
| 4 | ALL Relays ON | กดปุ่ม Inject | relay ทั้ง 3 ทำงาน | ✅ |
| 5 | ALL Relays OFF | กดปุ่ม Inject | relay ทั้ง 3 หยุด | ✅ |
| 6 | Pump ON only | กดปุ่ม Inject | เฉพาะ relay1 ทำงาน | ✅ |
| 7 | Fan ON only | กดปุ่ม Inject | เฉพาะ relay2 ทำงาน | ✅ |
| 8 | Heater ON only | กดปุ่ม Inject | เฉพาะ relay3 ทำงาน | ✅ |
| 9 | Round-trip test | ส่งคำสั่ง → รอ status | relays ใน telemetry สะท้อนคำสั่งที่ส่งไป | ✅ |

---

## 11. การแก้ไขปัญหาเบื้องต้น

### ปัญหา: สถานะ "disconnected" หรือ "connect failed"

**สาเหตุที่เป็นไปได้:**
- อินเทอร์เน็ตขัดข้อง
- Broker ชั่วคราวล่ม (Public broker อาจมี downtime)
- Client ID ซ้ำกับ client อื่น (เกิดได้บน Public broker)

**วิธีแก้:**
1. ตรวจสอบการเชื่อมต่ออินเทอร์เน็ต
2. เปลี่ยน Client ID ในการตั้งค่า Broker เช่น `nodered-smartfarm-002`
3. รอสักครู่แล้ว Deploy ใหม่

---

### ปัญหา: ไม่ได้รับข้อมูลจาก ESP32

**สาเหตุที่เป็นไปได้:**
- ESP32 ยังไม่ได้เชื่อมต่อ Broker
- Topic ใน ESP32 firmware พิมพ์ผิด (case-sensitive)
- ESP32 ยังไม่ได้รับ MQTT connection

**วิธีแก้:**
1. ตรวจสอบ Serial Monitor ของ ESP32
2. ตรวจสอบ topic ใน firmware ให้ตรงทุกตัวอักษร รวมถึงตัวพิมพ์ใหญ่-เล็ก
3. ใช้ MQTT Explorer Subscribe topic เดียวกันเพื่อยืนยันว่า ESP32 ส่งข้อมูลหรือไม่

---

### ปัญหา: ESP32 ไม่รับคำสั่ง relay

**สาเหตุที่เป็นไปได้:**
- ESP32 ไม่ได้ Subscribe topic `/control`
- โครงสร้าง JSON ไม่ตรงกับที่ firmware คาดหวัง

**วิธีแก้:**
1. ตรวจสอบ firmware ว่า subscribe topic `/control` หรือไม่
2. ตรวจสอบ JSON parsing ใน firmware ให้ตรงกับ field `command` และ `relays`
3. ใช้ MQTT Explorer ส่งข้อความทดสอบโดยตรงเพื่อ bypass Node-RED

---

### ปัญหา: Import Flow แล้วไม่เห็น Tab

**วิธีแก้:**
1. ตรวจสอบว่า Import เลือก **"new flow"** ไม่ใช่ merge กับ flow ปัจจุบัน
2. ดูที่แท็บด้านบนสุดของ canvas — ควรมีแท็บใหม่ชื่อ **"SmartFarm ESP32"**
3. หาก MQTT broker node แสดง error ให้ดับเบิลคลิกแก้ไขค่า broker

---

## ไฟล์ที่เกี่ยวข้อง

| ไฟล์ | คำอธิบาย |
|------|---------|
| `flows/smartfarm-esp32-control.json` | Node-RED flow สำหรับ import |
| `ESP32MQTTTester.md` | เอกสารนี้ |

---

## ข้อมูลอุปกรณ์จริง (จากการทดสอบ 2026-04-09)

| รายการ | ค่า |
|--------|-----|
| Board ID | `ESP32-FARM-001-NATTAPHOL-PALM` |
| IP Address | `192.168.1.7` |
| Firmware | `1.0.0` |
| อุณหภูมิน้ำ | 26.4 °C |
| อุณหภูมิอากาศ | 30.1 °C |
| ความชื้นอากาศ | 70.8 % |
| สัญญาณ WiFi (RSSI) | -56 dBm |

---

*เอกสารนี้สร้างสำหรับโปรเจกต์ SmartFarm ESP32 — Node-RED MQTT Testing*  
*อัปเดตล่าสุด: 2026-04-09 — เพิ่มข้อมูล JSON จริงจากการทดสอบ*
