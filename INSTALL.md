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

# Cloudflare Tunnel — ใส่หลัง setup tunnel แล้ว (ดูขั้นตอนที่ 8)
CLOUDFLARE_TUNNEL_TOKEN=YOUR_TUNNEL_TOKEN_HERE
CF_TUNNEL_URL=https://YOUR-CF-TUNNEL-URL

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
| `N8N_HOST` | `0.0.0.0` | ถ้าเป็น `localhost` tunnel เข้าไม่ได้ |
| `N8N_PROTOCOL` | `https` | ต้องตรงกับ Cloudflare Tunnel URL (HTTPS) |
| `WEBHOOK_URL` | CF Tunnel URL | N8N สร้าง OAuth callback URL จากนี้ |
| `N8N_EDITOR_BASE_URL` | CF Tunnel URL | ถ้าไม่มี OAuth callback จะกลับไป localhost |

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

## ขั้นตอนที่ 8 — Setup Cloudflare Tunnel สำหรับ OAuth2

> ข้ามขั้นตอนนี้ถ้ายังไม่ต้องการ Gmail / Google Drive

Cloudflare Tunnel รันใน Docker ร่วมกับ N8N — **ไม่ต้องเปิด terminal แยก** และ **URL ไม่เปลี่ยนเมื่อ restart**

### 8.1 สร้าง Cloudflare Account

สมัครบัญชีฟรีที่ [dash.cloudflare.com/sign-up](https://dash.cloudflare.com/sign-up)

### 8.2 เพิ่ม Domain ใน Cloudflare

> ต้องมี domain ที่ใช้ Cloudflare เป็น nameserver เช่น domain จาก Cloudflare Registrar, Namecheap, หรืออื่น ๆ ที่เปลี่ยน NS มาชี้ Cloudflare

1. ไปที่ [dash.cloudflare.com](https://dash.cloudflare.com) → **Add a domain**
2. ทำตามขั้นตอน — อัปเดต nameserver ที่ registrar ให้ชี้มา Cloudflare

### 8.3 สร้าง Tunnel

1. ไปที่ **Zero Trust** (เมนูซ้าย) → [one.dash.cloudflare.com](https://one.dash.cloudflare.com)
2. **Networks** → **Tunnels** → **Create a tunnel**
3. เลือก **Cloudflared** → ตั้งชื่อ tunnel เช่น `n8n-smartfarm` → **Save tunnel**
4. หน้า **Install connector** จะแสดง token — **คัดลอก token ทั้งหมด**

### 8.4 กำหนด Public Hostname

ยังอยู่ในหน้า Create Tunnel → แท็บ **Public Hostname**:

| Field | ค่า |
|-------|-----|
| Subdomain | `n8n` |
| Domain | `thaitechsync.com` (domain ที่เพิ่มไว้) |
| Service Type | `HTTP` |
| URL | `n8n:5678` |

> `n8n:5678` คือ Docker service name ภายใน network — cloudflared เข้าถึงได้โดยตรง

คลิก **Save tunnel** → tunnel URL จะเป็น `https://n8n.thaitechsync.com`

### 8.5 อัปเดต .env

```env
CLOUDFLARE_TUNNEL_TOKEN=eyJhIjoixxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx...
CF_TUNNEL_URL=https://n8n.thaitechsync.com
```

### 8.6 Start Cloudflared พร้อม Stack

```bash
docker compose up -d
```

Cloudflared จะ start อัตโนมัติพร้อมกับ N8N ทุกครั้ง

### 8.7 Restart N8N เพื่อโหลด URL ใหม่

```bash
docker compose up -d --force-recreate n8n
```

### 8.8 ตรวจสอบ Tunnel ทำงาน

```bash
docker logs cloudflared
```

ควรเห็น:
```
Connection established connIndex=0 ...
```

หรือเปิด Zero Trust Dashboard → Tunnels → สถานะ tunnel เป็น **Healthy**

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
   https://n8n.thaitechsync.com/rest/oauth2-credential/callback
   ```
4. Save → Download JSON → เก็บ `Client ID` และ `Client Secret`

### 9.3 เพิ่ม Credentials ใน N8N

> **สำคัญ:** ต้องเปิด N8N ผ่าน Cloudflare Tunnel URL เท่านั้น ไม่ใช่ localhost

1. เปิด `https://n8n.thaitechsync.com`
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

## การจัดการ Cloudflare Tunnel

| สถานการณ์ | ต้องทำอะไร |
|-----------|-----------|
| `docker compose restart n8n` | ไม่ต้องทำอะไร — URL คงที่ ✅ |
| `docker compose restart cloudflared` | ไม่ต้องทำอะไร — reconnect อัตโนมัติ ✅ |
| เปลี่ยน domain / subdomain | อัปเดต `CF_TUNNEL_URL` → restart n8n → อัปเดต Google Console ⚠️ |
| Token หมดอายุ / revoke | สร้าง token ใหม่ใน Zero Trust → อัปเดต `CLOUDFLARE_TUNNEL_TOKEN` → restart cloudflared ⚠️ |

ถ้าต้องเปลี่ยน domain:
```bash
# 1. อัปเดต Zero Trust Dashboard → Tunnels → Public Hostname

# 2. แก้ไข .env
#    CF_TUNNEL_URL=https://n8n-new.thaitechsync.com

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
- [ ] สร้าง Cloudflare account + เพิ่ม domain
- [ ] สร้าง tunnel ใน Zero Trust → คัดลอก token
- [ ] กำหนด Public Hostname: `n8n.thaitechsync.com` → `n8n:5678`
- [ ] แก้ไข `.env` ใส่ `CLOUDFLARE_TUNNEL_TOKEN` และ `CF_TUNNEL_URL`
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
| OAuth2 callback ล้มเหลว | เปิด N8N ผ่าน Cloudflare Tunnel URL ไม่ใช่ localhost |
| N8N เชื่อม MQTT ไม่ได้ | ใช้ hostname `mosquitto` ไม่ใช่ `localhost` |
| CF_TUNNEL_URL มี space นำหน้า | แก้ `.env`: `CF_TUNNEL_URL=https://...` (ลบ space) |
| cloudflared logs แสดง `failed to connect` | ตรวจสอบ `CLOUDFLARE_TUNNEL_TOKEN` ใน `.env` ถูกต้อง |
| Tunnel สถานะ `Degraded` ใน Dashboard | `docker restart cloudflared` — reconnect อัตโนมัติ |
| `mosquitto unhealthy` | `docker logs mosquitto` — มักเป็น mosquitto.conf ผิด |
| Node-RED ไม่โหลด OPC node | `docker restart nodered` แล้วรอ 30 วิ |
| Port 1883 ถูกใช้งาน | `netstat -ano \| findstr :1883` หา PID แล้ว `taskkill /PID xxx /F` |
| Docker ไม่ start | เปิด Docker Desktop ก่อนแล้วรอ engine พร้อม |
