# N8N Automation — SmartFarm ESP32

> **โปรเจกต์:** SmartFarm — Node-RED → N8N via Webhook  
> **N8N:** Docker Desktop (localhost:5678)  
> **Tunnel:** Cloudflare Tunnel (cloudflared ใน Docker)  
> **วันที่สร้าง:** 2026-04-10  
> **ไฟล์ที่เกี่ยวข้อง:**  
> - `flows/smartfarm-nodered-n8n.json` — Node-RED flow (อัปเดต + HTTP forward)  
> - `flows/n8n-smartfarm-workflow.json` — N8N workflow สำหรับ import

---

## สารบัญ

1. [ภาพรวมระบบ](#1-ภาพรวมระบบ)
2. [สิ่งที่ต้องมีก่อนเริ่ม](#2-สิ่งที่ต้องมีก่อนเริ่ม)
3. [ขั้นตอนที่ 1 — ตรวจสอบ Ngrok URL](#3-ขั้นตอนที่-1--ตรวจสอบ-ngrok-url)
4. [ขั้นตอนที่ 2 — Import N8N Workflow](#4-ขั้นตอนที่-2--import-n8n-workflow)
5. [ขั้นตอนที่ 3 — อัปเดต Node-RED Flow](#5-ขั้นตอนที่-3--อัปเดต-node-red-flow)
6. [โครงสร้าง N8N Workflow](#6-โครงสร้าง-n8n-workflow)
7. [รายละเอียด Nodes ใน N8N](#7-รายละเอียด-nodes-ใน-n8n)
8. [Webhook Endpoints](#8-webhook-endpoints)
9. [Logic การตรวจสอบ Alert](#9-logic-การตรวจสอบ-alert)
10. [การเพิ่ม Action ต่อจาก Alert Nodes](#10-การเพิ่ม-action-ต่อจาก-alert-nodes)
11. [การทดสอบ End-to-End](#11-การทดสอบ-end-to-end)
12. [การแก้ไขปัญหาเบื้องต้น](#12-การแก้ไขปัญหาเบื้องต้น)

---

## 1. ภาพรวมระบบ

```
ESP32                Node-RED              N8N (Docker)         Actions
  │                     │                      │                   │
  │──MQTT Telemetry──►  │                      │                   │
  │                     │──HTTP POST──────────►│                   │
  │                     │  /webhook/           │──IF water_overflow►│ Alert
  │                     │  smartfarm-telemetry │──IF air_temp>35°C─►│ Alert
  │                     │                      │──Respond 200 OK   │
  │                     │                      │                   │
  │──MQTT Status──────► │                      │                   │
  │                     │──HTTP POST──────────►│                   │
  │                     │  /webhook/           │──IF offline───────►│ Alert
  │                     │  smartfarm-status    │──Respond 200 OK   │
  │                     │                      │                   │
```

**หลักการทำงาน:**
1. ESP32 ส่งข้อมูลผ่าน MQTT → Node-RED รับ
2. Node-RED forward ข้อมูลทันทีผ่าน **HTTP POST** ไปยัง N8N Webhook (Ngrok URL)
3. N8N ประมวลผล — แยก fields, เช็ค conditions, trigger alerts
4. Alert nodes พร้อมต่อ action เช่น Email, Line, Slack, Discord ฯลฯ

---

## 2. สิ่งที่ต้องมีก่อนเริ่ม

| รายการ | สถานะ |
|--------|-------|
| Node-RED รันอยู่ใน Docker | ✅ |
| N8N รันอยู่ใน Docker Desktop | ✅ |
| Cloudflare Tunnel (cloudflared) รันใน Docker | ✅ |
| ESP32 ส่ง MQTT ทำงานได้ | ✅ |

**ตรวจสอบ services ทั้งหมด:**
```bash
docker compose ps
```
ควรเห็น `cloudflared` สถานะ `running` พร้อมกับ n8n และ nodered

---

## 3. ขั้นตอนที่ 1 — ตรวจสอบ Cloudflare Tunnel URL

### 3.1 ตรวจสอบ Tunnel ทำงาน

```bash
docker logs cloudflared
```

ควรเห็น:
```
Connection established connIndex=0 ...
```

หรือเปิด Zero Trust Dashboard → **Networks → Tunnels** → สถานะ **Healthy**

### 3.2 URL ของ Tunnel

URL คงที่ตามที่กำหนด Public Hostname ใน Zero Trust:
```
https://n8n.thaitechsync.com
```

> **ข้อดีเหนือ Ngrok:** URL ไม่เปลี่ยนแม้จะ restart Docker — ไม่ต้องอัปเดต Node-RED ซ้ำ

---

## 4. ขั้นตอนที่ 2 — Import N8N Workflow

### 4.1 เปิด N8N

```
http://localhost:5678
```

### 4.2 Import Workflow

1. คลิก **"Add workflow"** หรือ **"+"** มุมบนซ้าย
2. คลิกเมนู **"..."** (สามจุด) มุมบนขวาของ canvas
3. เลือก **"Import from file"**
4. เลือกไฟล์: `flows/n8n-smartfarm-workflow.json`
5. Workflow จะปรากฏบน canvas ชื่อ **"SmartFarm ESP32 Automation"**

### 4.3 Activate Workflow

1. คลิก Toggle **"Active"** มุมบนขวา (เปลี่ยนจาก Inactive → Active)
2. หลัง Activate webhook URLs จะพร้อมรับข้อมูล

> **หมายเหตุ:** ใช้ **Production webhook URL** (ไม่ใช่ Test URL)  
> - Production: `https://YOUR-NGROK.ngrok-free.app/webhook/smartfarm-telemetry`  
> - Test (ใช้ได้เฉพาะตอนกด "Test workflow"): `https://YOUR-NGROK.ngrok-free.app/webhook-test/smartfarm-telemetry`

---

## 5. ขั้นตอนที่ 3 — อัปเดต Node-RED Flow

### 5.1 Import Flow ใหม่

1. เปิด Node-RED → เมนู **☰** → **Import**
2. เลือกไฟล์: `flows/smartfarm-nodered-n8n.json`
3. Import เป็น **new flow** หรือแทนที่ flow เดิม

### 5.2 อัปเดต Ngrok URL ใน HTTP Request Nodes

Flow ใหม่มี HTTP Request nodes **2 ตัว** ที่ต้องแก้ URL:

**Node: "POST → N8N Telemetry"**
- ดับเบิลคลิก node
- แก้ URL จาก:
  ```
  https://YOUR-NGROK-URL.ngrok-free.app/webhook/smartfarm-telemetry
  ```
  เป็น:
  ```
  https://xxxx-xx-xx-xx-xx.ngrok-free.app/webhook/smartfarm-telemetry
  ```

**Node: "POST → N8N Status"**
- ดับเบิลคลิก node  
- แก้ URL จาก:
  ```
  https://YOUR-NGROK-URL.ngrok-free.app/webhook/smartfarm-status
  ```
  เป็น:
  ```
  https://xxxx-xx-xx-xx-xx.ngrok-free.app/webhook/smartfarm-status
  ```

### 5.3 Deploy

คลิก **Deploy** (ปุ่มแดงมุมบนขวา)

---

## 6. โครงสร้าง N8N Workflow

### Pipeline 1: Telemetry

```
[Webhook: Telemetry]
        │
        ▼
[Extract Telemetry Fields]  ← Set node: แยก fields ทั้งหมด
        │
        ├──────────────────────────────────┐
        │                                  │
        ▼                                  ▼
[IF: Water Alert?]              [IF: Temp > 35°C?]
   water_overflow=true             air_temp >= 35
   OR water_dry=true                    │
        │ TRUE                     TRUE  │  FALSE
        ▼                               │
[Set Water Alert Message]    [Set Temp Alert Message]
   alert_type, message               (no action)
        │
        │ FALSE
        │
        ▼
[Respond 200 OK (Telemetry)]
```

### Pipeline 2: Status

```
[Webhook: Status]
        │
        ▼
[Extract Status Fields]  ← Set node: แยก fields + คำนวณ uptime_hours
        │
        ├──────────────────────────┐
        │                         │
        ▼                         ▼
[IF: Device Offline?]    [Respond 200 OK (Status)]
   status == "offline"
        │ TRUE
        ▼
[Set Offline Alert Message]
   alert_type, message
        │ FALSE
        (ไม่ทำอะไร)
```

---

## 7. รายละเอียด Nodes ใน N8N

### 7.1 Webhook Nodes

| Node | Path | Method |
|------|------|--------|
| Webhook: Telemetry | `/webhook/smartfarm-telemetry` | POST |
| Webhook: Status | `/webhook/smartfarm-status` | POST |

- `responseMode: responseNode` → ตอบกลับผ่าน **Respond to Webhook** node (ควบคุม response ได้)
- ข้อมูลที่รับเข้ามาจะอยู่ใน `$json.body` (N8N wrap ไว้อัตโนมัติ)

---

### 7.2 Extract Telemetry Fields (Set Node)

แยก fields จาก `$json.body` ออกมาเป็น flat structure:

| Output Field | Source | ชนิด |
|-------------|--------|------|
| `board_id` | `$json.body.board_id` | string |
| `timestamp_ms` | `$json.body.timestamp` | number |
| `rssi` | `$json.body.rssi` | number |
| `water_temp` | `$json.body.sensors.water_temp` | number |
| `air_temp` | `$json.body.sensors.air_temp` | number |
| `air_humidity` | `$json.body.sensors.air_humidity` | number |
| `water_overflow` | `$json.body.sensors.water_overflow` | boolean |
| `water_dry` | `$json.body.sensors.water_dry` | boolean |
| `relay1_pump` | `$json.body.relays.relay1_pump` | boolean |
| `relay2_fan` | `$json.body.relays.relay2_fan` | boolean |
| `relay3_heater` | `$json.body.relays.relay3_heater` | boolean |
| `received_at` | `$now.toISO()` | string |

---

### 7.3 Extract Status Fields (Set Node)

| Output Field | Source | ชนิด |
|-------------|--------|------|
| `board_id` | `$json.body.board_id` | string |
| `status` | `$json.body.status` | string |
| `ip` | `$json.body.ip` | string |
| `firmware` | `$json.body.firmware` | string |
| `uptime_sec` | `$json.body.uptime` | number |
| `uptime_hours` | `($json.body.uptime / 3600).toFixed(2)` | string |
| `received_at` | `$now.toISO()` | string |

---

### 7.4 IF Nodes (Condition Checks)

| Node | Condition | True Branch | False Branch |
|------|-----------|-------------|--------------|
| IF: Water Alert? | `water_overflow == true` OR `water_dry == true` | Set Alert | ไม่ทำอะไร |
| IF: Temp > 35°C? | `air_temp >= 35` | Set Alert | ไม่ทำอะไร |
| IF: Device Offline? | `status == "offline"` | Set Alert | ไม่ทำอะไร |

---

### 7.5 Alert Set Nodes (Output พร้อมต่อ Action)

**Water Alert:**
```json
{
  "alert_type": "WATER_OVERFLOW" or "WATER_DRY",
  "alert_message": "[ALERT] น้ำล้น! ..." or "[ALERT] น้ำหมด ...",
  "board_id": "ESP32-FARM-001-NATTAPHOL-PALM",
  "triggered_at": "2026-04-10T10:30:00.000Z"
}
```

**Temp Alert:**
```json
{
  "alert_type": "TEMP_HIGH",
  "alert_message": "[ALERT] อุณหภูมิสูงเกิน! air_temp=36.2°C (เกณฑ์ 35°C)",
  "board_id": "ESP32-FARM-001-NATTAPHOL-PALM",
  "air_temp": 36.2,
  "triggered_at": "2026-04-10T10:30:00.000Z"
}
```

**Offline Alert:**
```json
{
  "alert_type": "DEVICE_OFFLINE",
  "alert_message": "[ALERT] ESP32 Offline! board_id=ESP32-FARM-001-NATTAPHOL-PALM",
  "board_id": "ESP32-FARM-001-NATTAPHOL-PALM",
  "last_ip": "192.168.1.7",
  "triggered_at": "2026-04-10T10:30:00.000Z"
}
```

---

### 7.6 Respond to Webhook Nodes

ส่ง HTTP Response 200 กลับไปยัง Node-RED เสมอ:

```json
{
  "status": "ok",
  "received": "telemetry",
  "timestamp": "2026-04-10T10:30:00.000Z"
}
```

Node-RED จะแสดง response นี้ใน Debug node ชื่อ **"N8N Response (Telemetry)"** และ **"N8N Response (Status)"**

---

## 8. Webhook Endpoints

| Endpoint | ใช้สำหรับ | รับจาก |
|----------|----------|--------|
| `POST /webhook/smartfarm-telemetry` | ข้อมูลเซ็นเซอร์ | Node-RED (ทุกครั้งที่ได้ MQTT telemetry) |
| `POST /webhook/smartfarm-status` | สถานะ device | Node-RED (ทุกครั้งที่ได้ MQTT status) |

**Full URL (Production):**
```
https://n8n.thaitechsync.com/webhook/smartfarm-telemetry
https://n8n.thaitechsync.com/webhook/smartfarm-status
```

**Test ด้วย curl:**
```bash
curl -X POST https://n8n.thaitechsync.com/webhook/smartfarm-telemetry \
  -H "Content-Type: application/json" \
  -d '{"board_id":"ESP32-FARM-001-NATTAPHOL-PALM","timestamp":99648422,"rssi":-56,"sensors":{"water_temp":26.4,"air_temp":30.1,"air_humidity":70.8,"water_overflow":false,"water_dry":false},"relays":{"relay1_pump":true,"relay2_fan":true,"relay3_heater":true}}'
```

```bash
curl -X POST https://n8n.thaitechsync.com/webhook/smartfarm-status \
  -H "Content-Type: application/json" \
  -d '{"board_id":"ESP32-FARM-001-NATTAPHOL-PALM","status":"online","ip":"192.168.1.7","firmware":"1.0.0","uptime":99739,"timestamp":99739959}'
```

---

## 9. Logic การตรวจสอบ Alert

### 9.1 เกณฑ์ Alert ที่ตั้งไว้

| Alert | เงื่อนไข | ความรุนแรง |
|-------|---------|-----------|
| WATER_OVERFLOW | `sensors.water_overflow == true` | สูง — หยุดปั๊มน้ำทันที |
| WATER_DRY | `sensors.water_dry == true` | สูง — เติมน้ำด่วน |
| TEMP_HIGH | `sensors.air_temp >= 35°C` | กลาง — เปิดพัดลม/ลดอุณหภูมิ |
| DEVICE_OFFLINE | `status == "offline"` | สูง — อุปกรณ์ขาดการเชื่อมต่อ |

### 9.2 การปรับเกณฑ์อุณหภูมิ

ดับเบิลคลิก node **"IF: Temp > 35°C?"** → แก้ค่า `rightValue` จาก `35` เป็นค่าที่ต้องการ

---

## 10. การเพิ่ม Action ต่อจาก Alert Nodes

Alert Set nodes ทั้ง 3 ตัวพร้อมต่อ action ได้เลย ต่อ node ออกจาก output ของ Set nodes เหล่านี้:

### ตัวอย่าง Actions ที่ต่อได้

| Action | N8N Node | คำอธิบาย |
|--------|----------|----------|
| Line Notify | HTTP Request | POST ไป `notify-api.line.me` |
| Email | Gmail / SMTP | ส่ง email แจ้งเตือน |
| Slack | Slack node | ส่ง message ไป channel |
| Discord | HTTP Request | ส่ง Discord webhook |
| Google Sheets | Google Sheets node | บันทึก log |
| Telegram | Telegram node | ส่ง bot message |

### ตัวอย่าง: ต่อ Line Notify

1. คลิก output ของ **"Set Water Alert Message"**
2. ลาก → วาง **"HTTP Request"** node
3. ตั้งค่า:
   ```
   Method  : POST
   URL     : https://notify-api.line.me/api/notify
   Headers : Authorization = Bearer YOUR-LINE-TOKEN
   Body    : message={{ $json.alert_message }}
   ```

---

## 11. การทดสอบ End-to-End

### ขั้นที่ 1 — ตรวจสอบ N8N Webhook พร้อมใช้

1. เปิด N8N → Workflow **"SmartFarm ESP32 Automation"**
2. ตรวจ Toggle ว่า **Active** (สีเขียว)
3. คลิกที่ node **"Webhook: Telemetry"** → ดู Production URL ที่แสดง

---

### ขั้นที่ 2 — ส่งข้อมูล Telemetry ทดสอบ

วิธีที่ 1: **ผ่าน Node-RED** (ใช้ ESP32 ส่งข้อมูล MQTT ตามปกติ)

วิธีที่ 2: **curl โดยตรง**
```bash
curl -X POST https://YOUR-NGROK-URL.ngrok-free.app/webhook/smartfarm-telemetry \
  -H "Content-Type: application/json" \
  -d '{"board_id":"ESP32-FARM-001-NATTAPHOL-PALM","timestamp":100000,"rssi":-56,"sensors":{"water_temp":26.4,"air_temp":36.5,"air_humidity":70.8,"water_overflow":false,"water_dry":true},"relays":{"relay1_pump":false,"relay2_fan":false,"relay3_heater":false}}'
```
> ตัวอย่างนี้จะ trigger ทั้ง **WATER_DRY** และ **TEMP_HIGH** พร้อมกัน

---

### ขั้นที่ 3 — ตรวจสอบผลใน N8N

1. เปิด N8N → คลิก **"Executions"** ด้านซ้าย
2. ดู execution ล่าสุด → คลิกเพื่อดู detail
3. แต่ละ node จะแสดง input/output ที่ผ่าน
4. ตรวจสอบว่า IF nodes routing ถูก branch

---

### ขั้นที่ 4 — ตรวจสอบ Response ใน Node-RED

1. เปิด Node-RED Debug panel
2. ดูที่ node **"N8N Response (Telemetry)"** และ **"N8N Response (Status)"**
3. ต้องเห็น response:
   ```json
   { "status": "ok", "received": "telemetry", "timestamp": "..." }
   ```

---

### ตารางสรุปการทดสอบ

| # | กรณีทดสอบ | วิธีทดสอบ | ผลที่คาดหวัง | ผ่าน/ไม่ผ่าน |
|---|-----------|-----------|--------------|-------------|
| 1 | Webhook รับข้อมูล Telemetry | curl / Node-RED | N8N execution ปรากฏ | |
| 2 | Extract fields ถูกต้อง | ดู execution detail | ทุก field มีค่าครบ | |
| 3 | Water Alert trigger | ส่ง `water_dry: true` | Set Water Alert Message ทำงาน | |
| 4 | Temp Alert trigger | ส่ง `air_temp: 36` | Set Temp Alert Message ทำงาน | |
| 5 | No Alert (ปกติ) | ส่ง `air_temp: 28` | IF nodes ผ่าน False branch | |
| 6 | Webhook รับข้อมูล Status | curl / Node-RED | N8N execution ปรากฏ | |
| 7 | Device Offline Alert | ส่ง `status: "offline"` | Set Offline Alert Message ทำงาน | |
| 8 | Device Online (ปกติ) | ส่ง `status: "online"` | IF offline ผ่าน False branch | |
| 9 | Node-RED รับ 200 OK | ดู Debug panel | Response `{"status":"ok"}` | |

---

## 12. การแก้ไขปัญหาเบื้องต้น

### ปัญหา: Node-RED ส่ง HTTP แล้ว Error / Timeout

**สาเหตุ:**
- Cloudflare Tunnel ยังไม่ start หรือ unhealthy
- N8N Workflow ยัง Inactive
- URL พิมพ์ผิดใน Node-RED

**วิธีแก้:**
1. ตรวจสอบ tunnel: `docker logs cloudflared` — ต้องเห็น `Connection established`
2. ตรวจสอบ N8N Toggle เป็น **Active**
3. URL ใน Node-RED HTTP Request nodes ต้องตรงกับ `CF_TUNNEL_URL` ใน `.env`

---

### ปัญหา: N8N รับข้อมูลได้ แต่ fields ว่างเปล่า

**สาเหตุ:**
- N8N wrap body ไว้ใน `$json.body` ไม่ใช่ `$json` โดยตรง

**วิธีแก้:**
- ตรวจสอบใน Extract node ว่าใช้ `$json.body.sensors.water_temp` ไม่ใช่ `$json.sensors.water_temp`
- ดู raw data ใน execution ของ Webhook node ว่า body อยู่ที่ไหน

---

### ปัญหา: N8N ใน Docker เข้าไม่ได้หลัง restart

**วิธีแก้:**
```bash
docker start <n8n-container-name>
```
หรือตรวจสอบ:
```bash
docker ps -a | grep n8n
```

---

## ไฟล์ที่เกี่ยวข้องทั้งหมด

| ไฟล์ | คำอธิบาย |
|------|---------|
| `flows/smartfarm-esp32-control.json` | Node-RED flow ต้นฉบับ (MQTT only) |
| `flows/smartfarm-nodered-n8n.json` | Node-RED flow (MQTT + HTTP → N8N) |
| `flows/smartfarm-nodered-full.json` | Node-RED flow ฉบับสมบูรณ์ (+ รับคำสั่งจาก N8N) |
| `flows/n8n-smartfarm-workflow.json` | N8N workflow พื้นฐาน |
| `flows/n8n-smartfarm-autocontrol.json` | N8N workflow + Auto Relay Control |
| `ESP32MQTTTester.md` | เอกสารทดสอบ MQTT |
| `N8NAutomation.md` | เอกสารนี้ |

---

## Auto-Control: N8N สั่ง Relay กลับไปยัง Node-RED

> **ไฟล์ที่ใช้:**  
> - Node-RED: `flows/smartfarm-nodered-full.json`  
> - N8N: `flows/n8n-smartfarm-autocontrol.json`

### ภาพรวม Auto-Control Loop

```
ESP32 ──MQTT──► Node-RED ──HTTP POST──► N8N
                                         │
                                    ตรวจ conditions
                                         │
                              ┌──────────┼──────────┐
                         water_overflow  │ water_dry │ air_temp≥35
                              │          │           │
                          ALL OFF     Pump ON      Fan ON
                              │          │           │
                              └──────────┴───────────┘
                                         │ HTTP POST
                                         ▼
                               Node-RED /smartfarm/relay-control
                                         │
                                    validate & format
                                         │ MQTT Publish
                                         ▼
                                       ESP32
                                  (ทำงานตาม relay command)
```

---

### Auto-Control Rules

| เงื่อนไข | Action | Relay State |
|---------|--------|-------------|
| `water_overflow == true` | ปิดปั๊มน้ำทันที | pump=OFF, fan=OFF, heater=OFF |
| `water_dry == true` | เปิดปั๊มน้ำ เติมน้ำ | pump=ON, fan=OFF, heater=OFF |
| `air_temp >= 35°C` | เปิดพัดลม ระบายความร้อน | pump=OFF, fan=ON, heater=OFF |
| `status == "offline"` | แจ้งเตือนเท่านั้น | ไม่สั่ง relay (device ไม่ online) |

---

### การตั้งค่า — Node-RED (smartfarm-nodered-full.json)

Node-RED เพิ่ม **HTTP In endpoint** รับคำสั่งจาก N8N:

```
POST http://localhost:1880/smartfarm/relay-control
```

**Flow ของ endpoint นี้:**

```
[HTTP In: POST /smartfarm/relay-control]
        │
        ▼
[Function: Validate & Format Relay Command]
        │
        ├── Output 1 → [PUB: Control → ESP32]  (MQTT publish)
        └── Output 2 → [HTTP Response → N8N]   (200 OK)
```

**Function node ทำงาน:**
1. ตรวจสอบว่า `command == "relay_control"` และมี `relays` object
2. ถ้าถูกต้อง → สร้าง MQTT payload ส่ง ESP32
3. ถ้าผิดรูปแบบ → ส่ง HTTP 400 กลับ ไม่ส่ง MQTT
4. แสดง status บน canvas (สีเขียว + reason)

---

### โค้ด Function Node — อธิบายทีละส่วน

```js
const body = msg.payload;
```
> รับ body ของ HTTP POST ที่ N8N ส่งมา — ข้อมูลทั้งหมดอยู่ใน `msg.payload`  
> (Node-RED HTTP In node จะ parse JSON ให้อัตโนมัติ)

---

```js
if (!body || body.command !== 'relay_control' || !body.relays) {
    node.warn('Invalid command: ' + JSON.stringify(body));
    const errRes = { payload: { status: 'error', message: 'Invalid command format' }, statusCode: 400 };
    return [null, errRes];
}
```
> **Guard clause** — ตรวจสอบ 3 เงื่อนไขก่อนทำงาน:
>
> | เงื่อนไข | ความหมาย |
> |---------|---------|
> | `!body` | ไม่มีข้อมูลเลย (body ว่าง/null) |
> | `body.command !== 'relay_control'` | command ผิดประเภท |
> | `!body.relays` | ไม่มี relays object (ไม่รู้จะสั่ง relay ไหน) |
>
> ถ้าผิดเงื่อนไขใดข้อหนึ่ง:
> - `node.warn(...)` → แสดง warning ใน Debug panel
> - `return [null, errRes]` → ส่งออก **Output 2** เป็น HTTP 400 และ **Output 1 เป็น null** (ไม่ส่ง MQTT)

---

```js
const mqttMsg = {
    payload: {
        command: 'relay_control',
        relays: {
            relay1_pump:   body.relays.relay1_pump   !== undefined ? body.relays.relay1_pump   : false,
            relay2_fan:    body.relays.relay2_fan    !== undefined ? body.relays.relay2_fan    : false,
            relay3_heater: body.relays.relay3_heater !== undefined ? body.relays.relay3_heater : false
        }
    },
    topic: ''
};
```
> **สร้าง MQTT message** ที่จะส่งให้ ESP32
>
> **Pattern:** `ค่าจาก body !== undefined ? ใช้ค่านั้น : false`  
> = ถ้า N8N ส่ง relay มาครบก็ใช้ค่านั้น แต่ถ้าไม่ได้ส่งฟิลด์ไหนมา (undefined) ให้ default เป็น `false`
>
> ตัวอย่าง: N8N ส่งมาแค่ `relay2_fan: true` โดยไม่ส่ง relay อื่น  
> → relay1_pump = **false** (default), relay2_fan = **true**, relay3_heater = **false** (default)
>
> `topic: ''` → ปล่อยว่างเพราะ topic ถูกกำหนดไว้ใน MQTT Out node แล้ว

---

```js
const resMsg = {
    payload: {
        status: 'ok',
        action:       body.reason       || 'manual',
        triggered_by: body.triggered_by || 'unknown',
        relays:       mqttMsg.payload.relays,
        timestamp:    new Date().toISOString()
    },
    statusCode: 200
};
```
> **สร้าง HTTP Response** ที่จะส่งกลับไปหา N8N (ยืนยันว่ารับคำสั่งแล้ว)
>
> | Field | ความหมาย | ตัวอย่าง |
> |-------|---------|---------|
> | `status` | ผลการทำงาน | `"ok"` |
> | `action` | เหตุผลที่สั่ง (จาก `body.reason`) | `"temp_high"`, `"water_dry"` |
> | `triggered_by` | ต้นทางที่สั่ง (จาก `body.triggered_by`) | `"n8n_auto"` |
> | `relays` | relay states จริงที่ส่ง MQTT ไป | `{relay1_pump:false, relay2_fan:true, ...}` |
> | `timestamp` | เวลาที่ประมวลผล | `"2026-04-10T10:30:00.000Z"` |
>
> **`||` (OR)** — ใช้ fallback ถ้าค่าหลักเป็น falsy:
> - `body.reason || 'manual'` → ถ้า N8N ไม่ส่ง reason มา จะใช้ค่า `'manual'`
> - `body.triggered_by || 'unknown'` → ถ้าไม่รู้ต้นทาง จะแสดง `'unknown'`

---

```js
node.status({ fill: 'green', shape: 'dot', text: body.reason || 'command received' });
return [mqttMsg, resMsg];
```
> **`node.status(...)`** → แสดง indicator สีเขียวใต้ node ใน canvas พร้อมข้อความ reason
> (เช่น "temp_high", "water_dry") เพื่อ debug ได้โดยไม่ต้องเปิด Debug panel
>
> **`return [mqttMsg, resMsg]`** → node นี้มี **2 outputs**:
> - Output 1 = `mqttMsg` → ไปที่ **MQTT Out** node → ส่งคำสั่งให้ ESP32
> - Output 2 = `resMsg` → ไปที่ **HTTP Response** node → ส่ง 200 OK กลับ N8N

---

### ภาพรวม Data Flow ของ Function Node

```
N8N HTTP POST
      │
      ▼
[msg.payload = body]
      │
      ▼  ┌─ body ว่าง?
[Validate]─┤─ command ผิด?  → Output 2: HTTP 400 │ Output 1: null (ไม่ publish)
           └─ ไม่มี relays?
      │
      │ (ผ่านทุกเงื่อนไข)
      ▼
[Build mqttMsg]  → relay ที่ไม่ได้ส่งมา default = false
      │
      ▼
[Build resMsg]   → ยืนยัน relays จริงที่จะส่ง + timestamp
      │
      ▼
[node.status]    → แสดง indicator บน canvas
      │
      ▼
return [mqttMsg, resMsg]
   │            │
   ▼            ▼
MQTT Out    HTTP Response
(→ ESP32)   (→ N8N 200 OK)
```

**Request body ที่ N8N ส่งมา:**
```json
{
  "command": "relay_control",
  "relays": {
    "relay1_pump": false,
    "relay2_fan": true,
    "relay3_heater": false
  },
  "triggered_by": "n8n_auto",
  "reason": "temp_high",
  "board_id": "ESP32-FARM-001-NATTAPHOL-PALM"
}
```

**Response ที่ Node-RED ส่งกลับ:**
```json
{
  "status": "ok",
  "action": "temp_high",
  "triggered_by": "n8n_auto",
  "relays": { "relay1_pump": false, "relay2_fan": true, "relay3_heater": false },
  "timestamp": "2026-04-10T10:30:00.000Z"
}
```

---

### การตั้งค่า — N8N (n8n-smartfarm-autocontrol.json)

N8N เพิ่ม nodes หลัง IF conditions แต่ละตัว:

**Pattern ของแต่ละ auto-control branch:**
```
[IF: condition?]
     │ TRUE
     ▼
[Set: CMD payload]   ← กำหนด relay states + reason + triggered_by
     │
     ▼
[HTTP Request: → NodeRED]   ← POST ไปที่ Node-RED
     │
     ▼
(ได้รับ 200 OK response จาก Node-RED)
```

**URL ที่ N8N ใช้เรียก Node-RED:**
```
http://host.docker.internal:1880/smartfarm/relay-control
```

> `host.docker.internal` คือ hostname พิเศษสำหรับ Docker Desktop บน Windows/Mac  
> ใช้แทน `localhost` เพราะ N8N รันอยู่ใน container ไม่ใช่ host โดยตรง

---

### ขั้นตอนการ Setup Auto-Control

**ขั้นที่ 1 — Import Node-RED Flow ใหม่**
1. Node-RED → Import → เลือก `flows/smartfarm-nodered-full.json`
2. Deploy
3. ตรวจสอบว่า node **"POST /smartfarm/relay-control"** ปรากฏบน canvas

**ขั้นที่ 2 — Import N8N Workflow ใหม่**
1. N8N → Import → เลือก `flows/n8n-smartfarm-autocontrol.json`
2. อัปเดต Ngrok URL ใน Webhook node (ถ้าเปลี่ยน)
3. Activate workflow

**ขั้นที่ 3 — ทดสอบ Auto-Control ด้วย curl**

ทดสอบ N8N → Node-RED โดยตรง (ทดสอบ endpoint Node-RED):
```bash
curl -X POST http://localhost:1880/smartfarm/relay-control \
  -H "Content-Type: application/json" \
  -d '{"command":"relay_control","relays":{"relay1_pump":false,"relay2_fan":true,"relay3_heater":false},"triggered_by":"n8n_auto","reason":"temp_high","board_id":"ESP32-FARM-001-NATTAPHOL-PALM"}'
```

ทดสอบ Trigger ผ่าน N8N webhook (จำลอง sensor ร้อน):
```bash
curl -X POST https://YOUR-NGROK-URL.ngrok-free.app/webhook/smartfarm-telemetry \
  -H "Content-Type: application/json" \
  -d '{"board_id":"ESP32-FARM-001-NATTAPHOL-PALM","timestamp":100000,"rssi":-56,"sensors":{"water_temp":26.4,"air_temp":37.0,"air_humidity":70.8,"water_overflow":false,"water_dry":false},"relays":{"relay1_pump":false,"relay2_fan":false,"relay3_heater":false}}'
```
> ผลที่คาดหวัง: N8N ตรวจพบ air_temp=37 ≥ 35 → ส่งคำสั่ง Fan ON กลับ Node-RED → MQTT Publish → ESP32 เปิด relay2_fan

---

### ตารางสรุปการทดสอบ Auto-Control

| # | กรณีทดสอบ | ข้อมูลที่ส่ง | ผลที่คาดหวัง | ผ่าน/ไม่ผ่าน |
|---|-----------|------------|--------------|-------------|
| 1 | Node-RED รับคำสั่งจาก N8N | curl POST ไป `/smartfarm/relay-control` | MQTT publish + 200 OK response | |
| 2 | Auto: Fan ON เมื่อร้อน | `air_temp: 37` | N8N → NodeRED Fan ON → ESP32 | |
| 3 | Auto: ALL OFF เมื่อน้ำล้น | `water_overflow: true` | N8N → NodeRED ALL OFF → ESP32 | |
| 4 | Auto: Pump ON เมื่อน้ำแห้ง | `water_dry: true` | N8N → NodeRED Pump ON → ESP32 | |
| 5 | ไม่ trigger เมื่อปกติ | `air_temp: 28, overflow: false` | IF nodes ผ่าน False branch | |
| 6 | Invalid command rejected | body ไม่มี `command` field | Node-RED ส่ง 400, ไม่ publish MQTT | |

---

### การแก้ไขปัญหา Auto-Control

**ปัญหา: N8N เรียก Node-RED ไม่ได้ (Connection refused)**

สาเหตุ: `host.docker.internal` ใช้ไม่ได้ใน Linux Docker  
วิธีแก้: ใช้ IP ของ host machine แทน
```bash
# หา IP ของ host จากใน Docker container
ip route show default | awk '/default/ {print $3}'
```
แล้วเปลี่ยน URL ใน HTTP Request nodes เป็น `http://192.168.x.x:1880/smartfarm/relay-control`

---

**ปัญหา: Node-RED ส่ง 400 Bad Request กลับ N8N**

สาเหตุ: body ที่ N8N ส่งมาผิดรูปแบบ  
วิธีแก้: ดู Debug node **"N8N Auto-Control Command"** ใน Node-RED แล้วตรวจ payload ที่รับได้

---

*เอกสารนี้สร้างสำหรับโปรเจกต์ SmartFarm ESP32 — Node-RED → N8N Automation via Webhook*  
*สร้างเมื่อ: 2026-04-10 | อัปเดต: เพิ่ม Auto-Control (N8N → Node-RED → ESP32)*
