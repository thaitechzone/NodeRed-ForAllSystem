# คู่มือระบบ Smart Energy Management
## Node-RED + N8N + AI Agent + Google Sheets

> **เวอร์ชัน:** 2.0 | **วันที่:** 16 พฤษภาคม 2569 | **ภาษา:** ไทย  
> **ตรวจสอบจาก:** source code จริงใน `flows/` และ `docker-compose.yml`

---

## สารบัญ

1. [ภาพรวมระบบ](#1-ภาพรวมระบบ)
2. [สถาปัตยกรรม](#2-สถาปัตยกรรม)
3. [โครงสร้างไฟล์โปรเจกต์](#3-โครงสร้างไฟล์โปรเจกต์)
4. [Infrastructure (Docker)](#4-infrastructure-docker)
5. [Node-RED Flow — Energy Test → N8N](#5-node-red-flow--energy-test--n8n)
6. [N8N Workflow 1 — Energy Collector](#6-n8n-workflow-1--energy-collector)
7. [N8N Workflow 2 — AI Energy Analyzer](#7-n8n-workflow-2--ai-energy-analyzer)
8. [Google Sheets (Data Storage)](#8-google-sheets-data-storage)
9. [Dashboard UI (Node-RED)](#9-dashboard-ui-node-red)
10. [AI Decision Logic](#10-ai-decision-logic)
11. [Data Flow สมบูรณ์](#11-data-flow-สมบูรณ์)
12. [การตั้งค่าระบบใหม่ (Setup)](#12-การตั้งค่าระบบใหม่-setup)
13. [การแก้ปัญหาที่พบบ่อย](#13-การแก้ปัญหาที่พบบ่อย)

---

## 1. ภาพรวมระบบ

ระบบนี้จำลองการทำงานของเครื่องจักรในโรงงาน (Machine **MC-01**) เพื่อ **ติดตามและวิเคราะห์การใช้พลังงานแบบ Real-time** โดยใช้ AI ตัดสินใจว่าควร **ลดกำลังการทำงาน (ECO Mode)** หรือ **ทำงานปกติ (NORMAL Mode)**

### จุดประสงค์หลัก

| # | หน้าที่ | เทคโนโลยี | ความถี่ |
|---|---|---|---|
| 1 | จำลองข้อมูลพลังงาน 3 เฟส | Node-RED Function | ทุก **10 วินาที** |
| 2 | เก็บข้อมูลลง Google Sheets | N8N Workflow 1 | ทุก 10 วินาที |
| 3 | วิเคราะห์ด้วย AI | N8N Workflow 2 + OpenRouter | ทุก **1 นาที** |
| 4 | ส่งคำสั่งควบคุม simulator | HTTP API | ทุกครั้งที่วิเคราะห์ |
| 5 | แสดงผล Dashboard | Node-RED Dashboard | Real-time |

---

## 2. สถาปัตยกรรม

```
Internet
    │  HTTPS (Cloudflare Tunnel)
    ▼
┌─────────────────────────────────────────────────────────────┐
│                     LOCAL (Docker)                          │
│                                                             │
│  ┌──────────────┐    ┌──────────────────┐                  │
│  │  cloudflared │───►│  Nginx Proxy Mgr │                  │
│  │  (Tunnel)    │    │  Port: 80/443/81 │                  │
│  └──────────────┘    └────────┬─────────┘                  │
│                               │                             │
│  ┌──────────────┐    ┌────────▼─────────────────────────┐  │
│  │  Mosquitto   │    │           N8N                    │  │
│  │  Port: 1883  │◄───│  Port: 5678                      │  │
│  └──────┬───────┘    │  Public: https://${N8N_DOMAIN}   │  │
│         │  MQTT      └────────────┬─────────────────────┘  │
│         ▼                         │                         │
│  ┌──────────────┐    ┌────────────▼─────────────────────┐  │
│  │   Node-RED   │    │      Google Sheets               │  │
│  │  Port: 1880  │    │  EnergyLog / LogResult           │  │
│  │  Simulator   │    └────────────┬─────────────────────┘  │
│  │  Dashboard   │                 │ อ่านข้อมูล              │
│  └──────────────┘    ┌────────────▼─────────────────────┐  │
│                      │     OpenRouter AI Agent          │  │
│  ┌──────────────┐    │     (ทุก 1 นาที)                │  │
│  │  InfluxDB    │    └──────────────────────────────────┘  │
│  │  Port: 8086  │                                          │
│  └──────┬───────┘                                          │
│         ▼                                                   │
│  ┌──────────────┐                                          │
│  │   Grafana    │                                          │
│  │  Port: 3000  │                                          │
│  └──────────────┘                                          │
└─────────────────────────────────────────────────────────────┘
```

### URL ที่ใช้งาน

| บริการ | URL | หมายเหตุ |
|---|---|---|
| Node-RED UI | `http://localhost:1880` | Flow editor |
| Node-RED Dashboard | `http://localhost:1880/ui` | แสดงผล real-time |
| N8N (local) | `http://localhost:5678` | Workflow editor |
| N8N (public) | `https://<N8N_DOMAIN>` | ผ่าน Cloudflare Tunnel |
| InfluxDB | `http://localhost:8086` | Time-series database UI |
| Grafana | `http://localhost:3000` | Dashboard visualization |
| Nginx Proxy Manager | `http://localhost:81` | Reverse proxy admin |
| Home Assistant | `http://localhost:8123` | Home automation |

---

## 3. โครงสร้างไฟล์โปรเจกต์

```
NodeRed-ForAllSystem/
├── .env                          ← ตัวแปร environment (สร้างจาก .env.example)
├── .env.example                  ← Template สำหรับสร้าง .env
├── docker-compose.yml            ← กำหนด services ทั้งหมด
├── PROJECT-MANUAL.md             ← คู่มือนี้
├── README.md                     ← เอกสารภาพรวม
├── INSTALL.md                    ← คู่มือติดตั้งทีละขั้นตอน
│
├── flows/
│   ├── NodeRED flowsEnergy Test N8N.json   ← Flow Node-RED (import ที่ 1880)
│   ├── n8n-workflow1-collector.json        ← N8N Workflow 1 (import ที่ 5678)
│   └── n8n-workflow2-analyzer (New).json  ← N8N Workflow 2 (import ที่ 5678)
│
├── nodered/
│   └── settings.js               ← Config Node-RED (timezone, logging, auth)
│
├── mosquitto/
│   └── config/
│       └── mosquitto.conf        ← Config MQTT Broker
│
└── esp32-firmware-NodeRED/       ← Firmware สำหรับ ESP32
```

---

## 4. Infrastructure (Docker)

### Services ใน docker-compose.yml

| Container | Image | Port | หน้าที่ |
|---|---|---|---|
| `mosquitto` | eclipse-mosquitto:2 | 1883, 9001 | MQTT Broker สำหรับ IoT |
| `postgres` | postgres:16 | 5432 | Database สำหรับ N8N |
| `influxdb` | influxdb:2.7 | 8086 | Time-series database |
| `nodered` | nodered/node-red:latest | 1880 | Flow automation + Dashboard |
| `n8n` | n8nio/n8n:latest | 5678 | Workflow automation + AI |
| `homeassistant` | homeassistant/home-assistant:stable | 8123 | Home automation |
| `grafana` | grafana/grafana:latest | 3000 | Data visualization |
| `nginx-proxy-manager` | jc21/nginx-proxy-manager:latest | 80, 443, 81 | Reverse proxy + SSL |
| `cloudflared` | cloudflare/cloudflared:latest | — | Cloudflare Tunnel |

### Environment Variables

ไฟล์ `.env` (สร้างจาก `.env.example` — **ห้าม commit ลง git**):

```env
TZ=Asia/Bangkok
CLOUDFLARE_TUNNEL_TOKEN=<token-จาก-cloudflare-dashboard>
N8N_DOMAIN=n8n.yourdomain.com
N8N_ENCRYPTION_KEY=<32-char-hex>           # openssl rand -hex 16
POSTGRES_USER=iot_user
POSTGRES_PASSWORD=<strong-password>
POSTGRES_DB=iot_db
INFLUXDB_USERNAME=admin
INFLUXDB_PASSWORD=<strong-password>
INFLUXDB_ORG=iot_org
INFLUXDB_BUCKET=iot_bucket
INFLUXDB_ADMIN_TOKEN=<64-char-hex>         # openssl rand -hex 32
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<strong-password>
```

### N8N Environment ที่สำคัญ

| Variable | ค่า | คำอธิบาย |
|---|---|---|
| `N8N_PROTOCOL` | `https` | บอก N8N ว่าทำงานเบื้องหลัง HTTPS |
| `WEBHOOK_URL` | `https://${N8N_DOMAIN}/` | Public URL สำหรับ webhook |
| `N8N_EDITOR_BASE_URL` | `https://${N8N_DOMAIN}/` | URL สำหรับ N8N editor |
| `EXECUTIONS_DATA_MAX_AGE` | `168` | เก็บ execution logs 7 วัน |

### Node-RED Settings (nodered/settings.js)

- **Timezone:** `Asia/Bangkok` (ตั้งค่าในระดับ runtime)
- **Admin Auth:** ปิดอยู่ (commented out) — ไม่ต้อง login
- **Context Storage:** `memory` (default) + `localfilesystem` (persistent)
- **Port:** 1880

หากต้องการเปิด Admin Login สร้าง bcrypt hash ที่ https://bcrypt-generator.com (rounds=8) แล้วแก้ settings.js

### Network

- ทุก container อยู่ใน Docker network ชื่อ `iot_network` (bridge)
- Container คุยกันด้วยชื่อ container เช่น `http://nodered:1880` และ `mqtt://mosquitto:1883`
- **สำคัญ:** ใช้ชื่อ container เสมอ ไม่ใช้ `localhost` หรือ `host.docker.internal`

### คำสั่ง Docker พื้นฐาน

```bash
# เริ่ม stack
docker compose up -d

# ดูสถานะ
docker compose ps

# ดู logs
docker compose logs -f nodered
docker compose logs -f n8n
docker compose logs -f cloudflared

# หยุด stack
docker compose down

# รีสตาร์ท container เดียว
docker compose restart nodered
docker compose up -d --force-recreate cloudflared
```

---

## 5. Node-RED Flow — Energy Test → N8N

**ไฟล์:** `flows/NodeRED flowsEnergy Test N8N.json`  
**Tab:** `Energy Test → N8N`

### 5.1 ภาพรวม Flow

```
[Inject 10s] → [สร้าง Payload] ─┬─► [Wrap → N8N] → [POST N8N] → [Debug Response]
                                  │                              └─► [Catch Error]
                                  ├─► [แยก Gauges & Chart] → [Dashboard UI]
                                  └─► [Debug Payload]

[POST /energy-command] → [เก็บคำสั่ง + ตอบ 200] ─┬─► [200 OK]
                                                    └─► [แยก AI result → UI] → [Dashboard AI Panel]
```

---

### 5.2 Simulator — Node: `fn_build_payload`

**ทริกเกอร์:** Inject node (`inj_sim_5s`) ทุก **10 วินาที** (`repeat: "10"`)

> **หมายเหตุ:** ชื่อ Inject node เขียนว่า "ส่งข้อมูลทุก 5 วินาที" แต่ค่า `repeat` จริงคือ `"10"` (10 วินาที)

#### โมเดลการจำลอง

ใช้ **Sine Wave** เพื่อให้ค่าเปลี่ยนแปลงตามจังหวะ:
```
sine = sin(t × π / 60)   → คาบ ~2 นาที, ช่วง -1 ถึง +1
t    = Date.now() / 1000  (Unix time in seconds)
```

#### โหมดการทำงาน

| พารามิเตอร์ | NORMAL Mode | ECO Mode |
|---|---|---|
| Active Power | `7.8 + sine×1.7` = **6.1 – 9.5 kW** | `2.5 + sine×0.8` = **1.7 – 3.3 kW** |
| Load | `70 + sine×14` = **56 – 84%** | `32 + sine×9` = **23 – 41%** |
| Current (base) | `14 + sine×3.0` = **11 – 17 A** | `5.5 + sine×1.5` = **4 – 7 A** |
| Power Factor | `0.89 + sine×0.05` = **0.84 – 0.94** | `0.96` (คงที่) |
| Motor RPM | `1480 + rand(-20, +15)` = **1460 – 1495** | `lerp(1200→1380, ratio) ± 15` |

#### Smooth Transition — เปลี่ยน Mode อย่างนุ่มนวล

เมื่อ AI สั่งเปลี่ยน mode ค่าจะค่อยๆ เปลี่ยนผ่าน **20 steps** ด้วย Lerp:

```javascript
ratio = step / 20          // 0.0 → 1.0
base  = lerp(prev, target, ratio)   // Linear interpolation
```

ด้วย inject ทุก 10 วินาที: **20 steps × 10s ≈ 200 วินาที** (~3.3 นาที) จึงจะถึง mode ใหม่เต็มที่

#### Spike Event — โอกาส 10%

มีโอกาส 10% ต่อ tick (ใน NORMAL เท่านั้น) ที่จะเกิด power surge:
```
spikeX = rand(1.3, 1.8)    → กำลัง/กระแสพุ่งขึ้น 1.3–1.8×
overcurrent = true          → ถ้า current > 17.5 A ทุกเฟส
```

#### Voltage Sag — แรงดันลดตาม Load

```javascript
voltSag = (load_pct - 50) × 0.03   // เฉพาะ NORMAL mode
```

#### Energy Accumulation — สะสมพลังงานวันนี้

```javascript
energy_today_kwh += activePow * 5 / 3600   // สะสมทุก tick (ใช้ค่า 5s per tick)
```

> **หมายเหตุ:** โค้ดใช้ `5/3600` (5 วินาทีต่อ tick) แม้ inject จะทำงานทุก 10 วินาที ค่า `energy_today_kwh` จึงสะสมช้ากว่าความเป็นจริง ~2×

#### โครงสร้าง Payload ที่ส่ง

```json
{
  "machine_id": "MC-01",
  "ts": "2026-04-19T13:30:00.000+07:00",
  "voltage_v":             { "l1": 230.5, "l2": 229.1, "l3": 231.2 },
  "current_a":             { "l1": 14.2,  "l2": 13.8,  "l3": 14.5  },
  "frequency_hz":          50.02,
  "power_factor":          0.921,
  "active_power_kw":       7.84,
  "reactive_power_kvar":   3.21,
  "apparent_power_kva":    8.51,
  "energy_today_kwh":      2.45,
  "motor_rpm":             1477,
  "load_pct":              71.3,
  "alarm_overcurrent":     false,
  "spike_event":           false,
  "power_mode":            "NORMAL",
  "status_label":          "NORMAL",
  "transition_pct":        100,
  "reduce_power_active":   false,
  "source":                "node-red-energy-simulator"
}
```

**Timestamp:** ใช้ Bangkok UTC+7 — `new Date(Date.now() + 7*3600*1000).toISOString().replace('Z', '+07:00')`

---

### 5.3 Wrap Payload — Node: `fn_wrap_webhook`

ห่อข้อมูลให้เป็น format ที่ N8N รับ:

```javascript
msg.payload = {
  event:  'machine_energy_telemetry',
  source: 'node-red',
  topic:  'smartfactory/MC-01/energy/telemetry',
  data:   msg.payload   // payload จาก fn_build_payload
};
```

---

### 5.4 POST to N8N — Node: `http_post_n8n`

```
POST https://<N8N_DOMAIN>/webhook/energy-machine-telemetry
Content-Type: application/json
```

มี `catch` node สำหรับดัก error การส่งแยกต่างหาก

---

### 5.5 HTTP Endpoint — รับคำสั่งจาก N8N

**Node:** `http_in_cmd`  
**Method & Path:** `POST /energy-command`  
**URL สมบูรณ์ภายใน Docker:** `http://nodered:1880/energy-command`

#### Node: `fn_store_cmd` — เก็บคำสั่ง

```javascript
const reducePower = body.reduce_power === true;
flow.set('reduce_power', reducePower);   // Simulator อ่านทุก tick
flow.set('last_analysis', body);          // เก็บผลวิเคราะห์เต็ม

// ต้องใช้ msg ตัวเดิม (เพื่อรักษา msg.res สำหรับ http response)
msg.statusCode = 200;
msg.payload = { status: 'ok', reduce_power: reducePower, ts: new Date().toISOString() };
return [msg, uiMsg];   // output 1 → http response, output 2 → UI
```

> **สำคัญมาก:** ต้องคืน `msg` ตัวเดิม ห้ามสร้าง object ใหม่ มิฉะนั้น `msg.res` (HTTP response handle) จะหายและเกิด timeout

---

## 6. N8N Workflow 1 — Energy Collector

**ไฟล์:** `flows/n8n-workflow1-collector.json`  
**Workflow ID:** `RTBRCvWWvN7NddPy`  
**สถานะ:** Active  
**ทริกเกอร์:** Webhook POST

### Flow

```
[Webhook] → [Extract Sheet Row] → [Append to Google Sheet] → [Respond 200 OK]
```

---

### Node 1: Receive from Node-RED (Webhook)

| ค่า | รายละเอียด |
|---|---|
| Path | `energy-machine-telemetry` |
| Method | POST |
| Response Mode | `responseNode` (รอ Respond node ส่งคืนก่อน) |
| URL สมบูรณ์ | `https://<N8N_DOMAIN>/webhook/energy-machine-telemetry` |

---

### Node 2: Extract Sheet Row (Code)

**Smart Path Detection** — รองรับ payload ทุก format ที่เป็นไปได้:

```javascript
const d = raw.data?.machine_id   ? raw.data        // { event, data: {...} }  ← format ที่ Node-RED ส่ง
        : raw.body?.data          ? raw.body.data   // { body: { data: {...} } }
        : raw.body?.machine_id    ? raw.body        // { body: { machine_id, ... } }
        : raw.machine_id          ? raw             // flat payload
        : raw.data                ? raw.data
        : raw;
```

ฟิลด์ `_path_used` ใน output บอกว่าใช้ path ไหน (ใช้สำหรับ debug)

**ฟิลด์ที่ส่งลง Google Sheet:**

| ฟิลด์ | ประเภท | คำอธิบาย |
|---|---|---|
| timestamp | string | เวลา Bangkok +07:00 |
| machine_id | string | รหัสเครื่องจักร (MC-01) |
| power_mode | string | NORMAL / ECO |
| status_label | string | NORMAL / NORMAL ⚡SPIKE / NORMAL ⚠OVERCURRENT / ECO (xx%) |
| active_power_kw | number | กำลังไฟฟ้าจริง (kW) |
| reactive_power_kvar | number | กำลังรีแอคทีฟ (kVAr) |
| apparent_power_kva | number | กำลังปรากฏ (kVA) |
| power_factor | number | Power Factor (0–1) |
| energy_today_kwh | number | พลังงานสะสมวันนี้ (kWh) |
| frequency_hz | number | ความถี่ไฟฟ้า (Hz) |
| load_pct | number | % โหลดเครื่องจักร |
| motor_rpm | number | รอบมอเตอร์ (RPM) |
| current_max | number | กระแสสูงสุดใน 3 เฟส (A) |
| current_l1 / l2 / l3 | number | กระแสแต่ละเฟส (A) |
| voltage_l1 / l2 / l3 | number | แรงดันแต่ละเฟส (V) |
| alarm_overcurrent | string | `TRUE` / `FALSE` |
| spike_event | string | `TRUE` / `FALSE` |
| _path_used | string | debug: path ที่ใช้ดึงข้อมูล |

---

### Node 3: Append to Google Sheet

- **Spreadsheet:** EnergyLog
- **Sheet ID:** `1Oa979YHjGgximaLgiNp--XX4jLZRMgqmuWZJrPpZPaQ`
- **Tab:** Sheet1
- **Mapping Mode:** `autoMapInputData` — ส่งทุก field อัตโนมัติ
- **Credential:** `Google Sheets account` (OAuth2)

---

### Node 4: Respond 200 OK

```json
{ "status": "saved", "ts": "{{ $json.timestamp }}" }
```

---

## 7. N8N Workflow 2 — AI Energy Analyzer

**ไฟล์:** `flows/n8n-workflow2-analyzer (New).json`  
**Workflow ID:** `QyHZo76SA8njPP29`  
**สถานะ:** Active  
**ทริกเกอร์:** Schedule ทุก 1 นาที (`*/1 * * * *`)

### Flow

```
[Schedule 1min] → [Read Sheet] → [Filter 1min + Stats] → [Has Data?]
                                                               │ YES (skip = false)
                                                     [Build AI Prompt]
                                                               │
                                                  [AI Agent] ← [OpenRouter Chat Model]
                                                               │
                                                   [Parse AI Decision]
                                                               │
                                              [Send Command → Node-RED]
                                                               │
                                                   [Log Result to Sheet]
```

---

### Node 1: Every 1 Minutes (Schedule Trigger)

- **Cron:** `*/1 * * * *` (ทุกนาทีที่ 0 วินาที)
- ทำงานทุกนาทีตลอด 24 ชั่วโมง

---

### Node 2: Read Energy Log Sheet

- อ่าน **ทุก row** จาก EnergyLog → Sheet1
- ส่งต่อเป็น array ของ items ไปยัง Filter node

---

### Node 3: Filter 1min + Calc Stats (Code)

**ขั้นตอนการทำงาน:**

1. กรองเฉพาะ rows ที่ `timestamp` อยู่ใน **1 นาทีที่ผ่านมา**
2. ถ้าไม่พบข้อมูลใน 1 นาที → **fallback: ใช้ 12 rows ล่าสุด** (field `used_fallback: true`)
3. คำนวณสถิติสรุป

**สถิติที่คำนวณ:**

| Field | คำอธิบาย |
|---|---|
| `power_avg/max/min_kw` | avg / max / min ของ active_power_kw |
| `reactive_avg_kvar` | avg ของ reactive_power_kvar |
| `apparent_avg_kva` | avg ของ apparent_power_kva |
| `pf_avg`, `pf_min` | avg / min ของ power_factor |
| `load_avg/max_pct` | avg / max ของ load_pct |
| `current_avg/max_a` | avg / max ของ current_max |
| `rpm_avg` | avg ของ motor_rpm |
| `freq_avg_hz` | avg ของ frequency_hz |
| `energy_delta_kwh` | energy_last − energy_first (≥ 0) |
| `alarm_count` | จำนวน rows ที่ alarm_overcurrent = TRUE |
| `spike_count` | จำนวน rows ที่ spike_event = TRUE |
| `alarm_rate_pct`, `spike_rate_pct` | อัตราร้อยละของ alarm / spike |
| `time_from`, `time_to` | timestamp แรก-ท้ายของช่วง |
| `count` | จำนวน readings ที่ใช้วิเคราะห์ |
| `used_fallback` | `true` ถ้าใช้ 12 rows แทน 1min window |

---

### Node 4: Has Data? (IF)

- ผ่าน (TRUE): `skip = false` → ไปวิเคราะห์ต่อ
- ไม่ผ่าน (FALSE): `skip = true` → หยุด workflow (ไม่มีข้อมูลเลย)

---

### Node 5: Build AI Prompt (Code)

สร้าง system prompt + user prompt ภาษาไทยส่งให้ AI วิเคราะห์:

```
System: "คุณเป็น AI วิศวกรพลังงานอุตสาหกรรม..."
        "ตอบกลับเป็น JSON เท่านั้น ห้ามมี markdown หรือ code block"

User: วิเคราะห์ข้อมูลพลังงาน... (${count} readings)

【กำลังไฟฟ้า】
• Active Power  : เฉลี่ย X kW | สูงสุด X kW | ต่ำสุด X kW
• Reactive Power: เฉลี่ย X kVAr
• Apparent Power: เฉลี่ย X kVA
• Power Factor  : เฉลี่ย X | ต่ำสุด X
• พลังงานใช้ไป : X kWh

【โหลดและกระแส】
• Load     : เฉลี่ย X% | สูงสุด X%
• Current  : เฉลี่ย X A | สูงสุด X A
• Motor RPM: เฉลี่ย X rpm
• Frequency: X Hz

【เหตุการณ์ผิดปกติ】
• Overcurrent Alarm: X ครั้ง (X% ของเวลา)
• Spike Event      : X ครั้ง (X% ของเวลา)
```

---

### Node 6: AI Agent + OpenRouter Chat Model

| Node | ประเภท | รายละเอียด |
|---|---|---|
| `AI Agent` | `@n8n/n8n-nodes-langchain.agent` v3.1 | รับ prompt + ส่งผ่าน LLM |
| `OpenRouter Chat Model` | `@n8n/n8n-nodes-langchain.lmChatOpenRouter` v1 | ใช้ credential `OpenRouter account` |

AI ตอบกลับเป็น JSON (ห้าม markdown):
```json
{
  "reduce_power":   true,
  "reason":         "กำลังไฟฟ้าเฉลี่ยเกิน 7.5 kW",
  "recommendation": "ปรับลดโหลดเครื่องจักร",
  "risk_level":     "medium",
  "summary":        "เครื่องจักร MC-01 ใช้พลังงานสูงกว่าปกติ..."
}
```

---

### Node 7: Parse AI Decision (Code)

รองรับ output format หลายแบบจาก N8N:

```javascript
const rawText =
  resp.choices?.[0]?.message?.content ||  // OpenAI HTTP format
  resp.output ||                           // n8n LangChain / AI Agent ← format ที่ใช้จริง
  resp.text   ||                           // n8n LLM Chain
  resp.message?.content || '';
```

ดึง JSON ออกจาก text ด้วย regex: `rawText.match(/\{[\s\S]*\}/)`

**Output ที่ส่งต่อ:**

| Field | ค่า | คำอธิบาย |
|---|---|---|
| `reduce_power` | boolean | คำสั่งหลัก (true = ECO, false = NORMAL) |
| `reason` | string | สาเหตุที่ AI ตัดสินใจ |
| `recommendation` | string | คำแนะนำการปฏิบัติ |
| `risk_level` | string | `low` / `medium` / `high` |
| `summary` | string | สรุปสถานการณ์ |
| `machine_id` | string | รหัสเครื่องจักร |
| `analyzed_at` | string | เวลาวิเคราะห์ (Bangkok +07:00) |
| `readings_count` | number | จำนวน readings ที่ใช้ |
| `power_avg_kw` | number | ค่าเฉลี่ยกำลังไฟฟ้า |
| `power_max_kw` | number | ค่าสูงสุดกำลังไฟฟ้า |
| `load_avg_pct` | number | โหลดเฉลี่ย |
| `alarm_count` | number | จำนวน overcurrent alarm |
| `spike_count` | number | จำนวน spike event |
| `ai_model` | string | model ที่ใช้ (จาก OpenRouter) |
| `tokens_used` | number | จำนวน tokens |
| `source` | string | `'n8n-openrouter-5min'` |

---

### Node 8: Send Command to Node-RED

```
POST http://nodered:1880/energy-command
Content-Type: application/json
Timeout: 8,000 ms

Body: JSON ทั้งหมดจาก Parse AI Decision
```

---

### Node 9: Log Result to Sheet

- **Spreadsheet:** LogResult
- **Sheet ID:** `1cKT9jznanj2aHwdE1lcrsV0lIx1c_LkU57E9YcHpZPA`
- **Tab:** ชีต1 (gid=0)
- **Credential:** `Google Sheets account` (OAuth2)

**คอลัมน์ที่บันทึก:**

| คอลัมน์ใน Sheet | ค่าที่ map | หมายเหตุ |
|---|---|---|
| `reduce_power` | `$json.reduce_power` | |
| `status` | `$json.status` | |
| `ts` | `$json.ts` | |
| `season` | `Parse AI Decision.reason` | ชื่อคอลัมน์ใน Sheet เป็น "season" แต่เก็บค่า reason |
| `recommendation` | `Parse AI Decision.recommendation` | |
| `summary` | `Parse AI Decision.summary` | |
| `risk_level` | `Parse AI Decision.risk_level` | |

> **หมายเหตุ:** คอลัมน์ชื่อ `season` ใน Google Sheet เก็บค่า `reason` จาก AI — ชื่อคอลัมน์ผิดพลาดจากการตั้งค่าครั้งแรก แต่ระบบทำงานปกติ

---

## 8. Google Sheets (Data Storage)

### Sheet 1 — EnergyLog

| | รายละเอียด |
|---|---|
| **ชื่อ** | EnergyLog |
| **Sheet ID** | `1Oa979YHjGgximaLgiNp--XX4jLZRMgqmuWZJrPpZPaQ` |
| **Tab** | Sheet1 |
| **อัตราข้อมูล** | ทุก 10 วินาที = ~6 rows/นาที = ~360 rows/ชั่วโมง |
| **เขียนโดย** | N8N Workflow 1 (Append) |
| **อ่านโดย** | N8N Workflow 2 (Read all) |

### Sheet 2 — LogResult

| | รายละเอียด |
|---|---|
| **ชื่อ** | LogResult |
| **Sheet ID** | `1cKT9jznanj2aHwdE1lcrsV0lIx1c_LkU57E9YcHpZPA` |
| **Tab** | ชีต1 (gid=0) |
| **อัตราข้อมูล** | ทุก 1 นาที = ~60 rows/ชั่วโมง |
| **เขียนโดย** | N8N Workflow 2 (Append) |

### Credentials ที่ต้องมีใน N8N

| ชื่อ Credential | ประเภท | ใช้ใน |
|---|---|---|
| `Google Sheets account` | Google Sheets OAuth2 | Workflow 1 + Workflow 2 |
| `OpenRouter account` | OpenRouter API | Workflow 2 (AI Agent) |

---

## 9. Dashboard UI (Node-RED)

**URL:** `http://localhost:1880/ui`  
**Tab:** Energy Monitor  
**เฟรมเวิร์ค:** node-red-dashboard v3.6.6

### Group 1: ค่าพลังงาน MC-01

| Widget | ค่าที่แสดง | ช่วง | เกณฑ์สี |
|---|---|---|---|
| Gauge: Active Power | `active_power_kw` (kW) | 0–12 | เขียว: <6 / เหลือง: 6–9 / แดง: >9 |
| Gauge: Power Factor | `power_factor × 100` (%) | 0–100 | แดง: <82 / เหลือง: 82–92 / เขียว: >92 |
| Gauge: Load | `load_pct` (%) | 0–100 | เขียว: <60 / เหลือง: 60–80 / แดง: >80 |
| Gauge: Max Current | `max(l1,l2,l3)` (A) | 0–22 | เขียว: <14 / เหลือง: 14–17.5 / แดง: >17.5 |
| Gauge: Motor RPM | `motor_rpm` | 1000–1500 | liquid style (เหลือง: 1350, แดง: 1450) |
| Text: สถานะ | `status_label` | — | สีแดง + bold เมื่อ alarm/spike |

### Group 2: Power Trend (Line Chart)

- **เส้น 1:** `active_power_kw` (topic: "Power kW")
- **เส้น 2:** `load_pct ÷ 10` (topic: "Load x0.1%") — แบ่ง 10 เพื่อให้อยู่ใน Y-axis เดียวกัน
- **X-axis:** `HH:mm:ss`
- **เก็บข้อมูล:** 120 points สุดท้าย = **5 นาที**
- **Y-axis:** 0–12

### Group 3: ผลวิเคราะห์ AI (อัปเดตทุก 1 นาที)

| Widget | ค่าที่แสดง | ตัวอย่าง |
|---|---|---|
| Power Mode | mode + สี | `🔴 ECO MODE — ลดการใช้พลังงาน` หรือ `🟢 NORMAL — ทำงานปกติ` |
| Risk Level | risk + readings + เวลา | `⚠ Risk: HIGH  │  readings: 6  │  วิเคราะห์: 13:30:00 UTC` |
| สาเหตุ | `reason` จาก AI | |
| คำแนะนำ | `recommendation` จาก AI | |
| สรุปสถานการณ์ | `summary` จาก AI | |

> **หมายเหตุ:** แถว Risk Level แสดงเวลาจาก `analyzed_at` (Bangkok +07:00) แต่ label บอกว่า "UTC" — เป็น bug เล็กน้อยในโค้ด Node-RED ที่ไม่กระทบการทำงาน

---

## 10. AI Decision Logic

### เกณฑ์ที่ AI ใช้ตัดสินใจ (ระบุใน AI Prompt)

AI จะ set `reduce_power = true` เมื่อมีเงื่อนไขข้อใดข้อหนึ่ง:

| เงื่อนไข | เกณฑ์ | ความหมาย |
|---|---|---|
| กำลังไฟฟ้าเฉลี่ยสูง | `power_avg > 7.5 kW` | โหลดหนักต่อเนื่อง |
| กำลังไฟฟ้าสูงสุดเกิน | `power_max > 9.0 kW` | มี peak สูง |
| โหลดเฉลี่ยสูง | `load_avg > 75%` | ใกล้เต็มกำลัง |
| โหลดสูงสุดเกิน | `load_max > 85%` | มี peak overload |
| Power Factor ต่ำ | `pf_min < 0.88` | ประสิทธิภาพต่ำ |
| Overcurrent alarm | `alarm_count > 0` | กระแสเกิน 17.5A |
| Spike event | `spike_count > 0` | มีไฟกระชาก |
| กระแสสูงสุดเกิน | `current_max > 18 A` | กระแสอันตราย |

### Risk Level ที่ AI ประเมิน

| ระดับ | สัญลักษณ์ | ความหมาย |
|---|---|---|
| `low` | 🟢 เขียว | ทุกค่าปกติ |
| `medium` | 🟡 เหลือง | พลังงานสูง แต่ไม่มี alarm |
| `high` | 🔴 แดง | มี overcurrent / spike alarm |

### ผลที่เกิดขึ้นใน Simulator

```
reduce_power = true  → Simulator เข้า ECO mode (ค่อยๆ ลดใน ~200 วินาที)
reduce_power = false → Simulator ทำงานปกติ NORMAL mode
```

---

## 11. Data Flow สมบูรณ์

```
╔══════════════════════════════════════════════════════════════════╗
║  ทุก 10 วินาที                                                    ║
║                                                                  ║
║  ┌─────────────────────────────────────────────────────────┐    ║
║  │  Node-RED Simulator (fn_build_payload)                  │    ║
║  │  • อ่าน flow.get('reduce_power')                        │    ║
║  │  • คำนวณ Sine + Lerp + Spike                            │    ║
║  │  • Timestamp Bangkok +07:00                             │    ║
║  └────────────────────────┬────────────────────────────────┘    ║
║                           │                                      ║
║         ┌─────────────────┼──────────────────┐                  ║
║         ▼                 ▼                  ▼                   ║
║  Dashboard UI      Wrap → ngrok         Debug node               ║
║  (Gauges+Chart)    POST webhook                                   ║
║                           │                                      ║
║                    N8N Workflow 1                                 ║
║                    Extract → Append                               ║
║                           │                                      ║
║                    EnergyLog (Sheet1)                             ║
║                    ~6 rows/min                                    ║
╚═══════════════════════════╪══════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════╗
║  ทุก 1 นาที                                                       ║
║                                                                  ║
║  N8N Schedule                                                    ║
║       │                                                          ║
║  Read EnergyLog (ทุก row)                                        ║
║       │                                                          ║
║  Filter 1min + Calc Stats                                        ║
║  • กรอง 1 นาทีล่าสุด                                             ║
║  • fallback: 12 rows ล่าสุด (ถ้าไม่มีข้อมูลใหม่)                ║
║  • คำนวณ avg/max/min/alarm                                       ║
║       │                                                          ║
║  Has Data? (skip = false?)                                       ║
║       │ YES                                                      ║
║  Build AI Prompt (ภาษาไทย)                                       ║
║       │                                                          ║
║  AI Agent → OpenRouter Chat Model                                ║
║  • วิเคราะห์และตัดสินใจ ECO/NORMAL                               ║
║  • ตอบกลับเป็น JSON                                               ║
║       │                                                          ║
║  Parse AI Decision                                               ║
║  • ดึง JSON จาก AI output                                        ║
║  • รองรับหลาย format (OpenAI, LangChain)                         ║
║       │                                                          ║
║  ┌────┴────┐                                                     ║
║  ▼         ▼                                                     ║
║  POST      Log Result                                            ║
║  nodered:  → LogResult                                           ║
║  1880/     (ชีต1)                                                ║
║  energy-                                                         ║
║  command                                                         ║
║  │                                                               ║
║  flow.set('reduce_power')                                        ║
║  Dashboard AI Panel อัปเดต                                       ║
║  Simulator ปรับ mode ทีละ step (~200s)                           ║
╚══════════════════════════════════════════════════════════════════╝
```

---

## 12. การตั้งค่าระบบใหม่ (Setup)

### ขั้นตอนที่ 1 — เตรียม Environment

```bash
# คัดลอก template
cp .env.example .env

# แก้ไข .env ใส่ค่าจริง
# - CLOUDFLARE_TUNNEL_TOKEN: จาก Cloudflare Zero Trust Dashboard
# - N8N_DOMAIN: โดเมนที่ตั้งใน Cloudflare (เช่น n8n.yourdomain.com)
# - N8N_ENCRYPTION_KEY: openssl rand -hex 16
# - POSTGRES_PASSWORD, INFLUXDB_*, GRAFANA_*: ตั้ง password ที่แข็งแกร่ง
```

### ขั้นตอนที่ 2 — เริ่ม Docker Stack

```bash
docker compose up -d
docker compose ps   # ตรวจสอบทุก service ต้อง running
```

### ขั้นตอนที่ 3 — Import Node-RED Flow

1. เปิด `http://localhost:1880`
2. ☰ (เมนู) → **Import** → เลือกไฟล์ `flows/NodeRED flowsEnergy Test N8N.json`
3. กด **Deploy**

### ขั้นตอนที่ 4 — ตั้งค่า N8N Credentials

1. เปิด `https://<N8N_DOMAIN>` (ผ่าน Cloudflare) หรือ `http://localhost:5678`
2. สร้าง account และ login
3. เพิ่ม Credentials:
   - **Google Sheets OAuth2** — ชื่อ: `Google Sheets account`
   - **OpenRouter API** — ชื่อ: `OpenRouter account` (รับ key จาก https://openrouter.ai/keys)

### ขั้นตอนที่ 5 — Import N8N Workflow 1

1. N8N → **New Workflow** → ☰ → **Import from file**
2. เลือก `flows/n8n-workflow1-collector.json`
3. เลือก credential: `Google Sheets account`
4. Toggle **Active** (สีเขียว)

### ขั้นตอนที่ 6 — Import N8N Workflow 2

1. Import `flows/n8n-workflow2-analyzer (New).json`
2. เลือก credential: `Google Sheets account` + `OpenRouter account`
3. Toggle **Active**

### ขั้นตอนที่ 7 — เตรียม Google Sheets

> ต้องเปิด N8N ผ่าน `https://<N8N_DOMAIN>` เพื่อทำ OAuth2 Google

**EnergyLog Sheet** (Workflow 1 จะสร้าง/เติม row อัตโนมัติ):
- ต้องมีแถว header ใน Sheet1 ชื่อคอลัมน์ตามฟิลด์ในตาราง Section 6

**LogResult Sheet** (Workflow 2 จะสร้าง/เติม row อัตโนมัติ):
- ต้องมีแถว header ใน ชีต1 คอลัมน์: `reduce_power`, `status`, `ts`, `season`, `recommendation`, `summary`, `risk_level`

**Google OAuth2 Redirect URI** (ใส่ใน Google Console):
```
https://<N8N_DOMAIN>/rest/oauth2-credential/callback
```

### ขั้นตอนที่ 8 — ตรวจสอบการทำงาน

```bash
# 1. ดู Node-RED debug panel → ควรเห็น kW + status ทุก 10 วินาที
# 2. ดู N8N Executions → Workflow 1 ควรทำงานทุก ~10 วินาที
# 3. เปิด Google Sheets → ควรเห็น row ใหม่เพิ่มเรื่อยๆ
# 4. หลัง 1 นาที → N8N Workflow 2 ควรทำงาน
# 5. ดู Dashboard http://localhost:1880/ui
# 6. ตรวจ Cloudflare Tunnel: docker compose logs -f cloudflared
```

---

## 13. การแก้ปัญหาที่พบบ่อย

### ปัญหา: N8N webhook ไม่รับข้อมูล

```
Error: webhook "energy-machine-telemetry" is not registered
```

**สาเหตุ:** Workflow ยังไม่ได้ Activate  
**แก้ไข:** N8N → Workflow → Toggle เป็น **Active** (สีเขียว)

---

### ปัญหา: Node-RED ส่ง HTTP Response ไม่ได้ (timeout / No response object)

```
[http response] No response object
ECONNABORTED: timeout of 10000ms exceeded
```

**สาเหตุ:** `fn_store_cmd` สร้าง object ใหม่แทน `msg` → ทำให้ `msg.res` (HTTP handle) หาย  
**แก้ไข:**
```javascript
// ✅ ถูกต้อง — ใช้ msg ตัวเดิม
msg.statusCode = 200;
msg.payload = { status: 'ok', reduce_power: reducePower };
return [msg, uiMsg];

// ❌ ผิด — msg.res หายไป
const httpResp = { statusCode: 200, payload: { status: 'ok' } };
return [httpResp, uiMsg];
```

---

### ปัญหา: http in URL ผิด

**สาเหตุ:** Node-RED `http in` node บันทึก URL เป็น full URL  
**แก้ไข:** ต้องเป็น **path เท่านั้น**: `/energy-command`  
(ไม่ใช่ `http://nodered:1880/energy-command`)

---

### ปัญหา: N8N ติดต่อ Node-RED ไม่ได้ (ECONNABORTED)

```
ECONNABORTED: The connection was aborted
```

**สาเหตุ:** ใช้ `host.docker.internal` หรือ `localhost` ซึ่งไม่ทำงานใน Linux Docker  
**แก้ไข:** ใช้ชื่อ container: `http://nodered:1880/energy-command`

---

### ปัญหา: Filter 1min ไม่เจอข้อมูล (skip = true)

**สาเหตุ:** ข้อมูลล่าสุดใน Sheet เก่ากว่า 1 นาที (หยุด Node-RED หรือกำลัง test)  
**แก้ไข:** ระบบมี fallback อัตโนมัติ — ถ้าไม่มีข้อมูลใน 1 นาที จะใช้ **12 rows ล่าสุด**  
ดูได้จาก field `used_fallback: true` ใน Workflow 2

---

### ปัญหา: Timestamp ผิด timezone (เป็น UTC แทน Bangkok)

**สาเหตุ:** `new Date().toISOString()` คืนค่า UTC เสมอ  
**แก้ไข:**
```javascript
const ts = new Date(Date.now() + 7*60*60*1000).toISOString().replace('Z', '+07:00');
// ผลลัพธ์: "2026-04-19T20:30:00.000+07:00"
```

---

### ปัญหา: Parse AI response ไม่ได้ (ได้ค่า default)

**สาเหตุ:** AI Node (LangChain) คืนค่าใน field `output` ไม่ใช่ `choices[0].message.content`  
**แก้ไข:** ตรวจสอบว่า Parse AI Decision node ใช้ fallback chain:
```javascript
const rawText =
  resp.choices?.[0]?.message?.content ||   // OpenAI HTTP
  resp.output ||                            // n8n LangChain ← ใช้ format นี้
  resp.text   ||
  resp.message?.content || '';
```

---

### ปัญหา: flows.json ถูก overwrite หลัง Deploy ใน Node-RED UI

**สาเหตุ:** การกด Deploy ใน Node-RED จะเขียนทับ `/data/flows.json` เสมอ  
**แก้ไข:** ถ้าแก้ไขไฟล์ตรงๆ ต้องทำก่อน Deploy หรือ restart nodered container ก่อนที่ UI จะ Deploy

---

### ปัญหา: N8N เข้าถึงจาก internet ไม่ได้

**สาเหตุ:** Cloudflare Tunnel ยังไม่ได้รับการตั้งค่า หรือ Nginx Proxy Manager ยังไม่มี Proxy Host  
**แก้ไข:**
1. ตรวจ: `docker compose logs cloudflared` — ต้องไม่มี error
2. ตรวจว่า Nginx Proxy Manager (http://localhost:81) มี Proxy Host สำหรับ `<N8N_DOMAIN>` → `n8n:5678`
3. ตรวจ Cloudflare Dashboard ว่า Public Hostname ชี้ไปที่ `http://nginx-proxy-manager:80`

---

*คู่มือนี้จัดทำจากโค้ดจริงใน `flows/` | อัปเดตล่าสุด: 16 พฤษภาคม 2569 (2026)*
