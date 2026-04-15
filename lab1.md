# Lab 1: MQTT Telemetry → Node-RED → InfluxDB → Grafana

> **คอร์ส:** IoT Data Pipeline with Node-RED  
> **ระดับ:** เริ่มต้น–ปานกลาง  
> **เวลาโดยประมาณ:** 60–90 นาที  
> **แพลตฟอร์ม:** Windows 11 + Docker Desktop

---

## วัตถุประสงค์การเรียนรู้

เมื่อทำ Lab นี้สำเร็จ ผู้เรียนจะสามารถ:

1. อธิบาย Data Pipeline: `ESP32 → MQTT → Node-RED → InfluxDB → Grafana` ได้
2. สร้างและตั้งค่า Node-RED flow สำหรับรับข้อมูล MQTT Telemetry
3. บันทึกข้อมูล Time-Series ลง InfluxDB 2.x ด้วย node-red-contrib-influxdb
4. สร้าง Grafana Dashboard แสดงกราฟค่า sensor แบบ Real-time
5. เขียน Flux Query พื้นฐานสำหรับดึงข้อมูลจาก InfluxDB

---

## สถาปัตยกรรม Data Pipeline

```
┌──────────────────┐    MQTT Publish     ┌──────────────────────┐
│   ESP32 Sensor   │ ──────────────────► │   Mosquitto Broker   │
│  (หรือ Inject    │  topic:             │   (Docker container) │
│   Simulate node) │  smartfarm/         │   localhost:1883     │
└──────────────────┘  ESP32-ID/telemetry └──────────┬───────────┘
                                                     │
                                          MQTT Subscribe
                                                     │
                                          ┌──────────▼───────────┐
                                          │       Node-RED       │
                                          │   (localhost:1880)   │
                                          │                      │
                                          │  [MQTT In]           │
                                          │     ↓                │
                                          │  [JSON Parse]        │
                                          │     ↓                │
                                          │  [Format Function]   │
                                          │     ↓                │
                                          │  [InfluxDB Out]      │
                                          └──────────┬───────────┘
                                                     │
                                          HTTP Write (Line Protocol)
                                                     │
                                          ┌──────────▼───────────┐
                                          │      InfluxDB 2.x    │
                                          │   (localhost:8086)   │
                                          │   Bucket: sensors    │
                                          │   Org: iot           │
                                          └──────────┬───────────┘
                                                     │
                                            Flux Query
                                                     │
                                          ┌──────────▼───────────┐
                                          │       Grafana        │
                                          │   (localhost:3000)   │
                                          │   Dashboard          │
                                          └──────────────────────┘
```

### MQTT Payload Format (JSON)

```json
{
    "device": "ESP32-FARM-001",
    "temperature": 28.5,
    "humidity": 65.2,
    "soil_moisture": 42,
    "relay": 0,
    "rssi": -68
}
```

| Field          | Type  | Unit    | คำอธิบาย              |
|----------------|-------|---------|----------------------|
| `device`       | string | —      | Device ID            |
| `temperature`  | float | °C      | อุณหภูมิ             |
| `humidity`     | float | %RH     | ความชื้นสัมพัทธ์     |
| `soil_moisture`| int   | %       | ความชื้นดิน          |
| `relay`        | int   | 0/1     | สถานะรีเลย์          |
| `rssi`         | int   | dBm     | ความแรงสัญญาณ WiFi   |

---

## สิ่งที่ต้องเตรียม (Prerequisites)

### ✅ ระบบที่ต้องรันก่อนเริ่ม Lab

```bash
# ตรวจสอบ services ทั้งหมด
docker compose ps
```

ต้องเห็น status `Up (healthy)` หรือ `Up` สำหรับ:

| Service   | Port  | สถานะที่ต้องการ |
|-----------|-------|----------------|
| influxdb  | 8086  | Up (healthy)   |
| grafana   | 3000  | Up             |
| mosquitto | 1883  | Up (healthy)   |
| nodered   | 1880  | Up             |

ถ้ายังไม่ได้รัน:
```bash
cd d:\NodeRed
docker compose up -d
```

### ✅ ข้อมูลที่ต้องมี

เปิดไฟล์ `.env` เพื่อดูค่าที่จะใช้:

```env
INFLUXDB_TOKEN=<your-token>     # จะใช้ใน Node-RED config
INFLUXDB_ORG=iot                # Organization
INFLUXDB_BUCKET=sensors         # Bucket name
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<your-password>
```

---

## ขั้นตอนที่ 1 — ติดตั้ง node-red-contrib-influxdb

Node-RED ต้องการ package เพิ่มเติมเพื่อเขียนข้อมูลลง InfluxDB

### วิธีที่ 1: ผ่าน Node-RED UI (แนะนำ)

1. เปิด Node-RED: [http://localhost:1880](http://localhost:1880)
2. คลิก เมนู ☰ (มุมขวาบน) → **Manage palette**
3. คลิก tab **Install**
4. ค้นหา: `node-red-contrib-influxdb`
5. คลิก **Install** → รอ 1–2 นาที
6. คลิก **Close** เมื่อติดตั้งเสร็จ

### วิธีที่ 2: ผ่าน Terminal

```bash
docker exec nodered npm install node-red-contrib-influxdb --prefix /data
docker restart nodered
```

### ตรวจสอบการติดตั้ง

ใน Node-RED palette (ด้านซ้าย) ต้องเห็น node ชื่อ:
- `influxdb out` — สำหรับเขียนข้อมูล
- `influxdb in` — สำหรับอ่านข้อมูล (query)
- `influxdb batch` — สำหรับเขียนแบบ batch

---

## ขั้นตอนที่ 2 — Import Node-RED Flow

### 2.1 Import Flow จากไฟล์

1. เปิด Node-RED: [http://localhost:1880](http://localhost:1880)
2. คลิก ☰ → **Import**
3. คลิก **select a file to import**
4. เลือกไฟล์: `d:\NodeRed\flows\lab1-mqtt-influxdb-grafana.json`
5. คลิก **Import**

จะได้ Flow tab ชื่อ **"Lab1: MQTT→InfluxDB→Grafana"**

### 2.2 โครงสร้าง Flow ที่ได้

```
[Simulate ESP32]──────┐
[Random Sensor]──────►[Parse JSON]──►[Format for InfluxDB]──►[Write to InfluxDB]
[MQTT In: smartfarm/+/telemetry]──┘
                           │                    │
                     [Debug: Raw]         [Debug: Payload]

[Catch Errors]──►[Error Log]
```

### 2.3 ตั้งค่า InfluxDB Connection

1. ดับเบิ้ลคลิกที่ node **"Write to InfluxDB"**
2. คลิกไอคอน ✏️ ถัดจาก **Server**
3. กรอกข้อมูล:

| ฟิลด์    | ค่า                         |
|----------|-----------------------------|
| Version  | 2.0                         |
| URL      | `http://influxdb:8086`      |
| Token    | `<ค่าจาก .env INFLUXDB_TOKEN>` |

4. คลิก **Update** → **Done**
5. ตรวจสอบ:
   - **Org:** `iot`
   - **Bucket:** `sensors`

### 2.4 ตั้งค่า MQTT Broker Connection

1. ดับเบิ้ลคลิกที่ node **"MQTT: smartfarm/+/telemetry"**
2. คลิกไอคอน ✏️ ถัดจาก **Server**
3. ตรวจสอบค่า:
   - **Server:** `mosquitto`
   - **Port:** `1883`
4. คลิก **Update** → **Done**

### 2.5 Deploy Flow

คลิกปุ่ม **Deploy** (สีแดง มุมขวาบน)

---

## ขั้นตอนที่ 3 — ทดสอบ Flow (Simulation Mode)

### 3.1 เปิด Debug Panel

1. คลิกไอคอน 🐛 Debug (แถบขวามือ) หรือกด `Ctrl+G, D`

### 3.2 ทดสอบด้วย Inject Node

1. คลิกปุ่ม ▶️ (สามเหลี่ยม) ทางซ้ายของ node **"Simulate ESP32 Telemetry"**
2. ดู Debug panel — จะเห็นข้อมูล 2 รายการ:

**Debug 1 — Raw Payload:**
```json
{
    "device": "ESP32-FARM-001",
    "temperature": 28.5,
    "humidity": 65.2,
    "soil_moisture": 42,
    "relay": 0,
    "rssi": -68
}
```

**Debug 2 — InfluxDB Payload:**
```json
[
    {
        "measurement": "sensor_data",
        "tags": { "device": "ESP32-FARM-001", "location": "farm" },
        "fields": {
            "temperature": 28.5,
            "humidity": 65.2,
            "soil_moisture": 42,
            "relay": 0,
            "rssi": -68
        }
    }
]
```

### 3.3 ตรวจสอบ Status บน Node

หลัง inject สำเร็จ node **"Format for InfluxDB"** จะแสดง status:
```
● ESP32-FARM-001 T:28.5°C H:65.2%
```

ถ้าเห็น status สีเขียว = ข้อมูลถูกส่งไป InfluxDB แล้ว

### 3.4 เปิด Auto-Simulate ทุก 5 วินาที

node **"Simulate ESP32 Telemetry"** ตั้ง repeat ทุก 5 วินาที อยู่แล้ว  
ปล่อยให้รันสะสมข้อมูลอย่างน้อย 1–2 นาทีก่อนไปขั้นตอนถัดไป

---

## ขั้นตอนที่ 4 — ตรวจสอบข้อมูลใน InfluxDB

### 4.1 เข้า InfluxDB Data Explorer

1. เปิด: [http://localhost:8086](http://localhost:8086)
2. Login: ใช้ username/password จาก `.env`
3. คลิก **Data Explorer** (ไอคอนกราฟ ด้านซ้าย)

### 4.2 Query ด้วย Script Editor (Flux)

1. คลิก **Script Editor** (มุมขวาบน)
2. พิมพ์ query:

```flux
from(bucket: "sensors")
  |> range(start: -10m)
  |> filter(fn: (r) => r._measurement == "sensor_data")
  |> filter(fn: (r) => r._field == "temperature" or r._field == "humidity")
```

3. คลิก **Run** (หรือ `Ctrl+Enter`)
4. ต้องเห็นข้อมูลในตาราง

### 4.3 Query เฉพาะ Device

```flux
from(bucket: "sensors")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "sensor_data")
  |> filter(fn: (r) => r.device == "ESP32-FARM-001")
  |> filter(fn: (r) => r._field == "temperature")
  |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)
```

### 4.4 ดู Measurements ที่มีทั้งหมด

```flux
import "influxdata/influxdb/schema"
schema.measurements(bucket: "sensors")
```

---

## ขั้นตอนที่ 5 — สร้าง Grafana Dashboard

### 5.1 เข้า Grafana

1. เปิด: [http://localhost:3000](http://localhost:3000)
2. Login: `admin` / `<GRAFANA_ADMIN_PASSWORD จาก .env>`

### 5.2 ตรวจสอบ Data Source

1. คลิก ☰ → **Connections** → **Data sources**
2. ต้องเห็น **InfluxDB** ที่ configured อยู่แล้ว (auto-provisioned)
3. คลิก **InfluxDB** → **Save & test** → ต้องได้ "datasource is working"

ถ้าไม่มี Data source ให้เพิ่มเอง:
- Type: **InfluxDB**
- Query Language: **Flux**
- URL: `http://influxdb:8086`
- Token: `<INFLUXDB_TOKEN>`
- Organization: `iot`
- Default Bucket: `sensors`

### 5.3 สร้าง Dashboard ใหม่

1. คลิก ☰ → **Dashboards** → **New** → **New dashboard**
2. คลิก **Add visualization**
3. เลือก Data source: **InfluxDB**

### 5.4 Panel 1 — Temperature Graph (Time Series)

**ใน Query Editor เลือก Code mode แล้วพิมพ์:**

```flux
from(bucket: "sensors")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "sensor_data")
  |> filter(fn: (r) => r._field == "temperature")
  |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: false)
  |> yield(name: "temperature")
```

**ตั้งค่า Panel:**
- Visualization: **Time series**
- Panel title: `Temperature (°C)`
- Unit: `Celsius (°C)`
- ใน **Standard options** → Unit → เลือก `Temperature > Celsius (°C)`

### 5.5 Panel 2 — Humidity Graph

คลิก **+ Add panel** แล้วพิมพ์:

```flux
from(bucket: "sensors")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "sensor_data")
  |> filter(fn: (r) => r._field == "humidity")
  |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: false)
  |> yield(name: "humidity")
```

**ตั้งค่า Panel:**
- Panel title: `Humidity (%RH)`
- Unit: `Humidity (%H)`
- Color: สีน้ำเงิน

### 5.6 Panel 3 — Soil Moisture Gauge

```flux
from(bucket: "sensors")
  |> range(start: -5m)
  |> filter(fn: (r) => r._measurement == "sensor_data")
  |> filter(fn: (r) => r._field == "soil_moisture")
  |> last()
```

**ตั้งค่า Panel:**
- Visualization: **Gauge**
- Panel title: `Soil Moisture (%)`
- Min: `0`, Max: `100`
- Thresholds:
  - 0–30: สีแดง (แห้งเกินไป)
  - 30–70: สีเขียว (เหมาะสม)
  - 70–100: สีส้ม (ชื้นเกินไป)

### 5.7 Panel 4 — Device Status Table

```flux
from(bucket: "sensors")
  |> range(start: -5m)
  |> filter(fn: (r) => r._measurement == "sensor_data")
  |> filter(fn: (r) => r._field == "temperature" or r._field == "humidity" or r._field == "rssi")
  |> last()
  |> pivot(rowKey: ["_time", "device"], columnKey: ["_field"], valueColumn: "_value")
```

**ตั้งค่า Panel:**
- Visualization: **Table**
- Panel title: `Device Status (Last 5 min)`

### 5.8 บันทึก Dashboard

1. คลิก 💾 (Save) มุมขวาบน
2. ตั้งชื่อ: `SmartFarm IoT Dashboard`
3. คลิก **Save**

### 5.9 ตั้งค่า Auto-Refresh

1. มุมขวาบน เลือก Time range: **Last 15 minutes**
2. คลิก 🔄 → เลือก **5s** (refresh ทุก 5 วินาที)
3. ดูกราฟอัพเดตแบบ Real-time

---

## ขั้นตอนที่ 6 — ทดสอบกับ MQTT Broker จริง

### 6.1 ส่งข้อมูลผ่าน MQTT CLI (จาก Host)

```bash
# ติดตั้ง mosquitto-clients บน Windows (ถ้ายังไม่มี)
# หรือใช้ผ่าน Docker:
docker run --rm --network nodered_iot_network eclipse-mosquitto:2 \
    mosquitto_pub \
    -h mosquitto \
    -t "smartfarm/ESP32-FARM-001/telemetry" \
    -m '{"device":"ESP32-FARM-001","temperature":30.1,"humidity":58.5,"soil_moisture":35,"relay":0,"rssi":-72}'
```

### 6.2 Subscribe เพื่อ Monitor (Debug)

```bash
docker run --rm --network nodered_iot_network eclipse-mosquitto:2 \
    mosquitto_sub \
    -h mosquitto \
    -t "smartfarm/#" \
    -v
```

### 6.3 ส่งข้อมูลจาก Windows PowerShell (ใช้ mosquitto ที่ติดตั้งบน Host)

```powershell
# ถ้าติดตั้ง Mosquitto บน Windows
mosquitto_pub -h localhost -p 1883 `
    -t "smartfarm/ESP32-FARM-001/telemetry" `
    -m '{"device":"ESP32-FARM-001","temperature":31.2,"humidity":62.0,"soil_moisture":38,"relay":1,"rssi":-65}'
```

---

## Flux Query เพิ่มเติม สำหรับ Grafana

### Query: Average ทุก 1 นาที แยกตาม Device

```flux
from(bucket: "sensors")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "sensor_data")
  |> filter(fn: (r) => r._field == "temperature")
  |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)
  |> group(columns: ["device"])
```

### Query: Max Temperature ในช่วง 1 ชั่วโมง

```flux
from(bucket: "sensors")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "sensor_data")
  |> filter(fn: (r) => r._field == "temperature")
  |> max()
```

### Query: นับจำนวน records ต่อ device

```flux
from(bucket: "sensors")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "sensor_data")
  |> filter(fn: (r) => r._field == "temperature")
  |> group(columns: ["device"])
  |> count()
```

### Query: Alert — Temperature สูงกว่า 35°C

```flux
from(bucket: "sensors")
  |> range(start: -5m)
  |> filter(fn: (r) => r._measurement == "sensor_data")
  |> filter(fn: (r) => r._field == "temperature")
  |> filter(fn: (r) => r._value > 35.0)
  |> last()
```

---

## Troubleshooting

| อาการ | สาเหตุที่เป็นไปได้ | วิธีแก้ |
|------|-------------------|---------|
| InfluxDB node แสดง `error: unauthorized` | Token ไม่ถูกต้อง | ตรวจ INFLUXDB_TOKEN ใน `.env` และ Node-RED config |
| InfluxDB node แสดง `connection refused` | InfluxDB ยังไม่พร้อม | `docker compose ps` — รอให้ status เป็น `healthy` |
| ไม่เห็นข้อมูลใน Data Explorer | Bucket ผิด หรือ range สั้นเกิน | เปลี่ยน range เป็น `-1h` หรือตรวจ bucket name |
| Grafana ไม่มี data | Data source token ผิด | **Save & test** Data source ใน Grafana |
| MQTT In node ไม่เชื่อมต่อ | Broker hostname ผิด | ใช้ `mosquitto` ไม่ใช่ `localhost` (Docker network) |
| Node-RED ไม่มี `influxdb out` node | ยังไม่ได้ติดตั้ง package | ติดตั้ง `node-red-contrib-influxdb` |
| Function node แสดง `missing fields` | Payload ขาด temperature/humidity | ตรวจรูปแบบ JSON payload ให้ครบ field |
| Grafana graph ว่างเปล่า | Time range ไม่ครอบคลุมข้อมูล | เปลี่ยนเป็น "Last 15 minutes" หรือ "Last 1 hour" |

### ตรวจสอบ Logs

```bash
# ดู Node-RED logs
docker compose logs -f nodered

# ดู InfluxDB logs
docker compose logs -f influxdb

# ดู Grafana logs
docker compose logs -f grafana
```

---

## สรุปขั้นตอนทั้งหมด

```
1. docker compose up -d
          │
2. ติดตั้ง node-red-contrib-influxdb
          │
3. Import flow: lab1-mqtt-influxdb-grafana.json
          │
4. ตั้งค่า InfluxDB config node (URL + Token)
          │
5. Deploy flow → ทดสอบด้วย Inject node
          │
6. ตรวจสอบข้อมูลใน InfluxDB Data Explorer
          │
7. สร้าง Grafana Dashboard + Flux Queries
          │
8. Auto-refresh 5s → Real-time monitoring ✅
```

---

## คำถามท้ายบท (Review Questions)

1. **ทำไม** ต้องใช้ hostname `mosquitto` แทน `localhost` ใน Node-RED สำหรับ MQTT broker?

2. **อธิบาย** ความแตกต่างระหว่าง `measurement`, `tags`, และ `fields` ใน InfluxDB

3. **Flux Query** ด้านล่างทำอะไร?
   ```flux
   |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)
   ```

4. **ถ้า** ต้องการเพิ่ม sensor ใหม่ (เช่น CO2) ต้องแก้ไขส่วนใดบ้างของ Flow?

5. **ออกแบบ** Alert rule ใน Grafana ที่จะแจ้งเตือนเมื่ออุณหภูมิสูงกว่า 35°C เป็นเวลาต่อเนื่อง 3 นาที

---

## การทดลองเพิ่มเติม (Extension Activities)

### ระดับ 1 — เพิ่ม Sensor Field
แก้ไข Function node "Format for InfluxDB" เพื่อเพิ่มค่า `battery_voltage` (สร้างข้อมูลจำลองเพิ่มใน Inject node)

### ระดับ 2 — Multi-Device Dashboard
เพิ่ม Inject node จำลองอีก 2 device (ESP32-FARM-002, ESP32-FARM-003) แล้วสร้าง Grafana panel ที่แสดงข้อมูลทุก device ในกราฟเดียวกัน

### ระดับ 3 — Grafana Alert
สร้าง Alert rule ใน Grafana:
- Condition: `temperature > 35`
- Contact point: Email หรือ Webhook

### ระดับ 4 — Real ESP32
Flash firmware `esp32-firmware/` ลง ESP32 จริง:
1. เปิด `esp32-firmware/include/config.h` → แก้ WiFi + MQTT Host
2. Build & Upload ด้วย PlatformIO
3. เปิด Serial Monitor ดู log การเชื่อมต่อ
4. ดูข้อมูลจริงใน Grafana Dashboard

---

## ไฟล์ที่เกี่ยวข้อง

| ไฟล์ | คำอธิบาย |
|------|---------|
| `flows/lab1-mqtt-influxdb-grafana.json` | Node-RED flow สำหรับ import |
| `esp32-firmware/platformio.ini` | PlatformIO project config |
| `esp32-firmware/include/config.h` | WiFi / MQTT / Sensor config |
| `esp32-firmware/src/main.cpp` | ESP32 firmware |
| `esp32-firmware/test/test_payload.py` | Python MQTT simulator (ไม่ต้องใช้ ESP32) |
| `docker-compose.yml` | กำหนด services ทั้งหมด |
| `.env` | ตัวแปรสำคัญ (Token, Password) |
| `grafana/provisioning/datasources/influxdb.yml` | Auto-configure Grafana datasource |

---

*Lab 1 เสร็จสมบูรณ์ — ดำเนินการ Lab 2: MQTT Command & Control ต่อได้*
