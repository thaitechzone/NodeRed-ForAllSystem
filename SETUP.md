# SmartFarm — คู่มือตั้งค่าระบบสมบูรณ์

> **Platform:** Windows 11 Pro | **Working dir:** `d:\NodeRed`  
> **อัปเดตล่าสุด:** 2026-04-10

---

## สารบัญ

1. [สถาปัตยกรรมระบบ](#1-สถาปัตยกรรมระบบ)
2. [สิ่งที่ต้องเตรียม](#2-สิ่งที่ต้องเตรียม)
3. [โครงสร้างไฟล์](#3-โครงสร้างไฟล์)
4. [ขั้นตอนที่ 1 — ติดตั้ง Docker Desktop](#4-ขั้นตอนที่-1--ติดตั้ง-docker-desktop)
5. [ขั้นตอนที่ 2 — ตั้งค่า Cloudflare Tunnel](#5-ขั้นตอนที่-2--ตั้งค่า-cloudflare-tunnel) *(สร้าง Tunnel + config docker-compose)*
6. [ขั้นตอนที่ 3 — ตั้งค่าไฟล์ .env](#6-ขั้นตอนที่-3--ตั้งค่าไฟล์-env)
7. [ขั้นตอนที่ 4 — Start Docker Stack](#7-ขั้นตอนที่-4--start-docker-stack)
8. [ขั้นตอนที่ 5 — ตั้งค่า Public Hostname](#8-ขั้นตอนที่-5--ตั้งค่า-public-hostname)
9. [ขั้นตอนที่ 6 — ตั้งค่า N8N](#9-ขั้นตอนที่-6--ตั้งค่า-n8n)
10. [ขั้นตอนที่ 7 — ตั้งค่า Node-RED](#10-ขั้นตอนที่-7--ตั้งค่า-node-red)
11. [ขั้นตอนที่ 8 — ทดสอบระบบ](#11-ขั้นตอนที่-8--ทดสอบระบบ)
12. [คำสั่งที่ใช้บ่อย](#12-คำสั่งที่ใช้บ่อย)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. สถาปัตยกรรมระบบ

```
ESP32 Device
    │
    │ MQTT (broker.hivemq.com:1883)
    ▼
┌─────────────────────────────────────────────────────┐
│  Docker Stack (d:\NodeRed)                          │
│                                                     │
│  ┌──────────┐   MQTT    ┌───────────┐               │
│  │ Node-RED │◄─────────►│ Mosquitto │               │
│  │  :1880   │           │   :1883   │               │
│  └────┬─────┘           └───────────┘               │
│       │ HTTP POST                                   │
│       │ /webhook/smartfarm-*                        │
│       ▼                                             │
│  ┌──────────┐           ┌─────────────┐             │
│  │   N8N    │◄──────────│ cloudflared │             │
│  │  :5678   │ HTTP POST │   (tunnel)  │             │
│  └──────────┘           └──────┬──────┘             │
│                                │                   │
└────────────────────────────────│───────────────────┘
                                 │ QUIC/HTTPS
                                 ▼
                      Cloudflare Network
                                 │
                                 ▼
                   https://n8n.thaitechsync.com
```

**หลักการทำงาน:**
1. ESP32 ส่ง telemetry ผ่าน MQTT → Node-RED รับ
2. Node-RED forward ข้อมูลผ่าน HTTP POST → N8N webhook (ผ่าน Cloudflare Tunnel)
3. N8N ตรวจสอบ conditions → ส่งคำสั่ง relay กลับ Node-RED
4. Node-RED publish MQTT → ESP32 ควบคุม relay

---

## 2. สิ่งที่ต้องเตรียม

| รายการ | หมายเหตุ |
|--------|---------|
| Windows 11 Pro | WSL2 required |
| Docker Desktop | ติดตั้งผ่าน winget |
| Cloudflare Account (ฟรี) | สมัครที่ dash.cloudflare.com |
| Domain บน Cloudflare | ซื้อที่ Cloudflare Registrar โดยตรง (ง่ายที่สุด) |
| RAM 8 GB+ | แนะนำ |
| Disk ว่าง 5 GB+ | สำหรับ Docker images และ volumes |

---

## 3. โครงสร้างไฟล์

```
d:\NodeRed\
  ├── .env                              ← ตั้งค่าทั้งหมด (ไม่ commit ขึ้น Git)
  ├── .gitignore                        ← ครอบคลุม .env แล้ว
  ├── docker-compose.yml                ← กำหนด services ทั้งหมด
  ├── SETUP.md                          ← เอกสารนี้
  ├── INSTALL.md                        ← คู่มือติดตั้ง Docker + OAuth2
  ├── N8NAutomation.md                  ← คู่มือ N8N Automation + Webhook
  ├── ESP32MQTTTester.md                ← คู่มือทดสอบ MQTT
  ├── mosquitto\
  │     └── config\
  │           └── mosquitto.conf        ← config MQTT broker
  ├── nodered\
  │     └── settings.js                ← config Node-RED
  └── flows\
        ├── smartfarm-nodered-full.json ← Node-RED flow (ใช้ไฟล์นี้)
        └── n8n-smartfarm-autocontrol.json ← N8N workflow (ใช้ไฟล์นี้)
```

---

## 4. ขั้นตอนที่ 1 — ติดตั้ง Docker Desktop

```bash
winget install Docker.DockerDesktop
```

หลังติดตั้ง:
1. เปิด Docker Desktop
2. Settings → General → เปิด ✅ **Use WSL 2 based engine**
3. Apply & Restart
4. รอจนไอคอน whale หยุดวิ่ง (engine พร้อม)

ตรวจสอบ:
```bash
docker --version
docker compose version
```

---

## 5. ขั้นตอนที่ 2 — ตั้งค่า Cloudflare Tunnel

Cloudflare Tunnel ทำให้ N8N เข้าถึงได้จากอินเทอร์เน็ตโดยไม่ต้องเปิด port — รัน **ใน Docker** อัตโนมัติพร้อมระบบ

### 5.1 ซื้อ Domain บน Cloudflare Registrar

> ซื้อที่ Cloudflare โดยตรง — domain จะอยู่บน Cloudflare DNS อัตโนมัติ ไม่ต้องตั้งค่าเพิ่ม

1. เข้า [dash.cloudflare.com](https://dash.cloudflare.com) → สมัคร/Login
2. เมนูซ้าย → **Domain Registration** → **Register Domains**
3. ค้นชื่อ domain ที่ต้องการ เช่น `thaitechsync.com`
4. ซื้อ (ราคา at-cost ไม่บวกกำไร)

### 5.2 สร้าง Tunnel ใน Zero Trust

1. เข้า [one.dash.cloudflare.com](https://one.dash.cloudflare.com)
2. ถ้าถามชื่อ Team → ตั้งชื่อได้เลย เช่น `thaitechzone`
3. เมนูซ้าย → **Networks** → **Tunnels**
4. **+ Create a tunnel** → เลือก **Cloudflared** → ตั้งชื่อ เช่น `n8n-smartfarm` → **Save tunnel**

### 5.3 คัดลอก Tunnel Token

1. หลัง Save tunnel → หน้า **Install connector** → เลือก **Docker**
2. จะเห็น command:
   ```
   docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run \
     --token eyJhIjoixxxxxxxxxxxxxxxx...
   ```
3. **คัดลอกเฉพาะ string หลัง `--token`** (ขึ้นต้นด้วย `eyJ` ยาว ~190+ ตัวอักษร)

> **หมายเหตุ:** Token ที่ถูกต้องขึ้นต้นด้วย `eyJ` เท่านั้น — ไม่ใช่ `cfk_` หรือ UUID สั้น ๆ

### 5.4 cloudflared ใน docker-compose.yml

Token ที่คัดลอกมาจะถูกใช้ใน service `cloudflared` ใน `docker-compose.yml` ดังนี้:

```yaml
cloudflared:
  image: cloudflare/cloudflared:latest
  container_name: cloudflared
  command: tunnel --no-autoupdate run --token ${CLOUDFLARE_TUNNEL_TOKEN}
  restart: unless-stopped
  depends_on:
    n8n:
      condition: service_healthy
  networks:
    - iot_network
```

**ไม่ต้องแก้ไข block นี้** — แค่ใส่ token ใน `.env` แล้ว `docker compose up -d` ก็พร้อมใช้งาน

> **สรุปการทำงาน:**  
> cloudflared อ่าน `CLOUDFLARE_TUNNEL_TOKEN` จาก `.env` → เปิด tunnel ออกไปหา Cloudflare  
> → Cloudflare รับ request จาก `n8n.thaitechsync.com` / `nodered.thaitechsync.com`  
> → ส่งกลับมาตาม tunnel → cloudflared forward ไปที่ `n8n:5678` / `nodered:1880` ใน Docker network

---

## 6. ขั้นตอนที่ 3 — ตั้งค่าไฟล์ .env

เปิดไฟล์ `.env` แล้วแก้ค่าให้ครบ:

```env
# ─── Timezone ────────────────────────────────────────────
TZ=Asia/Bangkok

# ─── Cloudflare Tunnel ───────────────────────────────────
# Token จาก Zero Trust Dashboard (ขึ้นต้นด้วย eyJ...)
CLOUDFLARE_TUNNEL_TOKEN=eyJhIjoixxxxxxxxxxxxxxxxxxxxxxxx...

# URL สาธารณะของ tunnel (subdomain ที่จะตั้งในขั้นตอนที่ 5)
CF_TUNNEL_URL=https://n8n.thaitechsync.com

# ─── N8N ─────────────────────────────────────────────────
# Key สำหรับเข้ารหัส credentials ใน N8N
# ครั้งแรก: ใส่ค่าใดก็ได้ (random string 32+ ตัว)
# ถ้ามี volume เดิม: ต้องตรงกับ key ใน volume (/home/node/.n8n/config)
N8N_ENCRYPTION_KEY=change-this-to-random-32-char-string

# ─── OPC Server ──────────────────────────────────────────
OPC_SERVER_IP=192.168.1.100
OPC_SERVER_PORT=4840
```

> **สำคัญ:** ถ้า N8N เคยรันมาก่อน ให้ตรวจสอบ key จริงจาก volume ก่อน:
> ```bash
> docker run --rm -v nodered_n8n_data:/n8ndata --entrypoint="" alpine sh -c "cat /n8ndata/config"
> ```

---

## 7. ขั้นตอนที่ 4 — Start Docker Stack

```bash
cd d:\NodeRed

# Pull images ล่าสุด
docker compose pull

# Start ทั้งหมด
docker compose up -d
```

ตรวจสอบ:
```bash
docker compose ps
```

ผลลัพธ์ที่ต้องเห็น:

```
NAME          STATUS
cloudflared   Up X seconds
mosquitto     Up X seconds (healthy)
n8n           Up X seconds
nodered       Up X seconds (healthy)
```

ตรวจสอบ Cloudflare Tunnel เชื่อมต่อสำเร็จ:
```bash
docker logs cloudflared --tail=10
```

ต้องเห็น:
```
INF Starting tunnel tunnelID=xxxx-xxxx-xxxx
INF Registered tunnel connection connIndex=0 ... location=bkk01
INF Registered tunnel connection connIndex=1 ... location=bkk01
```

---

## 8. ขั้นตอนที่ 5 — ตั้งค่า Public Hostname

ทำครั้งเดียวหลังสร้าง tunnel:

1. [one.dash.cloudflare.com](https://one.dash.cloudflare.com) → **Networks → Tunnels**
2. คลิก **3 จุด (...)** ข้างชื่อ tunnel → **Edit**
3. แท็บ **Public Hostname** → **Add a public hostname**
4. กรอก:

| Field | ค่า |
|-------|-----|
| Subdomain | `n8n` |
| Domain | `thaitechsync.com` |
| Type | `HTTP` |
| URL | `n8n:5678` |

5. **Save**

> **ทำไมใช้ `n8n:5678` ไม่ใช่ `localhost:5678`**  
> cloudflared อยู่ใน Docker network เดียวกับ n8n — Docker DNS resolve ชื่อ `n8n` ได้โดยตรง  
> `localhost` ใน cloudflared container หมายถึงตัว cloudflared เอง ไม่ใช่ n8n

---

## 9. ขั้นตอนที่ 6 — ตั้งค่า N8N

### 9.1 เข้า N8N ครั้งแรก

เปิด browser ไปที่:
```
https://n8n.thaitechsync.com
```

สร้างบัญชี Admin ครั้งแรก (email + password)

> **หมายเหตุ:** เข้าผ่าน `https://n8n.thaitechsync.com` เสมอ — ไม่ใช่ `localhost:5678`  
> เพราะ `WEBHOOK_URL` และ `N8N_EDITOR_BASE_URL` ถูกตั้งไว้เป็น CF Tunnel URL

### 9.2 Import Workflow

1. คลิก **+** (Add workflow) มุมบนซ้าย
2. คลิก **⋮** (สามจุด) มุมบนขวา → **Import from file**
3. เลือกไฟล์: `flows/n8n-smartfarm-autocontrol.json`
4. Workflow จะปรากฏบน canvas ชื่อ **"SmartFarm ESP32 — Auto Relay Control"**

### 9.3 Activate Workflow

คลิก Toggle **Inactive → Active** มุมบนขวา (เปลี่ยนเป็นสีน้ำเงิน/เขียว)

> **สำคัญ:** Webhook จะรับข้อมูลได้เฉพาะตอน **Active** เท่านั้น  
> Test mode ใช้ได้แค่ 1 ครั้งหลังกด "Execute workflow"

### 9.4 Webhook URLs ที่พร้อมใช้งาน

| Webhook | URL |
|---------|-----|
| Telemetry | `https://n8n.thaitechsync.com/webhook/smartfarm-telemetry` |
| Status | `https://n8n.thaitechsync.com/webhook/smartfarm-status` |

---

## 10. ขั้นตอนที่ 7 — ตั้งค่า Node-RED

### 10.1 Login Node-RED

เปิด [http://localhost:1880](http://localhost:1880) จะเห็นหน้า Login:

| Field | ค่า |
|-------|-----|
| Username | `admin` |
| Password | `admin1234` |

> **เปลี่ยน password:** แก้ไขไฟล์ `nodered/settings.js` — ต้อง generate bcrypt hash ใหม่ก่อน  
> ```bash
> docker exec nodered node -e "const bcrypt = require('bcryptjs'); bcrypt.hash('NEW_PASSWORD', 8, (e,h) => console.log(h));"
> ```  
> นำ hash ที่ได้ไปแทนค่า `password` ใน `adminAuth` แล้ว `docker restart nodered`

### 10.2 Import Flow

1. เข้า [http://localhost:1880](http://localhost:1880) → Login
2. เมนู **☰** → **Import**
3. เลือกไฟล์: `flows/smartfarm-nodered-full.json`
4. Import → **Deploy** (ปุ่มแดงมุมบนขวา)

### 10.3 Flow ที่ Import มีอะไรบ้าง

```
Section 1: SUBSCRIBE (รับจาก ESP32)
  [SUB: Telemetry] → [Debug] + [POST → N8N Telemetry]
  [SUB: Status]    → [Debug] + [POST → N8N Status]

Section 2: รับคำสั่ง Auto-Control จาก N8N
  [HTTP In: POST /smartfarm/relay-control]
    → [Validate & Format Relay Command]
      → Output 1: [PUB: Control → ESP32]  (MQTT)
      → Output 2: [HTTP Response → N8N]   (200 OK)

Section 3: PUBLISH Manual (ปุ่มทดสอบ)
  [ALL ON] [ALL OFF] [Pump ON] [Fan ON] [Heater ON]
    → [PUB: Control → ESP32]
```

### 10.4 HTTP Request URLs (ตั้งไว้แล้ว)

Flow ใช้ URLs เหล่านี้ส่งข้อมูลไป N8N:
- `https://n8n.thaitechsync.com/webhook/smartfarm-telemetry`
- `https://n8n.thaitechsync.com/webhook/smartfarm-status`

ไม่ต้องแก้ไขอะไรเพิ่ม — พร้อมใช้งานทันทีหลัง Deploy

---

## 11. ขั้นตอนที่ 8 — ทดสอบระบบ

### 11.1 ตรวจสอบ Services

```bash
docker compose ps
```

ทุกตัวต้อง `Up` และ cloudflared ต้องไม่ `Restarting`

### 11.2 ทดสอบ Tunnel

```bash
curl -sk -o /dev/null -w "HTTP: %{http_code}" https://n8n.thaitechsync.com
# ต้องได้ HTTP: 200
```

### 11.3 ทดสอบ Webhook ด้วย curl

```bash
# ทดสอบ Telemetry (temp สูง + น้ำแห้ง)
curl -X POST https://n8n.thaitechsync.com/webhook/smartfarm-telemetry \
  -H "Content-Type: application/json" \
  -d '{
    "board_id": "ESP32-FARM-001-NATTAPHOL-PALM",
    "timestamp": 100000,
    "rssi": -56,
    "sensors": {
      "water_temp": 26.4,
      "air_temp": 36.5,
      "air_humidity": 70.8,
      "water_overflow": false,
      "water_dry": true
    },
    "relays": {
      "relay1_pump": false,
      "relay2_fan": false,
      "relay3_heater": false
    }
  }'
```

**ผลที่คาดหวัง:**
- N8N ตรวจพบ `air_temp >= 35` → ส่ง Fan ON กลับ Node-RED
- N8N ตรวจพบ `water_dry = true` → ส่ง Pump ON กลับ Node-RED
- Node-RED publish MQTT → ESP32 ทำงาน

### 11.4 ตาราง Checklist

| # | ทดสอบ | ผ่าน/ไม่ผ่าน |
|---|-------|------------|
| 1 | `docker compose ps` ทุก service Up | |
| 2 | `docker logs cloudflared` เห็น `Registered tunnel connection` | |
| 3 | เปิด `https://n8n.thaitechsync.com` ได้ | |
| 4 | N8N workflow สถานะ Active | |
| 5 | curl webhook → N8N execution ปรากฏ | |
| 6 | N8N ส่ง relay command → Node-RED Debug แสดง | |
| 7 | MQTT message ถึง ESP32 | |

---

## 12. คำสั่งที่ใช้บ่อย

```bash
# ── Start / Stop ───────────────────────────────────
docker compose up -d                          # Start ทั้งหมด
docker compose down                           # Stop ทั้งหมด (volumes ยังอยู่)
docker compose down -v                        # Stop + ลบ volumes (ข้อมูลหาย!)

# ── Status & Logs ──────────────────────────────────
docker compose ps                             # ดู status ทุก service
docker compose logs -f                        # ดู logs ทุก service (real-time)
docker compose logs -f cloudflared            # ดู logs เฉพาะ cloudflared
docker compose logs -f n8n                    # ดู logs เฉพาะ n8n
docker stats                                  # ดู CPU/RAM usage

# ── Restart ────────────────────────────────────────
docker compose restart                        # Restart ทุก service
docker compose up -d --force-recreate n8n     # Restart n8n (หลังแก้ .env)
docker compose up -d --force-recreate cloudflared  # Restart tunnel

# ── N8N Encryption Key ─────────────────────────────
# ดู key จริงที่ N8N ใช้อยู่ (กรณี key ไม่ตรง)
docker run --rm -v nodered_n8n_data:/n8ndata --entrypoint="" alpine \
  sh -c "cat /n8ndata/config"
```

---

## 13. Troubleshooting

| ปัญหา | สาเหตุ | วิธีแก้ |
|-------|--------|---------|
| `cloudflared` Restarting | Token ไม่ถูกต้อง | Zero Trust → Configure → Docker → คัดลอก token ใหม่ (ต้องขึ้นต้น `eyJ`) |
| N8N `Mismatching encryption keys` | `N8N_ENCRYPTION_KEY` ใน .env ไม่ตรงกับ volume | อ่าน key จริงจาก volume แล้วอัปเดต .env |
| Webhook 404 | N8N Workflow ยัง Inactive | N8N → Workflow → เปิด Active toggle |
| Fan/Pump วนซ้ำไม่หยุด | Feedback loop | ตรวจสอบ IF anti-loop nodes ใน N8N workflow |
| `DNS_PROBE_FINISHED_NXDOMAIN` | Router DNS ยังไม่อัปเดต | เปลี่ยน DNS เป็น `1.1.1.1` + `8.8.8.8` ใน Network Settings |
| N8N เข้าไม่ได้ผ่าน tunnel | Public hostname ยังไม่ตั้ง | Zero Trust → Tunnels → Edit → Public Hostname → เพิ่ม `n8n.thaitechsync.com → n8n:5678` |
| N8N OAuth2 callback ล้มเหลว | เปิดผ่าน localhost | ใช้ `https://n8n.thaitechsync.com` เสมอ |
| N8N เชื่อม MQTT ไม่ได้ | ใช้ hostname ผิด | ใช้ `mosquitto` ไม่ใช่ `localhost` |
| Node-RED แสดงหน้า Login | ปกติ — Auth เปิดอยู่ | Login: `admin` / `admin1234` |
| Node-RED Login ผิดพลาด | Password ไม่ตรง | ดู `nodered/settings.js` — ต้อง generate bcrypt hash ใหม่ |
| `mosquitto unhealthy` | mosquitto.conf ผิด | `docker logs mosquitto` ตรวจสอบ error |
| Port 1883 ถูกใช้อยู่ | Process อื่นใช้ port | `netstat -ano \| findstr :1883` → `taskkill /PID xxx /F` |

---

## Auto-Control Logic (Anti-loop)

N8N workflow มี IF node ตรวจ relay state ก่อนส่งคำสั่งทุกครั้ง เพื่อป้องกัน feedback loop:

```
Telemetry เข้า N8N
      │
      ├─ IF water_overflow?  → IF any relay ON?    → CMD: ALL OFF → NodeRED
      ├─ IF water_dry?       → IF relay1_pump OFF? → CMD: Pump ON → NodeRED
      └─ IF air_temp ≥ 35°C? → IF relay2_fan OFF?  → CMD: Fan ON  → NodeRED
```

**ผลลัพธ์:** N8N จะส่งคำสั่งซ้ำไม่ได้ เพราะ telemetry รอบถัดไปจะรายงาน relay state ใหม่ → IF false → หยุด

---

## Config สรุป

| รายการ | ค่า |
|--------|-----|
| Node-RED UI | http://localhost:1880 |
| Node-RED Login | admin / admin1234 |
| N8N UI (local) | http://localhost:5678 |
| N8N UI (public) | https://n8n.thaitechsync.com |
| MQTT Broker (local) | localhost:1883 |
| MQTT Broker (Docker) | mosquitto:1883 |
| MQTT Device | ESP32-FARM-001-NATTAPHOL-PALM |
| MQTT Broker (ESP32) | broker.hivemq.com:1883 |
| Cloudflare Domain | thaitechsync.com |
| Tunnel Location | bkk01 (Bangkok), sin15 (Singapore) |
