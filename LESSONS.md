# Node-RED Workshop — คู่มือการเรียนรู้ 6 บทเรียน

> ระดับ: เริ่มต้น → กลาง → ประยุกต์ใช้งาน IoT จริง

---

## สิ่งที่ต้องเตรียม

| รายการ | รายละเอียด |
|--------|-----------|
| Node-RED | http://localhost:1880 (รัน Docker แล้ว) |
| MQTT Broker | Mosquitto ที่ port 1883 (มีใน Docker) |
| node-red-dashboard | ติดตั้งก่อน Lesson 5-6 |
| node-red-contrib-modbus | ติดตั้งก่อน Lesson 6 ส่วน C |

### วิธีติดตั้ง Package เพิ่มเติม

1. เปิด Node-RED → เมนู `≡` (มุมบนขวา) → **Manage Palette**
2. แท็บ **Install** → ค้นหาชื่อ package → กด **Install**
3. รอ restart อัตโนมัติ

---

## วิธี Import Flow เข้า Node-RED

```
Menu ≡ → Import → เลือกไฟล์ flows/lessons/lessonX-xxx.json → Import
```

หรือ copy เนื้อหาไฟล์ทั้งหมด แล้ว paste ในหน้าต่าง Import

> **หมายเหตุ Docker:** MQTT broker hostname ควรเป็น `mosquitto`
> แก้ได้ที่ node `mqtt-broker` → ดับเบิ้ลคลิก → เปลี่ยน Server จาก `localhost` → `mosquitto`

---

## ภาพรวม 6 บทเรียน

```
L1: Inject → Debug         — เข้าใจ message flow พื้นฐาน
L2: Function Node          — เขียน JavaScript ใน Node-RED
L3: HTTP Request           — เรียก REST API จากภายนอก
L4: MQTT Pub/Sub           — สื่อสาร IoT ผ่าน MQTT Broker
L5: Dashboard              — แสดงผลด้วย Gauge, Chart, Button
L6: Modbus PLC Simulator   — จำลองการอ่านข้อมูล PLC จริง
```

---

## Lesson 1 — Inject → Debug (Hello World)

**ไฟล์:** `flows/lessons/lesson1-inject-debug.json`

### วัตถุประสงค์
- เข้าใจโครงสร้าง message (`msg`) ใน Node-RED
- รู้จัก `msg.payload`, `msg.topic`
- เข้าใจ data type ต่างๆ ที่ Node-RED รองรับ

### แผนผัง Flow

```
[Inject String  ] ─┐
[Inject Number  ] ─┤
[Inject Boolean ] ─┼─► [Debug Node]
[Inject JSON    ] ─┤
[Inject Timestamp]─┘
```

### Node ที่ใช้

| Node | หน้าที่ |
|------|---------|
| **Inject** | ปุ่มส่ง message เข้า flow — ตั้งค่า payload ได้เป็น string/number/JSON/timestamp |
| **Debug** | แสดงผล message ใน Debug Panel ด้านขวา |

### ขั้นตอนการทดลอง

1. Import flow แล้วกด **Deploy** (ปุ่มแดงบนขวา)
2. เปิด **Debug Panel** — คลิกไอคอนแมลงสาบ 🐛 ด้านขวา
3. กดปุ่ม ► หน้า Inject node แต่ละอัน
4. สังเกตผลใน Debug Panel:

```
① String  → msg.payload: "Hello, Node-RED! สวัสดีโลก"   (type: string)
② Number  → msg.payload: 42                              (type: number)
③ Boolean → msg.payload: true                            (type: boolean)
④ JSON    → msg.payload: { student: "สมชาย", ... }      (type: object)
⑤ Auto    → msg.payload: 1718000000000                   (type: number = Unix ms)
```

### แนวคิดสำคัญ

```
msg = {
    payload: <ข้อมูลหลัก>,
    topic:   "test/string",
    _msgid:  "abc123..."   ← Node-RED สร้างให้อัตโนมัติ
}
```

> **กฎสำคัญ:** ใน Node-RED ทุกอย่างที่วิ่งในสาย wire คือ object ที่ชื่อ `msg`  
> `msg.payload` คือ "กล่องข้อมูล" หลักที่ node รับ-ส่งกัน

### แบบฝึกหัด

1. เพิ่ม Inject node ใหม่ — ตั้ง payload เป็น Array `[1, 2, 3, 4, 5]`
2. เปลี่ยน Debug node ให้แสดงเฉพาะ `msg.payload` (ไม่ใช่ `full msg`)
3. ตั้งให้ Inject ส่งซ้ำทุก 1 วินาที แล้วหยุดหลัง 10 ครั้ง

---

## Lesson 2 — Function Node + msg.payload

**ไฟล์:** `flows/lessons/lesson2-function-payload.json`

### วัตถุประสงค์
- เขียน JavaScript ใน Function node
- แปลง, คำนวณ, และสร้าง payload ใหม่
- ใช้ `return msg`, `node.send()`, และ multiple outputs

### แผนผัง Flow (4 ส่วน)

```
ส่วน A — Math:
[Inject:100] ──► [fn: คำนวณ] ──► [Debug]

ส่วน B — JSON:
[Inject:sensor] ──► [fn: วิเคราะห์] ──► [Debug]

ส่วน C — Conditional (2 outputs):
[Inject:35°C] ──► [fn: if/else] ──► [Debug: ปกติ]
                              └──► [Debug: เตือน!]

ส่วน D — Multi-message:
[Inject] ──► [fn: node.send()] ──► [Debug: รับ 3 ชุด]
```

### Function Node API

```javascript
// รับข้อมูล
var value = msg.payload;       // ข้อมูลขาเข้า
var topic = msg.topic;

// แก้ไขและส่งออก
msg.payload = { result: value * 2 };
return msg;                    // ส่ง output เดียว

// ส่งหลาย output (function ต้องตั้ง outputs = 2)
return [msg, null];            // ส่ง output 1 / ไม่ส่ง output 2
return [null, msg];            // ไม่ส่ง output 1 / ส่ง output 2

// ส่งหลาย message พร้อมกัน
node.send([msg1, msg2]);
return null;                   // ไม่ส่งเพิ่มอีก
```

### Context (เก็บข้อมูลข้ามรอบ)

```javascript
// Flow context — ใช้ร่วมกันใน tab เดียวกัน
flow.set('counter', 0);
var c = flow.get('counter') || 0;

// Global context — ใช้ทุก tab
global.set('config', { threshold: 30 });
var cfg = global.get('config');

// Node context — เฉพาะ node นี้
context.set('lastValue', msg.payload);
```

### แบบฝึกหัด

1. แก้ส่วน B ให้แสดง status เป็น `"HOT"` ถ้า temp > 30, `"COOL"` ถ้า temp < 20, `"OK"` อื่นๆ
2. สร้าง function ที่นับจำนวนครั้งที่รับ message (ใช้ `context.set`)
3. ส่วน D: เพิ่ม sensor D ที่ส่ง timestamp ปัจจุบัน

---

## Lesson 3 — HTTP Request

**ไฟล์:** `flows/lessons/lesson3-http-request.json`

### วัตถุประสงค์
- ดึงข้อมูลจาก REST API ผ่าน HTTP GET / POST
- จัดการ Response และ Status Code
- สร้าง URL แบบ dynamic

### แผนผัง Flow (3 ส่วน)

```
ส่วน A — GET คงที่:
[Inject] ──► [HTTP GET: /todos/1] ──► [fn: แยก field] ──► [Debug]

ส่วน B — GET Dynamic URL:
[Inject:ID=1] ─┐
[Inject:ID=5] ─┴─► [fn: สร้าง URL] ──► [HTTP GET] ──► [fn: parse] ──► [Debug]

ส่วน C — POST:
[Inject:JSON] ──► [HTTP POST: /posts] ──► [Debug]
```

### HTTP Request Node Settings

| ฟิลด์ | ค่า | คำอธิบาย |
|-------|-----|---------|
| Method | GET / POST / PUT / DELETE | HTTP method |
| URL | URL หรือเว้นว่างถ้าใช้ `msg.url` | endpoint |
| Return | `a parsed JSON object` | แปลง response เป็น object อัตโนมัติ |

### URL แบบ Dynamic

```javascript
// ตั้ง msg.url แล้ว HTTP Request node จะใช้ค่านี้แทน URL ที่ config ไว้
msg.url = "https://api.example.com/users/" + msg.payload;
return msg;
```

### ข้อมูลใน msg หลังจาก HTTP Request

```javascript
msg.payload      // response body (object ถ้า parse เป็น JSON)
msg.statusCode   // HTTP status: 200, 404, 500 ...
msg.headers      // response headers
msg.responseUrl  // URL จริงที่เรียก (อาจ redirect)
```

### แบบฝึกหัด

1. ดึงข้อมูล photo จาก `https://jsonplaceholder.typicode.com/photos/1` แล้วแสดง title และ url
2. เพิ่ม error handling: ถ้า `msg.statusCode !== 200` ให้ส่งไปยัง Debug "Error" node
3. สร้าง loop: inject ตัวเลข 1-5 ทีละตัว แล้ว GET user แต่ละคน

---

## Lesson 4 — MQTT Publish/Subscribe

**ไฟล์:** `flows/lessons/lesson4-mqtt-pubsub.json`

### วัตถุประสงค์
- เข้าใจหลักการ Pub/Sub messaging
- ส่งและรับข้อมูลผ่าน MQTT Broker
- เข้าใจ Topic และ Wildcard

### แผนผัง Flow

```
PUBLISHER:
[Inject Manual]─┐
[Inject Auto 5s]─┴─► [fn: สร้าง payload] ──► [MQTT Out: factory/sensor/mc01]
                                         └──► [Debug: ยืนยัน]

SUBSCRIBER:
[MQTT In: factory/sensor/#] ──► [fn: แปลง JSON] ──► [Debug: รับข้อมูล]

ALARM:
[Inject Alarm] ──► [MQTT Out: factory/alarm/mc01]
```

### MQTT Concept

```
Broker (Mosquitto)
    ├── Publisher  ──PUBLISH──► Topic: factory/sensor/mc01
    │                                      │
    └── Subscriber ◄──RECEIVE──────────────┘
                   Subscribe: factory/sensor/#
```

### Topic Structure (แนะนำ)

```
{site}/{type}/{device-id}

ตัวอย่าง:
  factory/sensor/mc01      → ข้อมูล sensor เครื่อง MC-01
  factory/alarm/mc01       → alarm จาก MC-01
  factory/command/mc01     → คำสั่งไปยัง MC-01
  building/floor2/temp     → อุณหภูมิชั้น 2
```

### Wildcard

| Wildcard | ความหมาย | ตัวอย่าง |
|----------|---------|---------|
| `+` | 1 level ใดก็ได้ | `factory/+/mc01` |
| `#` | หลาย level ใดก็ได้ (ท้าย topic) | `factory/#` |

### QoS (Quality of Service)

| QoS | ความหมาย | ใช้เมื่อ |
|-----|---------|--------|
| 0 | At most once (อาจหาย) | ข้อมูล sensor ทั่วไป |
| 1 | At least once (อาจซ้ำ) | คำสั่งสำคัญ |
| 2 | Exactly once | การเงิน, คำสั่ง critical |

### ตั้งค่า Broker สำหรับ Docker

ดับเบิ้ลคลิกที่ MQTT node → แก้ไข Server config:
- **Server:** `mosquitto` (ใน Docker) หรือ `localhost` (standalone)
- **Port:** `1883`

### แบบฝึกหัด

1. เพิ่ม Subscriber ที่ subscribe topic `factory/#` (Wildcard) แล้วแสดง topic และ payload แยกกัน
2. สร้าง "Chat" อย่างง่าย: 2 เครื่อง (หรือ 2 browser tab) ส่งข้อความหากัน
3. เพิ่ม Switch node เพื่อแยก Alarm message ออกจาก Sensor message

---

## Lesson 5 — Dashboard (Gauge, Chart, Button)

**ไฟล์:** `flows/lessons/lesson5-dashboard.json`

### วัตถุประสงค์
- แสดงข้อมูลบนหน้า Dashboard ของ Node-RED
- ใช้ Gauge, Chart, Text, Button, Slider
- เข้าใจโครงสร้าง UI Tab → Group → Widget

> **ต้องติดตั้งก่อน:** `node-red-dashboard` ผ่าน Manage Palette

### Dashboard URL

```
http://localhost:1880/ui
```

### แผนผัง Flow

```
[Inject: ทุก 2 วิ] ──► [fn: simulate sensor] ──► [fn: แจก]
                                                      ├──► [Gauge: Temperature]
                                                      ├──► [Gauge: Humidity]
                                                      ├──► [Gauge: Light]
                                                      ├──► [Chart: History]
                                                      └──► [Text: Sound]

[Button: Reset] ──► [fn: clear] ──► [Chart]
[Slider: Threshold] ──► [fn: set threshold]
```

### โครงสร้าง Dashboard

```
ui_tab "IoT Workshop"
    └── ui_group "Sensor Monitor"
            ├── ui_gauge  (Temperature)
            ├── ui_gauge  (Humidity)
            ├── ui_gauge  (Light — donut style)
            ├── ui_chart  (Temperature History)
            └── ui_text   (Sound Level)
    └── ui_group "Control Panel"
            ├── ui_button (Reset Chart)
            └── ui_slider (Alert Threshold)
```

### Gauge Node Settings

| ฟิลด์ | คำอธิบาย |
|-------|---------|
| Type | `Gauge` (เข็ม), `Donut` (วงกลม), `Compass`, `Level` |
| Min/Max | ช่วงค่า |
| Sectors | สีเปลี่ยนตาม threshold (เขียว/เหลือง/แดง) |
| Format | `{{value}}` = ตัวเลข, `{{value | number:2}}` = ทศนิยม 2 ตำแหน่ง |

### Chart Node Settings

| ฟิลด์ | คำอธิบาย |
|-------|---------|
| Type | Line / Bar / Scatter / Pie |
| X-axis | `HH:mm:ss` = เวลา |
| Remove older than | ลบข้อมูลเก่ากว่า N หน่วยเวลา |
| Max points | จำนวน data point สูงสุด |

### ล้าง Chart

```javascript
// ส่ง [] (array ว่าง) ไปยัง chart เพื่อล้างข้อมูลทั้งหมด
msg.payload = [];
return msg;
```

### แบบฝึกหัด

1. เพิ่ม `ui_led` (ถ้ามีใน palette) แสดงสีเขียว/แดงตาม threshold
2. เพิ่ม `ui_dropdown` ให้เลือก sensor ที่จะแสดงใน chart
3. เปลี่ยน chart เป็น Bar chart แสดงค่าเฉลี่ยรายนาที

---

## Lesson 6 — Modbus TCP + PLC Simulator

**ไฟล์:** `flows/lessons/lesson6-modbus-plc.json`

### วัตถุประสงค์
- จำลองข้อมูลจาก PLC Mitsubishi (P, V, I, Hz)
- ส่งผ่าน MQTT และแสดงบน Dashboard
- เข้าใจ Modbus TCP Register Map
- เชื่อมต่อ Modbus TCP จริงได้

> **ต้องติดตั้งก่อน:**
> - `node-red-dashboard`
> - `node-red-contrib-modbus` (สำหรับส่วน C เท่านั้น)

### แผนผัง Flow

```
ส่วน A — PLC Simulator (ไม่ต้องมี PLC จริง):
[Inject: ทุก 1 วิ] ──► [fn: คำนวณ P,V,I,Hz] ──► [MQTT Out: plc/mc01/data]
                                                ──► [Debug]

Mode Control:
[Inject: NORMAL] ─┐
[Inject: ECO]     ─┴─► [fn: flow.set('plc_mode')]

ส่วน B — Dashboard:
[MQTT In: plc/mc01/data] ──► [fn: แจก] ──► [Gauge: P kW]
                                        ──► [Gauge: V volt]
                                        ──► [Gauge: I amp]
                                        ──► [Gauge: Hz]
                                        ──► [Chart: Power Trend]
                                        ──► [Gauge: PF]

[Button: NORMAL] ─┐
[Button: ECO]     ─┴─► [fn: เปลี่ยน mode]

ส่วน C — Modbus TCP Client (ต้องมี PLC จริง):
[Modbus Read: D0-D3] ──► [fn: แปลง registers] ──► [MQTT Out: plc/mc01/data]
                     └──► [Debug Error]
```

### Modbus Register Map (Mitsubishi PLC)

| Register | ชื่อ D | ข้อมูล | Scaling | ตัวอย่าง |
|----------|--------|--------|---------|---------|
| Address 0 | D0 | Active Power | W × 10 | 35000 = 3500.0 W |
| Address 1 | D1 | Voltage (L-N) | V × 10 | 2200 = 220.0 V |
| Address 2 | D2 | Current | A × 100 | 1590 = 15.90 A |
| Address 3 | D3 | Frequency | Hz × 100 | 5000 = 50.00 Hz |

> FC (Function Code) 03 = Read Holding Registers

### การอ่านค่าจาก Modbus

```javascript
// msg.payload.data = [D0, D1, D2, D3]  (uint16 array)
var regs = msg.payload.data;

var P_kw  = regs[0] / 10000;  // 35000 / 10000 = 3.5 kW
var V_rms = regs[1] / 10;     // 2200  / 10    = 220.0 V
var I_A   = regs[2] / 100;    // 1590  / 100   = 15.90 A
var Hz    = regs[3] / 100;    // 5000  / 100   = 50.00 Hz
```

### ตั้งค่า Modbus Client node

ดับเบิ้ลคลิก **Modbus Read** node → แก้ไข Modbus Client:

```
Type:      TCP
Host:      192.168.1.10   ← IP ของ PLC จริง
Port:      502            ← Default Modbus TCP port
Unit-ID:   1              ← Slave ID ของ PLC
```

### Operating Modes

| Mode | กำลังไฟ | ใช้เมื่อ |
|------|---------|--------|
| **NORMAL** | 5.0 – 9.0 kW | โหลดปกติ |
| **ECO** | 2.0 – 3.5 kW | ประหยัดไฟ |

เปลี่ยน mode ได้จาก:
- กดปุ่ม Inject `NORMAL` / `ECO` ใน flow
- กดปุ่มบน Dashboard

### Dashboard URL

```
http://localhost:1880/ui
→ แท็บ "PLC Monitor"
```

### สูตรไฟฟ้าที่ใช้ในการจำลอง

```
S (kVA) = P (kW) / PF
I (A)   = S × 1000 / (V × √3)       ← 3-phase
Q (kVAR) = S × √(1 - PF²)
```

### แบบฝึกหัด

1. เพิ่ม `ui_text` แสดง Mode ปัจจุบัน (NORMAL/ECO) บน Dashboard
2. เพิ่ม Alarm logic: ถ้า `I_A > 20` ให้ publish ไปที่ `plc/alarm/mc01`
3. เพิ่ม Register D4 = Power Factor (PF × 1000) ใน simulator และอ่านจาก Modbus
4. บันทึกข้อมูลลง Google Sheets โดยส่งผ่าน N8N webhook (ต่อยอดจากโปรเจกต์หลัก)

---

## สรุปโครงสร้าง Files

```
flows/lessons/
├── lesson1-inject-debug.json       L1: Inject → Debug
├── lesson2-function-payload.json   L2: Function Node
├── lesson3-http-request.json       L3: HTTP Request
├── lesson4-mqtt-pubsub.json        L4: MQTT Pub/Sub
├── lesson5-dashboard.json          L5: Dashboard
└── lesson6-modbus-plc.json         L6: Modbus PLC Simulator
```

---

## Quick Reference — Node Types

| Node | ประเภท | หน้าที่ |
|------|--------|---------|
| `inject` | Input | ส่ง message เข้า flow (manual / schedule) |
| `debug` | Output | แสดงผลใน Debug Panel |
| `function` | Process | รัน JavaScript code |
| `change` | Process | เปลี่ยนค่า field ใน msg |
| `switch` | Process | แยก path ตามเงื่อนไข |
| `http request` | Network | เรียก HTTP API |
| `mqtt out` | Network | Publish ไปยัง MQTT Broker |
| `mqtt in` | Network | Subscribe จาก MQTT Broker |
| `ui_gauge` | Dashboard | แสดงตัวเลขแบบมาตรวัด |
| `ui_chart` | Dashboard | กราฟ line/bar |
| `ui_text` | Dashboard | ข้อความ |
| `ui_button` | Dashboard | ปุ่มกด |
| `ui_slider` | Dashboard | แถบเลื่อน |
| `modbus-read` | Modbus | อ่าน Holding Registers จาก PLC |

---

## ปัญหาที่พบบ่อย

| ปัญหา | สาเหตุ | วิธีแก้ |
|-------|--------|---------|
| MQTT ไม่เชื่อมต่อ | hostname ผิด | Docker → `mosquitto`, Standalone → `localhost` |
| Dashboard ไม่โหลด | ยังไม่ได้ติดตั้ง | `node-red-dashboard` ผ่าน Manage Palette |
| Modbus node ไม่มี | ยังไม่ได้ติดตั้ง | `node-red-contrib-modbus` ผ่าน Manage Palette |
| Flow ไม่ทำงาน | ลืม Deploy | กดปุ่ม **Deploy** (แดง) ทุกครั้งที่แก้ไข |
| Debug ไม่แสดง | Debug Panel ปิด | คลิกไอคอน 🐛 ด้านขวา |
| Function error | JavaScript ผิด | ดู error ใน Debug Panel (สีแดง) |
