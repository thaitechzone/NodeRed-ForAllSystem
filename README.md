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
                                             │ tunnel (Docker internal)
                                    ┌────────▼────────┐
                                    │     ngrok       │  Public HTTPS → N8N:5678
                                    │  (Docker)       │  ใช้สำหรับ OAuth2 Callback
                                    │  (port 4040)    │  Dashboard: localhost:4040
                                    └─────────────────┘
```

> **ngrok รันเป็น Docker container** — ไม่ต้องติดตั้งโปรแกรมเพิ่มในเครื่อง  
> รันและหยุดพร้อม `docker compose up/down` อัตโนมัติ

---

## Services สรุป

| Service | URL / Port | หมายเหตุ |
|---------|-----------|---------|
| Node-RED UI | http://localhost:1880 | Flow editor |
| N8N UI (local) | http://localhost:5678 | Workflow automation |
| N8N UI (public) | `https://<NGROK_DOMAIN>` | ใช้สำหรับ OAuth2 |
| ngrok Dashboard | http://localhost:4040 | ดู tunnel status |
| MQTT Broker | `localhost:1883` | จาก Windows host |
| MQTT (Docker internal) | `mosquitto:1883` | จาก container อื่น |
| MQTT WebSocket | `localhost:9001` | สำหรับ browser client |

---

## โครงสร้างไฟล์

```
d:\NodeRed\
  ├── .env                        ← ตั้งค่าทั้งหมดไว้ที่นี่
  ├── docker-compose.yml          ← กำหนด services ทั้งหมด (4 services)
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

# ─── Ngrok ───────────────────────────────────────────────
# Authtoken จาก https://dashboard.ngrok.com/get-started/your-authtoken
NGROK_AUTHTOKEN=your-authtoken-here

# Static domain จาก https://dashboard.ngrok.com/domains (ไม่ต้องมี https://)
NGROK_DOMAIN=your-domain.ngrok-free.dev
NGROK_URL=https://your-domain.ngrok-free.dev

# Key สำหรับเข้ารหัส credentials ใน N8N (random string ยาว 32+ ตัว)
N8N_ENCRYPTION_KEY=change-this-to-random-32-char-string

# Node-RED Admin Login
NR_ADMIN_USERNAME=admin
NR_ADMIN_PASSWORD_HASH=$2b$08$REPLACE_THIS_WITH_REAL_HASH

# IP ของเครื่องที่รัน OPC Server (ไม่ใช่ localhost)
OPC_SERVER_IP=192.168.1.100
OPC_SERVER_PORT=4840
```

> **หมายเหตุ `NGROK_DOMAIN` vs `NGROK_URL`**  
> - `NGROK_DOMAIN` — ใช้ใน ngrok container command (ไม่มี `https://`)  
> - `NGROK_URL` — ใช้ใน N8N config (มี `https://`)  
> ทั้งสองต้องชี้ไปที่ domain เดียวกัน

### วิธีสร้าง NR_ADMIN_PASSWORD_HASH

| วิธี | คำสั่ง | ต้องการ |
|------|--------|---------|
| CMD / PowerShell | `npx node-red-admin hash-pw` | Node.js |
| Docker (ยังไม่รัน) | `docker run --rm -it nodered/node-red node-red-admin hash-pw` | Docker |
| Docker (รันอยู่แล้ว) | `docker exec -it nodered node-red-admin hash-pw` | Docker + nodered running |

พิมพ์ password แล้วกด Enter — ได้ hash ขึ้นต้นด้วย `$2b$` นำไปใส่ใน `.env`

---

## docker-compose.yml อธิบาย

### Service 1: mosquitto (MQTT Broker)

```yaml
mosquitto:
  image: eclipse-mosquitto:2
  ports:
    - "1883:1883"   # MQTT protocol
    - "9001:9001"   # WebSocket (สำหรับ browser)
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
    - NR_ADMIN_USERNAME=${NR_ADMIN_USERNAME}
    - NR_ADMIN_PASSWORD_HASH=${NR_ADMIN_PASSWORD_HASH}
  depends_on:
    mosquitto:
      condition: service_healthy
```

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
    - EXECUTIONS_DATA_PRUNE=true
    - EXECUTIONS_DATA_MAX_AGE=168   # เก็บ logs 168 ชั่วโมง (7 วัน)
```

**ตัวแปรสำคัญสำหรับ OAuth2:**

| ตัวแปร | ค่า | เหตุผล |
|--------|-----|--------|
| `N8N_HOST` | `0.0.0.0` | ให้ N8N รับ request จากทุก IP รวมถึง ngrok |
| `N8N_PROTOCOL` | `https` | ต้องตรงกับ ngrok URL ที่เป็น HTTPS |
| `WEBHOOK_URL` | ngrok URL | N8N ใช้สร้าง webhook endpoint URLs |
| `N8N_EDITOR_BASE_URL` | ngrok URL | N8N ใช้สร้าง OAuth2 callback URL |

> `WEBHOOK_URL` และ `N8N_EDITOR_BASE_URL` ต้องตั้งพร้อมกัน มิฉะนั้น OAuth2 จะ redirect กลับไปที่ localhost

### Service 4: ngrok (Tunnel)

```yaml
ngrok:
  image: ngrok/ngrok:latest
  command: http --domain=${NGROK_DOMAIN} n8n:5678
  environment:
    - NGROK_AUTHTOKEN=${NGROK_AUTHTOKEN}
  ports:
    - "4040:4040"   # Dashboard
  depends_on:
    - n8n
  restart: unless-stopped
```

- ชี้ tunnel ไปที่ `n8n:5678` โดยตรงใน Docker network (ไม่ผ่าน localhost)
- Dashboard ดูสถานะ tunnel ได้ที่ http://localhost:4040
- `restart: unless-stopped` — ถ้า tunnel หลุด Docker จะ restart ให้อัตโนมัติ

---

## คำสั่งที่ใช้บ่อย

```bash
# เริ่มทั้งหมด
docker compose up -d

# ดู status
docker compose ps

# ดู logs
docker compose logs -f
docker compose logs -f ngrok
docker compose logs -f n8n

# Restart service เดียว (เช่น หลังแก้ .env)
docker compose up -d --force-recreate n8n
docker compose up -d --force-recreate ngrok

# หยุดทั้งหมด (ข้อมูลใน volumes ยังอยู่)
docker compose down

# ลบทุกอย่างรวม volumes (ข้อมูลหาย!)
docker compose down -v
```

---

## OAuth2 Setup (Gmail / Google Drive)

OAuth2 ต้องการ Public HTTPS URL สำหรับ callback — `localhost` ใช้ไม่ได้  
ngrok ใน Docker จัดการให้อัตโนมัติตั้งแต่ `docker compose up`

### อัปเดต Google Cloud Console

1. APIs & Services → Credentials → เลือก OAuth 2.0 Client ID
2. Authorized redirect URIs → เพิ่ม:
   ```
   https://your-domain.ngrok-free.dev/rest/oauth2-credential/callback
   ```
3. Save

> เปลี่ยน `your-domain.ngrok-free.dev` เป็นค่า `NGROK_DOMAIN` ใน `.env` ของคุณ

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
| Node-RED login ไม่ได้ | ตรวจสอบว่า `NR_ADMIN_PASSWORD_HASH` ขึ้นต้นด้วย `$2b$` |
| Node-RED เข้าได้โดยไม่มี login | `NR_ADMIN_PASSWORD_HASH` ว่างหรือไม่ได้ส่งเข้า container |
| OAuth2 callback ล้มเหลว | เปิด N8N ผ่าน ngrok URL ไม่ใช่ localhost |
| N8N เชื่อม MQTT ไม่ได้ | ใช้ hostname `mosquitto` ไม่ใช่ `localhost` |
| ngrok ไม่ขึ้น / tunnel ไม่ได้ | `docker logs ngrok` — ตรวจสอบ `NGROK_AUTHTOKEN` ใน `.env` |
| `mosquitto unhealthy` | `docker logs mosquitto` — มักเป็น mosquitto.conf ผิด |
| Node-RED ไม่โหลด OPC node | `docker restart nodered` แล้วรอ 30 วิ |
| Port 1883 ถูกใช้งาน | `netstat -ano \| findstr :1883` หา PID แล้ว `taskkill /PID xxx /F` |
