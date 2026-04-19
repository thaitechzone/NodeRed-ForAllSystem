# คู่มือระบบ Smart Energy Management
## Node-RED + N8N + AI Agent + Google Sheets

> **เวอร์ชัน:** 1.0 | **วันที่:** เมษายน 2569 | **ภาษา:** ไทย

---

## สารบัญ

1. [ภาพรวมระบบ](#1-ภาพรวมระบบ)
2. [สถาปัตยกรรม](#2-สถาปัตยกรรม)
3. [โครงสร้าง Infrastructure (Docker)](#3-โครงสร้าง-infrastructure-docker)
4. [Node-RED Flow — Energy Test → N8N](#4-node-red-flow--energy-test--n8n)
5. [N8N Workflow 1 — Energy Collector](#5-n8n-workflow-1--energy-collector)
6. [N8N Workflow 2 — AI Energy Analyzer](#6-n8n-workflow-2--ai-energy-analyzer)
7. [Google Sheets (Data Storage)](#7-google-sheets-data-storage)
8. [Dashboard UI (Node-RED)](#8-dashboard-ui-node-red)
9. [AI Decision Logic](#9-ai-decision-logic)
10. [Data Flow สมบูรณ์](#10-data-flow-สมบูรณ์)
11. [การตั้งค่าระบบ](#11-การตั้งค่าระบบ)
12. [การแก้ปัญหาที่พบบ่อย](#12-การแก้ปัญหาที่พบบ่อย)

---

## 1. ภาพรวมระบบ

ระบบนี้จำลองการทำงานของเครื่องจักรในโรงงาน (Machine **MC-01**) เพื่อ **ติดตามและวิเคราะห์การใช้พลังงานแบบ Real-time** โดยใช้ AI ตัดสินใจว่าควร **ลดกำลังการทำงาน (ECO Mode)** หรือ **ทำงานปกติ (NORMAL Mode)**

### จุดประสงค์หลัก
- **จำลอง** ข้อมูลพลังงานเครื่องจักรแบบ 3 เฟส ที่สมจริง
- **เก็บข้อมูล** ทุก 10 วินาทีลง Google Sheets อัตโนมัติ
- **วิเคราะห์** ด้วย AI (OpenRouter) ทุก 1 นาที
- **ส่งคำสั่ง** กลับมาควบคุม simulator ผ่าน HTTP API
- **แสดงผล** บน Dashboard แบบ Real-time

---

## 2. สถาปัตยกรรม

```
┌─────────────────────────────────────────────────────────────┐
│                     LOCAL (Docker)                          │
│                                                             │
│  ┌──────────────┐   MQTT    ┌──────────────┐               │
│  │  Mosquitto   │◄─────────►│   Node-RED   │               │
│  │  Port: 1883  │           │  Port: 1880  │               │
│  └──────────────┘           └──────┬───────┘               │
│                                    │ POST (HTTP)            │
│  ┌──────────────┐           ┌──────▼───────┐               │
│  │    ngrok     │◄──tunnel──│     N8N      │               │
│  │  Port: 4040  │           │  Port: 5678  │               │
│  └──────┬───────┘           └──────────────┘               │
└─────────┼───────────────────────────────────────────────────┘
          │ HTTPS
          ▼
   ┌──────────────┐      ┌──────────────────┐
   │   Internet   │      │  Google Sheets   │
   │  (Public URL)│      │  EnergyLog       │
   └──────────────┘      │  LogResult       │
                         └──────────────────┘
                                ▲
                         ┌──────┴───────┐
                         │  OpenRouter  │
                         │  AI Agent    │
                         └──────────────┘
```

### URL ที่ใช้งาน
| บริการ | URL | หมายเหตุ |
|---|---|---|
| Node-RED UI | `http://localhost:1880` | Flow editor |
| Node-RED Dashboard | `http://localhost:1880/ui` | แสดงผล real-time |
| N8N | `http://localhost:5678` | Workflow editor |
| ngrok Dashboard | `http://localhost:4040` | Monitor tunnel |
| ngrok Public | `https://junie-overcredulous-flushedly.ngrok-free.dev` | N8N public URL |

---

## 3. โครงสร้าง Infrastructure (Docker)

### Services ใน docker-compose.yml

| Container | Image | Port | หน้าที่ |
|---|---|---|---|
| `mosquitto` | eclipse-mosquitto:2 | 1883, 9001 | MQTT Broker สำหรับ IoT |
| `nodered` | nodered/node-red:latest | 1880 | Flow automation + Dashboard |
| `n8n` | n8nio/n8n:latest | 5678 | Workflow automation + AI |
| `ngrok` | ngrok/ngrok:latest | 4040 | Tunnel N8N สู่ internet |

### Environment Variables (.env)
```env
TZ=Asia/Bangkok
NGROK_AUTHTOKEN=...
NGROK_DOMAIN=junie-overcredulous-flushedly.ngrok-free.dev
NGROK_URL=https://junie-overcredulous-flushedly.ngrok-free.dev
N8N_ENCRYPTION_KEY=...
```

### Network
- ทุก container อยู่ใน network `iot_network` (bridge)
- Container คุยกันด้วยชื่อ เช่น `http://nodered:1880` และ `mqtt://mosquitto:1883`

---

## 4. Node-RED Flow — Energy Test → N8N

**ไฟล์:** `flows/NodeRED flowsEnergy Test N8N.json`  
**Tab:** Energy Test → N8N

### 4.1 ภาพรวม Flow

```
[Inject 10s] → [สร้าง Payload] ─┬→ [Wrap → N8N] → [POST N8N] → [Debug]
                                  ├→ [แยก Gauges & Chart] → [Dashboard UI]
                                  └→ [Debug Payload]

[POST /energy-command] → [เก็บคำสั่ง] ─┬→ [HTTP 200 OK]
                                         └→ [แยก AI result → UI] → [Dashboard]
```

---

### 4.2 Simulator — สร้าง Energy Payload

**Node:** `fn_build_payload`  
**ทำงานทุก:** 10 วินาที

#### โมเดลการจำลอง

ใช้ **Sine Wave** + **Lerp (Linear Interpolation)** เพื่อให้ค่าสมจริง:

```
sine = sin(t × π / 60)   → คาบ 2 นาที, ช่วง -1 ถึง +1
```

#### โหมดการทำงาน

| พารามิเตอร์ | NORMAL Mode | ECO Mode |
|---|---|---|
| Active Power | 6.1 – 9.5 kW (sine) | 1.7 – 3.3 kW (sine) |
| Load | 56 – 84% | 23 – 41% |
| Current (max) | 11 – 17 A | 4 – 7 A |
| Power Factor | 0.84 – 0.94 | 0.94 – 0.98 |
| Motor RPM | 1,460 – 1,495 | 1,200 – 1,395 (ramp) |

#### คุณสมบัติพิเศษ

**Smooth Transition** — เมื่อ mode เปลี่ยน ค่าจะค่อยๆ เปลี่ยนใน ~100 วินาที (20 steps × 5s)
```
ratio = step / 20    (0 → 1)
base  = lerp(prev, target, ratio)
```

**Spike Event** — โอกาส 10% ใน NORMAL mode จะเกิด surge 1.3–1.8× ทำให้ overcurrent alarm
```
สิ่งที่เกิด: current_max > 17.5A → alarm_overcurrent = true
```

**Voltage Sag** — แรงดันลดตาม load (สมจริง)
```
voltSag = (load_pct - 50) × 0.03 V
```

**Energy Accumulation** — สะสมพลังงานวันนี้
```
energy_today_kwh += activePow × 10/3600   (kWh ต่อ tick 10 วินาที)
```

#### โครงสร้าง Payload ที่ส่ง

```json
{
  "machine_id": "MC-01",
  "ts": "2026-04-19T13:30:00.000+07:00",
  "voltage_v":          { "l1": 230.5, "l2": 229.1, "l3": 231.2 },
  "current_a":          { "l1": 14.2,  "l2": 13.8,  "l3": 14.5 },
  "frequency_hz":       50.02,
  "power_factor":       0.921,
  "active_power_kw":    7.84,
  "reactive_power_kvar":3.21,
  "apparent_power_kva": 8.51,
  "energy_today_kwh":   2.45,
  "motor_rpm":          1477,
  "load_pct":           71.3,
  "alarm_overcurrent":  false,
  "spike_event":        false,
  "power_mode":         "NORMAL",
  "status_label":       "NORMAL",
  "transition_pct":     100,
  "reduce_power_active": false,
  "source":             "node-red-energy-simulator"
}
```

---

### 4.3 HTTP Endpoint — รับคำสั่งจาก N8N

**Node:** `http_in_cmd`  
**Method:** `POST /energy-command`

เมื่อ N8N ส่งผลวิเคราะห์มา:
1. **เก็บ** `reduce_power` ลง flow context (`flow.set('reduce_power', ...)`)
2. **ตอบ** 200 OK ทันที
3. **อัปเดต** Dashboard UI

```javascript
// Simulator อ่านค่านี้ทุก tick
const reducePower = flow.get('reduce_power') || false;
```

---

## 5. N8N Workflow 1 — Energy Collector

**ไฟล์:** `flows/n8n-workflow1-collector.json`  
**ชื่อ:** n8n-workflow1-collector  
**สถานะ:** Active

### Flow

```
[Webhook POST] → [Extract Sheet Row] → [Append to Google Sheet] → [Respond 200]
```

### Node 1: Receive from Node-RED (Webhook)
- **Path:** `/webhook/energy-machine-telemetry`
- **Method:** POST
- **Response Mode:** responseNode (รอจน Respond node)
- **URL สมบูรณ์:** `https://junie-overcredulous-flushedly.ngrok-free.dev/webhook/energy-machine-telemetry`

### Node 2: Extract Sheet Row (Code)

ดึงข้อมูลจาก payload พร้อม **smart path detection** รองรับทุก format:

```javascript
const d = raw.data?.machine_id   ? raw.data        // { event, data: {...} }
        : raw.body?.data          ? raw.body.data   // { body: { data: {...} } }
        : raw.body?.machine_id    ? raw.body        // { body: { machine_id, ... } }
        : raw.machine_id          ? raw             // flat payload
        : raw.data                ? raw.data
        : raw;
```

**ฟิลด์ที่ส่งลง Sheet:**

| ฟิลด์ | ประเภท | คำอธิบาย |
|---|---|---|
| timestamp | string | เวลา Bangkok +07:00 |
| machine_id | string | รหัสเครื่องจักร |
| power_mode | string | NORMAL / ECO |
| status_label | string | NORMAL / ⚡SPIKE / ⚠OVERCURRENT |
| active_power_kw | number | กำลังไฟฟ้าจริง |
| reactive_power_kvar | number | กำลังรีแอคทีฟ |
| apparent_power_kva | number | กำลังปรากฏ |
| power_factor | number | Power Factor (0–1) |
| energy_today_kwh | number | พลังงานสะสมวันนี้ |
| frequency_hz | number | ความถี่ไฟฟ้า |
| load_pct | number | % โหลด |
| motor_rpm | number | รอบมอเตอร์ |
| current_max | number | กระแสสูงสุด 3 เฟส |
| current_l1/l2/l3 | number | กระแสแต่ละเฟส |
| voltage_l1/l2/l3 | number | แรงดันแต่ละเฟส |
| alarm_overcurrent | string | TRUE / FALSE |
| spike_event | string | TRUE / FALSE |

### Node 3: Append to Google Sheet
- **Sheet:** EnergyLog → Sheet1
- **ID:** `1Oa979YHjGgximaLgiNp--XX4jLZRMgqmuWZJrPpZPaQ`
- **Credential:** Google Sheets OAuth2

### Node 4: Respond 200 OK
```json
{ "status": "saved", "ts": "2026-04-19T13:30:00.000+07:00" }
```

---

## 6. N8N Workflow 2 — AI Energy Analyzer

**ไฟล์:** `flows/n8n-workflow2-analyzer (New).json`  
**ชื่อ:** n8n-workflow2-analyzer (New)  
**สถานะ:** Active  
**ทำงาน:** ทุก 1 นาที (cron: `*/1 * * * *`)

### Flow

```
[Schedule 1min] → [Read Sheet] → [Filter 1min + Stats] → [Has Data?]
                                                               │ YES
                                                     [Build AI Prompt]
                                                               │
                                                         [AI Agent]  ← [OpenRouter]
                                                               │
                                                    [Parse AI Decision]
                                                               │
                                              [Send Command → Node-RED]
                                                               │
                                                   [Log Result to Sheet]
```

---

### Node 1: Every 1 Minutes (Schedule Trigger)
- **Cron:** `*/1 * * * *`
- ทำงานทุกนาทีที่ 0 วินาที

### Node 2: Read Energy Log Sheet
- อ่าน **ทุก row** จาก Sheet1 (EnergyLog)
- ส่งต่อเป็น array ของ item

### Node 3: Filter 1min + Calc Stats (Code)

**ขั้นตอน:**
1. กรองเฉพาะ row ที่ timestamp อยู่ในช่วง 1 นาทีที่ผ่านมา
2. ถ้าไม่มีข้อมูล → fallback ใช้ **12 rows ล่าสุด** (~1 นาทีที่ 10s/row)
3. คำนวณสถิติ

**สถิติที่คำนวณ:**

| ฟิลด์ | สูตร |
|---|---|
| power_avg/max/min_kw | avg/max/min ของ active_power_kw |
| pf_avg, pf_min | avg/min ของ power_factor |
| load_avg/max_pct | avg/max ของ load_pct |
| current_avg/max_a | avg/max ของ current_max |
| energy_delta_kwh | energy_last − energy_first |
| alarm_count | จำนวน row ที่ alarm_overcurrent = TRUE |
| spike_count | จำนวน row ที่ spike_event = TRUE |
| alarm_rate_pct | alarm_count / total × 100 |

### Node 4: Has Data? (IF)
- ถ้า `skip = false` → ไปวิเคราะห์ต่อ
- ถ้า `skip = true` → หยุด (ไม่มีข้อมูล)

### Node 5: Build AI Prompt (Code)

สร้าง prompt ภาษาไทยส่งให้ AI วิเคราะห์:

```
【กำลังไฟฟ้า】
• Active Power  : เฉลี่ย X kW | สูงสุด X kW | ต่ำสุด X kW
• Power Factor  : เฉลี่ย X | ต่ำสุด X
• พลังงานใช้ไป : X kWh

【โหลดและกระแส】
• Load     : เฉลี่ย X% | สูงสุด X%
• Current  : เฉลี่ย X A | สูงสุด X A

【เหตุการณ์ผิดปกติ】
• Overcurrent Alarm: X ครั้ง (X% ของเวลา)
• Spike Event      : X ครั้ง (X% ของเวลา)
```

### Node 6: AI Agent (OpenRouter)

- **Type:** `@n8n/n8n-nodes-langchain.agent`
- **Model:** OpenRouter Chat Model (`lmChatOpenRouter`)
- **Credential:** OpenRouter account

AI จะตอบกลับเป็น JSON:
```json
{
  "reduce_power": true,
  "reason": "กำลังไฟฟ้าเฉลี่ยเกิน 7.5 kW",
  "recommendation": "ปรับลดโหลดเครื่องจักร",
  "risk_level": "medium",
  "summary": "เครื่องจักร MC-01 ใช้พลังงานสูง..."
}
```

### Node 7: Parse AI Decision (Code)

รองรับ output format หลายแบบ:
```javascript
const rawText =
  resp.choices?.[0]?.message?.content ||  // OpenAI HTTP
  resp.output ||                           // n8n AI Agent / LangChain
  resp.text   ||                           // n8n LLM Chain
  resp.message?.content || '';
```

**Output ที่ส่งต่อ:**

| ฟิลด์ | คำอธิบาย |
|---|---|
| reduce_power | boolean — คำสั่งหลัก |
| reason | สาเหตุที่ AI ตัดสินใจ |
| recommendation | คำแนะนำการปฏิบัติ |
| risk_level | low / medium / high |
| summary | สรุปสถานการณ์ |
| analyzed_at | เวลาวิเคราะห์ (Bangkok +07:00) |
| readings_count | จำนวน readings ที่ใช้ |
| power_avg_kw | ค่าเฉลี่ยกำลังไฟฟ้า |
| ai_model | model ที่ใช้ |

### Node 8: Send Command to Node-RED

```
POST http://nodered:1880/energy-command
Content-Type: application/json
```

**Body:** ข้อมูลทั้งหมดจาก Parse AI Decision

### Node 9: Log Result to Sheet
- **Sheet:** LogResult → ชีต1
- **ID:** `1cKT9jznanj2aHwdE1lcrsV0lIx1c_LkU57E9YcHpZPA`
- บันทึก: reduce_power, status, ts, reason, recommendation, summary, risk_level

---

## 7. Google Sheets (Data Storage)

### Sheet 1 — EnergyLog (ข้อมูล Telemetry)
**ID:** `1Oa979YHjGgximaLgiNp--XX4jLZRMgqmuWZJrPpZPaQ`  
**Tab:** Sheet1

เก็บทุก reading จาก Node-RED (ทุก 10 วินาที = ~6 rows/นาที = ~360 rows/ชั่วโมง)

### Sheet 2 — LogResult (ผลวิเคราะห์ AI)
**ID:** `1cKT9jznanj2aHwdE1lcrsV0lIx1c_LkU57E9YcHpZPA`  
**Tab:** ชีต1

เก็บผลการวิเคราะห์ทุก 1 นาที ได้แก่ reduce_power, risk_level, reason, recommendation, summary

---

## 8. Dashboard UI (Node-RED)

**URL:** `http://localhost:1880/ui`  
**Tab:** Energy Monitor

### Group 1: ค่าพลังงาน MC-01

| Widget | ค่าที่แสดง | ช่วง | สีเตือน |
|---|---|---|---|
| Gauge: Active Power | active_power_kw | 0–12 kW | เขียว<6, เหลือง6-9, แดง>9 |
| Gauge: Power Factor | power_factor × 100 | 0–100% | แดง<82, เหลือง82-92, เขียว>92 |
| Gauge: Load | load_pct | 0–100% | เขียว<60, เหลือง60-80, แดง>80 |
| Gauge: Max Current | current_max | 0–22 A | เขียว<14, เหลือง14-17.5, แดง>17.5 |
| Gauge: Motor RPM | motor_rpm | 1000–1500 rpm | liquid style |
| Text: สถานะ | status_label | — | แดงเมื่อ alarm/spike |

### Group 2: Power Trend

- **Chart (Line):** Active Power kW + Load÷10 % (2 เส้น)
- แสดง 5 นาทีล่าสุด (120 points)
- X-axis: เวลา HH:mm:ss

### Group 3: ผลวิเคราะห์ AI (1 นาที)

| Widget | ข้อมูล |
|---|---|
| Power Mode | 🔴 ECO MODE / 🟢 NORMAL |
| Risk Level | Risk: HIGH/MEDIUM/LOW + readings count |
| สาเหตุ | reason จาก AI |
| คำแนะนำ | recommendation จาก AI |
| สรุปสถานการณ์ | summary จาก AI |

---

## 9. AI Decision Logic

### เกณฑ์การตัดสินใจ

AI จะ set `reduce_power = true` เมื่อมีเงื่อนไขใดข้อหนึ่งต่อไปนี้:

| เงื่อนไข | เกณฑ์ |
|---|---|
| กำลังไฟฟ้าเฉลี่ยสูง | `power_avg > 7.5 kW` |
| กำลังไฟฟ้าสูงสุดเกิน | `power_max > 9.0 kW` |
| โหลดเฉลี่ยสูง | `load_avg > 75%` |
| โหลดสูงสุดเกิน | `load_max > 85%` |
| Power Factor ต่ำ | `pf_min < 0.88` |
| Overcurrent alarm | `alarm_count > 0` |
| Spike event | `spike_count > 0` |
| กระแสสูงสุดเกิน | `current_max > 18 A` |

### Risk Level

| ระดับ | สี | เงื่อนไข |
|---|---|---|
| low | 🟢 เขียว | ทุกค่าปกติ |
| medium | 🟡 เหลือง | พลังงานสูง แต่ไม่มี alarm |
| high | 🔴 แดง | มี alarm / overcurrent / spike |

### ผลที่เกิดขึ้น

```
reduce_power = true  → Simulator เปลี่ยนเป็น ECO mode (ค่อยๆ ลดใน 100 วินาที)
reduce_power = false → Simulator ทำงานปกติ NORMAL mode
```

---

## 10. Data Flow สมบูรณ์

```
┌──────────────────────────────────────────────────────────────────┐
│  ทุก 10 วินาที                                                    │
│                                                                  │
│  Node-RED Simulator ──────────────────────────────────────────┐  │
│  (fn_build_payload)                                           │  │
│       │                                                       │  │
│       ├──► Dashboard UI (Gauges + Chart)                      │  │
│       │                                                       │  │
│       └──► POST ngrok/webhook/energy-machine-telemetry        │  │
│                          │                                    │  │
│                    N8N Workflow 1                             │  │
│                    Extract → Append                           │  │
│                          │                                    │  │
│                    Google Sheet                               │  │
│                    EnergyLog (Sheet1)  ◄──────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  ทุก 1 นาที                                                       │
│                                                                  │
│  N8N Schedule ──► Read EnergyLog ──► Filter 1min + Stats         │
│                                            │                     │
│                                      Has Data?                   │
│                                            │ YES                 │
│                                      Build AI Prompt             │
│                                            │                     │
│                                    AI Agent (OpenRouter)         │
│                                            │                     │
│                                    Parse AI Decision             │
│                                            │                     │
│                           ┌────────────────┴─────────────┐      │
│                           ▼                               ▼      │
│                   POST /energy-command            Log Result     │
│                   → Node-RED                      → Sheet        │
│                           │                                      │
│                   flow.set('reduce_power')                       │
│                           │                                      │
│                   Dashboard UI อัปเดต                            │
│                   Simulator ปรับ mode                            │
└──────────────────────────────────────────────────────────────────┘
```

---

## 11. การตั้งค่าระบบ

### Credentials ที่ต้องมีใน N8N

| ชื่อ | ประเภท | ใช้ใน |
|---|---|---|
| `Google Sheets account` | Google Sheets OAuth2 | Workflow 1 + 2 |
| `OpenRouter account` | openRouterApi | Workflow 2 |

### การ Deploy ระบบ

```bash
# 1. เริ่ม Docker stack
cd d:\NodeRed
docker compose up -d

# 2. ตรวจสอบ services
docker compose ps

# 3. ดู logs
docker logs nodered --tail 20
docker logs n8n --tail 20
```

### การ Import Flows

**Node-RED:**
1. เปิด `http://localhost:1880`
2. ☰ → Import → เลือกไฟล์ `NodeRED flowsEnergy Test N8N.json`
3. กด Deploy

**N8N Workflow 1:**
1. เปิด `http://localhost:5678`
2. New Workflow → Import → เลือก `n8n-workflow1-collector.json`
3. เลือก credential Google Sheets → Activate

**N8N Workflow 2:**
1. Import `n8n-workflow2-analyzer (New).json`
2. เลือก credential Google Sheets + OpenRouter → Activate

---

## 12. การแก้ปัญหาที่พบบ่อย

### ปัญหา: N8N webhook ไม่รับข้อมูล
```
Error: webhook "energy-machine-telemetry" is not registered
```
**สาเหตุ:** Workflow ยังไม่ได้ Activate  
**แก้ไข:** N8N → Workflow → Toggle เป็น Active

---

### ปัญหา: Node-RED ส่ง command กลับไม่ได้ (timeout)
```
ECONNABORTED: timeout of 10000ms exceeded
```
**สาเหตุ:** `http response` node ไม่ได้รับ `msg.res`  
**แก้ไข:** function node ที่ feed http response ต้องคืน `msg` ตัวเดิม ไม่สร้าง object ใหม่
```javascript
// ✅ ถูกต้อง
msg.statusCode = 200;
msg.payload = { status: 'ok' };
return [msg, uiMsg];

// ❌ ผิด — msg.res หาย
const httpResp = { statusCode: 200, payload: { status: 'ok' } };
return [httpResp, uiMsg];
```

---

### ปัญหา: http in URL ผิด
**สาเหตุ:** Node-RED `http in` node ถูกบันทึก URL เป็น full URL  
**แก้ไข:** ต้องเป็น path เท่านั้น: `/energy-command` (ไม่ใช่ `http://nodered:1880/energy-command`)

---

### ปัญหา: Filter 1min ไม่เจอข้อมูล
**สาเหตุ:** ข้อมูลล่าสุดใน Sheet เก่ากว่า 1 นาที (Node-RED หยุดส่ง หรือกำลัง test)  
**แก้ไข:** ใช้ fallback — ดึง 12 rows ล่าสุดแทน (`rows.slice(-12)`)

---

### ปัญหา: Timestamp ผิด timezone
**สาเหตุ:** `new Date().toISOString()` คืนค่า UTC เสมอ  
**แก้ไข:**
```javascript
// Bangkok UTC+7
const ts = new Date(Date.now() + 7*60*60*1000).toISOString().replace('Z', '+07:00');
```

---

### ปัญหา: Parse AI response ไม่ได้
**สาเหตุ:** AI Node ใน N8N คืนค่าใน field `output` (LangChain format) ไม่ใช่ `choices[0].message.content`  
**แก้ไข:** ใช้ fallback chain:
```javascript
const rawText =
  resp.choices?.[0]?.message?.content ||
  resp.output ||
  resp.text   ||
  resp.message?.content || '';
```

---

*คู่มือนี้จัดทำจากโค้ดจริงในระบบ | อัปเดตล่าสุด: เมษายน 2569*
