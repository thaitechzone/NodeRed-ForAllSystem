# Node-RED + N8N + MQTT + ngrok Stack (Docker)

> Platform: Windows 11 Pro | Working dir: `d:\NodeRed`

---

## สถาปัตยกรรมระบบ

```
┌─────────────┐     OPC-UA/DA      ┌─────────────────┐
│     PLC     │ ◄─────────────────► │   OPC Server    │  (Windows, ไม่อยู่ใน Docker)
└─────────────┘                     └────────┬────────┘
                                             │ OPC-UA (port 4840)
                                    ┌────────▼────────┐
                                    │    Node-RED     │  อ่าน/เขียน OPC-UA
                                    │  (port 1880)    │  publish/subscribe MQTT
                                    └────────┬────────┘
                                             │ MQTT (port 1883)
                                    ┌────────▼────────┐
                                    │   Mosquitto     │  Local MQTT Broker
                                    │  (port 1883)    │
                                    └────────┬────────┘
                                             │ MQTT Subscribe
                                    ┌────────▼────────┐
                                    │      N8N        │  Workflow Automation
                                    │  (port 5678)    │  Gemini / Gmail / Drive
                                    └────────┬────────┘
                                             │ tunnel (Docker internal)
                                    ┌────────▼────────┐
                                    │     ngrok       │  Public HTTPS → N8N:5678
                                    │   (Docker)      │  ใช้สำหรับ OAuth2 / Webhook
                                    │  (port 4040)    │  Dashboard: localhost:4040
                                    └─────────────────┘
```

> **ngrok รันเป็น Docker container** — ไม่ต้องติดตั้งโปรแกรมเพิ่มในเครื่อง

---

## Services สรุป

| Service | URL / Port | หมายเหตุ |
|---------|-----------|---------|
| Node-RED UI | http://localhost:1880 | Flow editor + OPC-UA + MQTT |
| N8N UI (local) | http://localhost:5678 | Workflow automation |
| N8N UI (public) | `https://<your-domain>.ngrok-free.dev` | ใช้สำหรับ OAuth2 / Webhook |
| ngrok Dashboard | http://localhost:4040 | ดู tunnel status |
| MQTT Broker | `localhost:1883` | จาก Windows host / ESP32 |
| MQTT (Docker internal) | `mosquitto:1883` | จาก container อื่น |
| MQTT WebSocket | `localhost:9001` | สำหรับ browser client |

---

## โครงสร้างไฟล์

```
d:\NodeRed\
  ├── .env                        ← ตั้งค่าทั้งหมดไว้ที่นี่ (ไม่อยู่ใน Git)
  ├── docker-compose.yml          ← กำหนด services ทั้งหมด (4 services)
  ├── setup.bat                   ← Management script (Windows)
  ├── INSTALL.md                  ← คู่มือติดตั้งฉบับเต็ม
  ├── VPS_DEPLOY.md               ← คู่มือ deploy ไป VPS
  ├── mosquitto\
  │     └── config\
  │           └── mosquitto.conf  ← config ของ MQTT broker
  ├── nodered\
  │     └── settings.js           ← config ของ Node-RED
  └── esp32-firmware-NodeRED\     ← firmware สำหรับ ESP32 (DS18B20 + MQTT)
```

---

## ไฟล์ .env (ตั้งค่าก่อนรัน)

```env
# ─── Timezone ────────────────────────────────────────────
TZ=Asia/Bangkok

# ─── Ngrok ───────────────────────────────────────────────
# Authtoken จาก: https://dashboard.ngrok.com/get-started/your-authtoken
NGROK_AUTHTOKEN=your-authtoken-here
# Static domain จาก: https://dashboard.ngrok.com/domains (ไม่มี https://)
NGROK_DOMAIN=your-domain.ngrok-free.dev
# URL สำหรับ N8N (มี https://)
NGROK_URL=https://your-domain.ngrok-free.dev

# ─── N8N Encryption Key ──────────────────────────────────
# สร้างด้วย PowerShell: powershell -Command "-join ((1..32) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) })"
N8N_ENCRYPTION_KEY=change-this-to-random-32-char-string
```

### ตัวแปรที่ต้อง (Required)

| ตัวแปร | คำอธิบาย |
|-------|---------|
| `TZ` | Timezone สำหรับ Node-RED / N8N (default: `Asia/Bangkok`) |
| `NGROK_AUTHTOKEN` | ngrok authentication token |
| `NGROK_DOMAIN` | ngrok static domain (ไม่มี `https://`) |
| `NGROK_URL` | ngrok URL สำหรับ N8N webhook (มี `https://`) |
| `N8N_ENCRYPTION_KEY` | 32-char hex string สำหรับเข้ารหัส N8N credentials |

---

## docker-compose.yml — Services ทั้งหมด

### Service 1: mosquitto (MQTT Broker)

```yaml
mosquitto:
  image: eclipse-mosquitto:2
  ports:
    - "1883:1883"   # MQTT protocol
    - "9001:9001"   # WebSocket
  healthcheck:
    test: ["CMD", "mosquitto_sub", "-t", "$$SYS/#", "-C", "1", "-W", "3"]
```

### Service 2: nodered (MQTT + Flow Automation)

```yaml
nodered:
  image: nodered/node-red:latest
  ports:
    - "1880:1880"
  depends_on:
    mosquitto:
      condition: service_healthy
```

ต้องการ OPC-UA? ติดตั้ง node เพิ่มและตั้ง endpoint ใน Node-RED UI โดยตรง:

1. เปิด http://localhost:1880
2. ไปที่เมนู ≡ → **Manage palette**
3. แท็บ **Install** → ค้นหา `node-red-contrib-opcua`
4. กด **Install**

### Service 3: n8n (Workflow Automation)

```yaml
n8n:
  image: n8nio/n8n:latest
  ports:
    - "5678:5678"
  environment:
    - N8N_PROTOCOL=https
    - WEBHOOK_URL=${NGROK_URL}/
    - N8N_EDITOR_BASE_URL=${NGROK_URL}/
```

| ตัวแปร | เหตุผล |
|--------|--------|
| `N8N_PROTOCOL=https` | ต้องตรงกับ ngrok ที่เป็น HTTPS |
| `WEBHOOK_URL` | N8N ใช้สร้าง webhook endpoint URLs |
| `N8N_EDITOR_BASE_URL` | N8N ใช้สร้าง OAuth2 callback URL |

### Service 4: ngrok (Tunnel)

```yaml
ngrok:
  image: ngrok/ngrok:latest
  command: http n8n:5678 --url=${NGROK_URL}
  ports:
    - "4040:4040"
```

---

## Data Flow

```
ESP32 (DS18B20) / PLC / OPC-UA
        │
        ▼
    Node-RED  ──── MQTT ────►  Mosquitto  ────►  N8N (automation)
                                                       │
                                              Gemini / Gmail / Drive
```

---

## คำสั่งที่ใช้บ่อย

```bash
# เริ่มทั้งหมด
docker compose up -d

# ดู status
docker compose ps

# ดู logs
docker compose logs -f
docker compose logs -f nodered
docker compose logs -f ngrok

# Restart service เดียว (หลังแก้ .env)
docker compose up -d --force-recreate n8n
docker compose up -d --force-recreate ngrok

# หยุดทั้งหมด (volumes ยังอยู่)
docker compose down

# ลบทุกอย่างรวม volumes (ข้อมูลหาย!)
docker compose down -v
```

---

## MQTT Topic Structure (ESP32 SmartFarm)

| Topic | ทิศทาง | ใช้งาน |
|-------|--------|--------|
| `smartfarm/<DEVICE_ID>/telemetry` | ESP32 → Broker | ข้อมูล sensor ทุก 5 วินาที |
| `smartfarm/<DEVICE_ID>/status` | ESP32 → Broker | สถานะ online/offline |
| `smartfarm/<DEVICE_ID>/command` | N8N/Node-RED → ESP32 | ควบคุม relay |

---

## OAuth2 Setup (Gmail / Google Drive)

OAuth2 ต้องการ Public HTTPS URL สำหรับ callback — `localhost` ใช้ไม่ได้
ngrok ใน Docker จัดการให้อัตโนมัติตั้งแต่ `docker compose up`

1. APIs & Services → Credentials → OAuth 2.0 Client ID
2. Authorized redirect URIs → เพิ่ม:
   ```
   https://your-domain.ngrok-free.dev/rest/oauth2-credential/callback
   ```
3. เปิด N8N **ผ่าน ngrok URL เท่านั้น** เมื่อทำ OAuth2

---

## Troubleshooting

| ปัญหา | วิธีแก้ |
|-------|---------|
| Node-RED login ไม่ได้ | `NR_ADMIN_PASSWORD_HASH` ต้องขึ้นต้นด้วย `$2b$` |
| ngrok ไม่ขึ้น | `docker logs ngrok` — ตรวจ `NGROK_AUTHTOKEN` ใน `.env` |
| OAuth2 callback ล้มเหลว | เปิด N8N ผ่าน ngrok URL ไม่ใช่ localhost |
| N8N เชื่อม MQTT ไม่ได้ | ใช้ hostname `mosquitto` ไม่ใช่ `localhost` |
| `mosquitto unhealthy` | `docker logs mosquitto` — ตรวจ mosquitto.conf |
| Port 1883 ถูกใช้งาน | `netstat -ano \| findstr :1883` หา PID แล้ว `taskkill /PID xxx /F` |
