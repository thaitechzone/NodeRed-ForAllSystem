# คู่มือติดตั้ง Node-RED + N8N + MQTT (Local Docker)

> Platform: Windows 11 Pro | Working dir: `d:\NodeRed`

---

## สิ่งที่ต้องมีก่อนเริ่ม

| รายการ | ตรวจสอบ |
|--------|---------|
| Docker Desktop สำหรับ Windows | [https://www.docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop) |
| WSL2 | Docker Desktop จะติดตั้งให้อัตโนมัติ |
| RAM | แนะนำ 8 GB ขึ้นไป |
| Disk ว่าง | 5 GB ขึ้นไป |

---

## ขั้นตอนที่ 1 — ติดตั้ง Docker Desktop

```powershell
winget install Docker.DockerDesktop
```

หลังติดตั้ง:
1. เปิด Docker Desktop
2. Settings → General → เปิด ✅ **Use WSL 2 based engine**
3. Apply & Restart

ตรวจสอบ:
```bash
docker --version
docker compose version
```

---

## ขั้นตอนที่ 2 — เตรียมโฟลเดอร์โปรเจกต์

ต้องมีไฟล์เหล่านี้ครบก่อนรัน:

```
d:\NodeRed\
  ├── .env
  ├── docker-compose.yml
  ├── mosquitto\
  │     └── config\
  │           └── mosquitto.conf
  └── nodered\
        └── settings.js
```

---

## ขั้นตอนที่ 3 — แก้ไขไฟล์ .env

เปิด `.env` แล้วแก้ค่าให้ตรงกับระบบ:

```env
# Timezone
TZ=Asia/Bangkok

# ngrok URL — ใส่หลัง setup ngrok แล้ว (ดูขั้นตอนที่ 8)
# สำคัญ: ต้องไม่มี space หน้า URL
NGROK_URL=https://your-domain.ngrok-free.app

# Key สำหรับเข้ารหัส credentials ใน N8N (ต้องเปลี่ยน — random string 32+ ตัว)
N8N_ENCRYPTION_KEY=MySecretKey1234567890AbCdEfGhIj

# IP ของเครื่องที่รัน OPC Server (ไม่ใช่ localhost)
OPC_SERVER_IP=192.168.1.100
OPC_SERVER_PORT=4840
```

> หา `OPC_SERVER_IP`: เปิด CMD แล้วพิมพ์ `ipconfig` ดูที่ IPv4 Address

---

## ขั้นตอนที่ 4 — ทำความเข้าใจ docker-compose.yml

ไฟล์ `docker-compose.yml` กำหนด 3 services และทำงานร่วมกัน:

### Service 1: mosquitto

```yaml
mosquitto:
  image: eclipse-mosquitto:2
  container_name: mosquitto
  ports:
    - "1883:1883"   # MQTT protocol — ใช้กับ Node-RED, N8N, MQTT clients
    - "9001:9001"   # WebSocket — สำหรับ browser-based MQTT clients
  volumes:
    - ./mosquitto/config/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro
    - mosquitto_data:/mosquitto/data   # เก็บข้อมูล persistent
    - mosquitto_log:/mosquitto/log     # log files
  restart: unless-stopped
  healthcheck:
    test: ["CMD", "mosquitto_sub", "-t", "$$SYS/#", "-C", "1", "-i", "healthcheck", "-W", "3"]
    interval: 30s
    timeout: 10s
    retries: 3
```

**Healthcheck:** Docker จะตรวจสอบว่า Mosquitto พร้อมรับ connection ก่อน start services อื่น  
Services ที่ระบุ `depends_on: mosquitto: condition: service_healthy` จะรอจนผ่าน healthcheck

### Service 2: nodered

```yaml
nodered:
  image: nodered/node-red:latest
  container_name: nodered
  ports:
    - "1880:1880"   # Web UI ของ Node-RED
  volumes:
    - nodered_data:/data                         # flows, credentials, node modules
    - ./nodered/settings.js:/data/settings.js:ro # config ของ Node-RED (read-only)
  environment:
    - TZ=${TZ}                       # Timezone จาก .env
    - OPC_SERVER_IP=${OPC_SERVER_IP}   # IP ของ OPC Server จาก .env
    - OPC_SERVER_PORT=${OPC_SERVER_PORT}
  depends_on:
    mosquitto:
      condition: service_healthy     # รอ Mosquitto พร้อมก่อน
```

**หมายเหตุ:** `OPC_SERVER_IP` และ `OPC_SERVER_PORT` ส่งเข้า container เพื่อให้ flow ใน Node-RED เรียกใช้ได้

### Service 3: n8n

```yaml
n8n:
  image: n8nio/n8n:latest
  container_name: n8n
  ports:
    - "5678:5678"   # Web UI ของ N8N
  volumes:
    - n8n_data:/home/node/.n8n   # workflows, credentials, database
  environment:
    - TZ=${TZ}
    - GENERIC_TIMEZONE=${TZ}

    # Network settings
    - N8N_HOST=0.0.0.0        # รับ connection จากทุก interface (จำเป็นสำหรับ ngrok)
    - N8N_PORT=5678
    - N8N_PROTOCOL=https      # ต้องตรงกับ ngrok ที่เป็น HTTPS

    # URL settings — ทั้งสองต้องตั้งพร้อมกันเสมอ
    - WEBHOOK_URL=${NGROK_URL}/         # N8N ใช้สร้าง webhook endpoint URLs
    - N8N_EDITOR_BASE_URL=${NGROK_URL}/ # N8N ใช้สร้าง OAuth2 callback URL

    # Security
    - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}  # เข้ารหัส credentials ที่เก็บใน volume

    # Performance
    - N8N_METRICS=false              # ปิด metrics endpoint
    - EXECUTIONS_DATA_PRUNE=true     # ลบ execution logs อัตโนมัติ
    - EXECUTIONS_DATA_MAX_AGE=168    # เก็บ logs ไว้ 168 ชั่วโมง (7 วัน)

  depends_on:
    mosquitto:
      condition: service_healthy
```

**ตัวแปรที่สำคัญที่สุดสำหรับ OAuth2:**

| ตัวแปร | ต้องเป็น | เหตุผล |
|--------|---------|--------|
| `N8N_HOST` | `0.0.0.0` | ถ้าเป็น `localhost` ngrok เข้าไม่ได้ |
| `N8N_PROTOCOL` | `https` | ต้องตรงกับ ngrok URL |
| `WEBHOOK_URL` | ngrok URL | N8N สร้าง OAuth callback URL จากนี้ |
| `N8N_EDITOR_BASE_URL` | ngrok URL | ถ้าไม่มี OAuth callback จะกลับไป localhost |

---

## ขั้นตอนที่ 5 — Pull Images และ Start Services

```bash
cd d:\NodeRed

# Pull images ทั้งหมด
docker compose pull

# Start ทั้งหมด
docker compose up -d
```

ตรวจสอบ:
```bash
docker compose ps
```

ผลลัพธ์ที่ควรเห็น:
```
NAME         IMAGE                    STATUS
mosquitto    eclipse-mosquitto:2      running (healthy)
nodered      nodered/node-red:latest  running
n8n          n8nio/n8n:latest         running
```

---

## ขั้นตอนที่ 6 — ติดตั้ง OPC-UA Node ใน Node-RED

```bash
# ติดตั้ง node
docker exec nodered npm install node-red-contrib-opcua --prefix /data

# Restart เพื่อโหลด node ใหม่
docker restart nodered
```

ตรวจสอบ:
```bash
docker exec nodered ls /data/node_modules | findstr opcua
# ควรแสดง: node-red-contrib-opcua
```

หรือติดตั้งผ่าน UI: Node-RED → ☰ Menu → **Manage palette** → Install → ค้น `node-red-contrib-opcua`

---

## ขั้นตอนที่ 7 — ตั้งค่า MQTT Credential ใน N8N

1. เปิด [http://localhost:5678](http://localhost:5678) → สร้างบัญชี Admin
2. Settings → Credentials → **Add Credential**
3. ค้นหา `MQTT` → เลือก **MQTT**
4. กรอก:
   - **Host:** `mosquitto` (ชื่อ service ใน Docker network — ไม่ใช่ localhost)
   - **Port:** `1883`
5. Save

---

## ขั้นตอนที่ 8 — Setup ngrok สำหรับ OAuth2

> ข้ามขั้นตอนนี้ถ้ายังไม่ต้องการ Gmail / Google Drive

### ติดตั้งและตั้งค่า

```bash
# ติดตั้ง
winget install ngrok.ngrok

# สมัครบัญชีที่ https://dashboard.ngrok.com/signup
# แล้วนำ Authtoken มาใส่
ngrok config add-authtoken YOUR_TOKEN_HERE
```

### สร้าง Static Domain (ฟรี 1 domain)

1. ไปที่ [dashboard.ngrok.com](https://dashboard.ngrok.com) → **Cloud Edge** → **Domains** → **New Domain**
2. จะได้ domain เช่น `your-name-abc.ngrok-free.app`

ข้อดีของ Static Domain: URL ไม่เปลี่ยนทุกครั้งที่ restart — ไม่ต้องอัปเดต Google Console ซ้ำ

### รัน ngrok Tunnel

```bash
# รัน (แทน your-domain ด้วย domain ที่ได้)
ngrok http --domain=your-domain.ngrok-free.app 5678
```

**ngrok รันบน Windows host โดยตรง** — ไม่ได้อยู่ใน Docker ดังนั้น `docker compose restart` ไม่กระทบ ngrok

### อัปเดต .env

```env
NGROK_URL=https://your-domain.ngrok-free.app
```

### Restart N8N เพื่อโหลด URL ใหม่

```bash
docker compose up -d --force-recreate n8n
```

---

## ขั้นตอนที่ 9 — Setup Google OAuth2 (Gmail / Google Drive)

### 9.1 สร้าง Google Cloud Project

1. ไปที่ [https://console.cloud.google.com](https://console.cloud.google.com)
2. สร้าง Project ใหม่ (หรือใช้ที่มีอยู่)
3. Enable APIs:
   - **Gmail API** → APIs & Services → Library → ค้น "Gmail API" → Enable
   - **Google Drive API** → ค้น "Google Drive API" → Enable
   - **Generative Language API** → ค้น "Generative Language API" → Enable

### 9.2 สร้าง OAuth2 Client ID

1. APIs & Services → **Credentials** → **Create Credentials** → **OAuth client ID**
2. Application type: **Web application**
3. Authorized redirect URIs → Add:
   ```
   https://your-domain.ngrok-free.app/rest/oauth2-credential/callback
   ```
4. Save → Download JSON → เก็บ `Client ID` และ `Client Secret`

### 9.3 เพิ่ม Credentials ใน N8N

> **สำคัญ:** ต้องเปิด N8N ผ่าน ngrok URL เท่านั้น ไม่ใช่ localhost

1. เปิด `https://your-domain.ngrok-free.app`
2. Settings → Credentials → Add Credential
3. สำหรับ Gmail: เลือก **Gmail OAuth2 API** → ใส่ Client ID + Secret → **Connect**
4. สำหรับ Drive: เลือก **Google Drive OAuth2 API** → ใส่ Client ID + Secret → **Connect**
5. หน้าต่าง Google Login จะเปิดขึ้น → Allow
6. สถานะเป็น **Connected** = สำเร็จ

### 9.4 Gemini API Key

1. สร้าง API Key ที่ [https://aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey)
2. N8N: Settings → Credentials → New → **Google Gemini(PaLM) Api** → วาง Key

---

## ขั้นตอนที่ 10 — ทดสอบ MQTT

```bash
# Subscribe ดูข้อมูลทุก topic ใต้ plc/
docker exec -it mosquitto mosquitto_sub -t "plc/#" -v

# เปิด terminal ใหม่ แล้ว publish ทดสอบ
docker exec mosquitto mosquitto_pub -t "plc/data/temperature" -m "{\"value\":75.5,\"unit\":\"C\"}"
```

หรือใช้ GUI: [MQTT Explorer](https://mqtt-explorer.com) → เชื่อมที่ `localhost:1883`

---

## การจัดการ ngrok URL เมื่อเปลี่ยน (Free plan ที่ไม่ใช้ Static Domain)

| สถานการณ์ | ต้องทำอะไร |
|-----------|-----------|
| `docker compose restart n8n` | ไม่ต้องทำอะไรกับ ngrok ✅ |
| ngrok ยังรันอยู่, URL เดิม | ไม่ต้องทำอะไร ✅ |
| ngrok เปิดใหม่ (URL เปลี่ยน) | อัปเดต .env → restart n8n → อัปเดต Google Console ⚠️ |

ถ้า URL เปลี่ยน ให้ทำตามลำดับ:
```bash
# 1. เปิด ngrok ใหม่ — ดู URL จาก terminal
ngrok http 5678

# 2. แก้ไข .env
#    NGROK_URL=https://xyz789.ngrok-free.app

# 3. Restart N8N
docker compose up -d --force-recreate n8n

# 4. อัปเดต Google Cloud Console → Authorized redirect URIs
```

---

## คำสั่งที่ใช้บ่อย

```bash
# ดู status ทุก service
docker compose ps

# ดู logs ทั้งหมด
docker compose logs -f

# ดู log เฉพาะ service
docker compose logs -f n8n
docker compose logs -f nodered
docker compose logs -f mosquitto

# Restart service เดียว (หลังแก้ .env)
docker compose up -d --force-recreate n8n

# หยุดทั้งหมด
docker compose stop

# เริ่มใหม่
docker compose start

# หยุดและลบ containers (volumes ยังอยู่)
docker compose down

# ลบทุกอย่างรวม volumes (ข้อมูลหาย!)
docker compose down -v

# ดู resource usage
docker stats
```

---

## Checklist ทั้งระบบ

### ติดตั้งครั้งแรก
- [ ] ติดตั้ง Docker Desktop + WSL2
- [ ] แก้ไข `.env` — ใส่ `OPC_SERVER_IP`, `N8N_ENCRYPTION_KEY`
- [ ] `docker compose up -d`
- [ ] ติดตั้ง `node-red-contrib-opcua` ใน Node-RED
- [ ] ตั้งค่า MQTT Credential ใน N8N (host: `mosquitto`, port: `1883`)

### Setup OAuth2 (Google Services)
- [ ] ติดตั้ง ngrok + สร้าง Static Domain
- [ ] แก้ไข `.env` ใส่ `NGROK_URL` (ไม่มี space)
- [ ] `docker compose up -d --force-recreate n8n`
- [ ] Google Cloud: Enable Gmail API + Drive API + Generative Language API
- [ ] Google Cloud: สร้าง OAuth2 Client ID + ใส่ redirect URI
- [ ] เพิ่ม Gmail + Drive Credentials ใน N8N (ผ่าน ngrok URL)
- [ ] สร้าง Gemini API Key + เพิ่มใน N8N

### ทดสอบ
- [ ] MQTT: `mosquitto_pub` → `mosquitto_sub` → รับได้
- [ ] Node-RED: OPC UA Client เชื่อม OPC Server ได้
- [ ] N8N: MQTT Trigger รับข้อมูลจาก Node-RED ได้
- [ ] N8N: Gmail / Drive OAuth2 status = Connected

---

## Troubleshooting

| ปัญหา | วิธีแก้ |
|-------|---------|
| OAuth2 callback ล้มเหลว | เปิด N8N ผ่าน ngrok URL ไม่ใช่ localhost |
| N8N เชื่อม MQTT ไม่ได้ | ใช้ hostname `mosquitto` ไม่ใช่ `localhost` |
| NGROK_URL มี space นำหน้า | แก้ `.env`: `NGROK_URL=https://...` (ลบ space) |
| `mosquitto unhealthy` | `docker logs mosquitto` — มักเป็น mosquitto.conf ผิด |
| Node-RED ไม่โหลด OPC node | `docker restart nodered` แล้วรอ 30 วิ |
| Port 1883 ถูกใช้งาน | `netstat -ano \| findstr :1883` หา PID แล้ว `taskkill /PID xxx /F` |
| Docker ไม่ start | เปิด Docker Desktop ก่อนแล้วรอ engine พร้อม |
