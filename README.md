# NodeRed & N8N Local Setup via Docker

> Platform: Windows 11 Pro | Working dir: `d:\NodeRed`

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
                                             │ MQTT
                                    ┌────────▼────────┐
                                    │      N8N        │  Workflow Automation
                                    │  (port 5678)    │  Gemini / Gmail / Drive
                                    └────────┬────────┘
                                             │ ngrok tunnel (HTTPS)
                                    ┌────────▼────────┐
                                    │   ngrok         │  Public HTTPS → localhost:5678
                                    │  (Windows host) │  ใช้สำหรับ OAuth2 Callback
                                    └─────────────────┘
```

---

## Services สรุป

| Service | URL / Port | หมายเหตุ |
|---------|-----------|---------|
| Node-RED UI | http://localhost:1880 | Flow editor |
| N8N UI (local) | http://localhost:5678 | Workflow automation |
| N8N UI (ngrok) | `https://<ngrok-url>` | ใช้สำหรับ OAuth2 |
| MQTT Broker | `localhost:1883` | จาก Windows host |
| MQTT (Docker internal) | `mosquitto:1883` | จาก container อื่น |
| MQTT WebSocket | `localhost:9001` | สำหรับ browser client |

---

## โครงสร้างไฟล์

```
d:\NodeRed\
  ├── .env                        ← ตั้งค่าทั้งหมดไว้ที่นี่
  ├── docker-compose.yml          ← กำหนด services ทั้งหมด
  ├── mosquitto\
  │     └── config\
  │           └── mosquitto.conf  ← config ของ MQTT broker
  └── nodered\
        └── settings.js           ← config ของ Node-RED
```

---

## ไฟล์ .env (ตั้งค่าก่อนรัน)

```env
# Timezone
TZ=Asia/Bangkok

# ngrok URL (ไม่มี space หน้า URL)
NGROK_URL=https://your-domain.ngrok-free.app

# Key สำหรับเข้ารหัส credentials ใน N8N (random string ยาว 32+ ตัว)
N8N_ENCRYPTION_KEY=change-this-to-random-32-char-string

# IP ของเครื่องที่รัน OPC Server (ไม่ใช่ localhost)
OPC_SERVER_IP=192.168.1.100
OPC_SERVER_PORT=4840
```

> **สำคัญ:** `NGROK_URL` ต้องไม่มี space นำหน้า URL มิฉะนั้น OAuth2 จะทำงานผิดพลาด

---

## docker-compose.yml อธิบาย

### Service 1: mosquitto (MQTT Broker)

```yaml
mosquitto:
  image: eclipse-mosquitto:2
  ports:
    - "1883:1883"   # MQTT protocol
    - "9001:9001"   # WebSocket (สำหรับ browser)
  volumes:
    - ./mosquitto/config/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro
  healthcheck:
    test: ["CMD", "mosquitto_sub", "-t", "$$SYS/#", "-C", "1", "-W", "3"]
    interval: 30s
```

- Healthcheck ทำให้ services อื่นรอ Mosquitto พร้อมก่อน (`depends_on: condition: service_healthy`)

### Service 2: nodered (OPC-UA + MQTT)

```yaml
nodered:
  image: nodered/node-red:latest
  ports:
    - "1880:1880"
  environment:
    - TZ=${TZ}
    - OPC_SERVER_IP=${OPC_SERVER_IP}
    - OPC_SERVER_PORT=${OPC_SERVER_PORT}
  depends_on:
    mosquitto:
      condition: service_healthy
```

- รับค่า IP และ Port ของ OPC Server จาก `.env`
- จะ start หลัง Mosquitto พร้อมเท่านั้น

### Service 3: n8n (Workflow Automation)

```yaml
n8n:
  image: n8nio/n8n:latest
  ports:
    - "5678:5678"
  environment:
    - N8N_HOST=0.0.0.0              # รับ connection จากทุก interface
    - N8N_PORT=5678
    - N8N_PROTOCOL=https            # ต้องตรงกับ ngrok (HTTPS)
    - WEBHOOK_URL=${NGROK_URL}/     # URL base สำหรับ webhook nodes
    - N8N_EDITOR_BASE_URL=${NGROK_URL}/  # URL สำหรับ OAuth2 callback
    - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
    - N8N_METRICS=false
    - EXECUTIONS_DATA_PRUNE=true    # ลบ execution logs อัตโนมัติ
    - EXECUTIONS_DATA_MAX_AGE=168   # เก็บ logs 168 ชั่วโมง (7 วัน)
```

**ตัวแปรสำคัญ:**

| ตัวแปร | ค่า | เหตุผล |
|--------|-----|--------|
| `N8N_HOST` | `0.0.0.0` | ให้ N8N รับ request จากทุก IP รวมถึง ngrok |
| `N8N_PROTOCOL` | `https` | ต้องตรงกับ ngrok URL ที่เป็น HTTPS |
| `WEBHOOK_URL` | ngrok URL | N8N ใช้สร้าง webhook endpoint URLs |
| `N8N_EDITOR_BASE_URL` | ngrok URL | N8N ใช้สร้าง OAuth2 callback URL |

> `WEBHOOK_URL` และ `N8N_EDITOR_BASE_URL` ต้องตั้งพร้อมกัน มิฉะนั้น OAuth2 จะ redirect กลับไปที่ localhost

---

## คำสั่งที่ใช้บ่อย

```bash
# เริ่มทั้งหมด
docker compose up -d

# ดู status
docker compose ps

# ดู logs
docker compose logs -f
docker compose logs -f n8n

# Restart service เดียว (เช่น หลังแก้ .env)
docker compose up -d --force-recreate n8n

# หยุดทั้งหมด (ข้อมูลใน volumes ยังอยู่)
docker compose down

# ลบทุกอย่างรวม volumes (ข้อมูลหาย!)
docker compose down -v
```

---

## OAuth2 Setup (Gmail / Google Drive)

OAuth2 ต้องการ Public HTTPS URL สำหรับ callback — `localhost` ใช้ไม่ได้

### วิธีที่แนะนำ: ngrok Static Domain (ฟรี)

```bash
# ติดตั้ง
winget install ngrok.ngrok

# Auth
ngrok config add-authtoken YOUR_TOKEN

# รัน (ใช้ static domain เพื่อ URL ไม่เปลี่ยน)
ngrok http --domain=your-domain.ngrok-free.app 5678
```

**Static Domain ฟรี:** Dashboard → Cloud Edge → Domains → New Domain

### อัปเดต Google Cloud Console

1. APIs & Services → Credentials → เลือก OAuth 2.0 Client ID
2. Authorized redirect URIs → เพิ่ม:
   ```
   https://your-domain.ngrok-free.app/rest/oauth2-credential/callback
   ```
3. Save

### อัปเดต .env และ Restart N8N

```bash
# แก้ไข .env
NGROK_URL=https://your-domain.ngrok-free.app

# Restart N8N
docker compose up -d --force-recreate n8n
```

---

## N8N Integrations — Google Services

### Gemini API
1. สร้าง API Key ที่ [https://aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey)
2. N8N: Settings → Credentials → New → `Google Gemini(PaLM) Api` → วาง Key

### Gmail & Google Drive (OAuth2)
1. Google Cloud Console → Enable **Gmail API** + **Google Drive API**
2. Create OAuth2 Client ID (Web application)
3. Redirect URI: `https://your-domain.ngrok-free.app/rest/oauth2-credential/callback`
4. เปิด N8N ผ่าน ngrok URL (ไม่ใช่ localhost) แล้ว Connect

---

## MQTT Topic Structure

| Topic | ทิศทาง | ใช้งาน |
|-------|--------|--------|
| `plc/data/temperature` | Node-RED → N8N | ค่า Sensor จาก PLC |
| `plc/data/pressure` | Node-RED → N8N | ค่า Sensor จาก PLC |
| `plc/data/status` | Node-RED → N8N | สถานะเครื่องจักร |
| `plc/command/setpoint` | N8N → Node-RED | สั่งค่า Setpoint |
| `plc/command/start` | N8N → Node-RED | สั่งเดินเครื่อง |
| `plc/command/stop` | N8N → Node-RED | สั่งหยุดเครื่อง |

---

## Troubleshooting

| ปัญหา | วิธีแก้ |
|-------|---------|
| OAuth2 callback ล้มเหลว | เปิด N8N ผ่าน ngrok URL ไม่ใช่ localhost |
| N8N เชื่อม MQTT ไม่ได้ | ใช้ hostname `mosquitto` ไม่ใช่ `localhost` |
| `mosquitto unhealthy` | `docker logs mosquitto` — มักเป็น mosquitto.conf ผิด |
| Node-RED ไม่โหลด OPC node | `docker restart nodered` แล้วรอ 30 วิ |
| Port 1883 ถูกใช้งาน | `netstat -ano \| findstr :1883` หา PID แล้ว `taskkill /PID xxx /F` |
| NGROK_URL มี space นำหน้า | แก้ `.env` ให้ไม่มี space: `NGROK_URL=https://...` |
