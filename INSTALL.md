# คู่มือติดตั้ง Node-RED + N8N + MQTT + ngrok (Docker)

> Platform: Windows 11 Pro | Working dir: `d:\NodeRed`

---

## สิ่งที่ต้องมีก่อนเริ่ม

| รายการ | ตรวจสอบ |
|--------|---------|
| Docker Desktop สำหรับ Windows | https://www.docker.com/products/docker-desktop |
| WSL2 | Docker Desktop จะติดตั้งให้อัตโนมัติ |
| บัญชี ngrok (ฟรี) | https://dashboard.ngrok.com/signup |
| RAM | แนะนำ 4 GB ขึ้นไป |
| Disk ว่าง | 3 GB ขึ้นไป |

> **ไม่ต้องติดตั้ง ngrok ในเครื่อง** — ใช้ Docker image แทน

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

## ขั้นตอนที่ 3 — ตั้งค่า ngrok

### 3.1 สมัครบัญชี ngrok (ฟรี)

ไปที่ https://dashboard.ngrok.com/signup

### 3.2 สร้าง Static Domain (ฟรี 1 domain)

1. Login → **Cloud Edge** → **Domains** → **New Domain**
2. จะได้ domain เช่น `your-name-abc.ngrok-free.dev`
3. จด domain นี้ไว้ใช้ในขั้นตอนถัดไป

> Static Domain ทำให้ URL ไม่เปลี่ยนทุกครั้งที่ restart — ไม่ต้องอัปเดต Google Console ซ้ำ

### 3.3 คัดลอก Authtoken

ไปที่ https://dashboard.ngrok.com/get-started/your-authtoken
คัดลอก token ยาว (ประมาณ 48 ตัวอักษร)

---

## ขั้นตอนที่ 4 — แก้ไขไฟล์ .env

เปิด `.env` แล้วแก้ค่าให้ตรงกับระบบ:

```env
# Timezone
TZ=Asia/Bangkok

# ─── Ngrok ───────────────────────────────────────────────
NGROK_AUTHTOKEN=ใส่-authtoken-ที่-copy-มา
NGROK_DOMAIN=your-name-abc.ngrok-free.dev       # ไม่ต้องมี https://
NGROK_URL=https://your-name-abc.ngrok-free.dev  # มี https://

# ─── N8N ─────────────────────────────────────────────────
# สร้างด้วย: node -e "console.log(require('crypto').randomBytes(16).toString('hex'))"
N8N_ENCRYPTION_KEY=random-32-char-string

# ─── Node-RED Admin Auth ─────────────────────────────────
# สร้าง hash ดูขั้นตอนที่ 5
NR_ADMIN_USERNAME=admin
NR_ADMIN_PASSWORD_HASH=$2b$08$REPLACE_THIS_WITH_REAL_HASH
```

---

## ขั้นตอนที่ 5 — ตั้งค่า Node-RED Admin Login

### 5.1 สร้าง Password Hash

เปิดเว็บ **https://bcrypt-generator.com**
1. ใส่ password ที่ต้องการ
2. เลือก rounds = **8** (จำนวนรอบการเข้ารหัส — ค่า default ของ Node-RED)
3. กด **Generate**
4. คัดลอก hash ที่ได้

ผลลัพธ์จะได้เช่น:
```
$2a$08$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ01234
```

### 5.2 ใส่ Hash ลงใน .env

```env
NR_ADMIN_USERNAME=admin
NR_ADMIN_PASSWORD_HASH=$2a$08$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ01234
```

> hash ขึ้นต้นด้วย `$2a$` หรือ `$2b$` — ถ้าไม่ใช่แสดงว่า copy ไม่ครบ

---

## ขั้นตอนที่ 6 — Pull Images และ Start Services

```bash
cd d:\NodeRed

# Pull images ทั้งหมด
docker compose pull

# Start ทุก service พร้อมกัน
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
nodered      nodered/node-red:latest  running (healthy)
n8n          n8nio/n8n:latest         running
ngrok        ngrok/ngrok:latest       running
```

ตรวจสอบ ngrok tunnel ขึ้นแล้ว:
```bash
docker logs ngrok
```
ควรเห็น: `started tunnel` และ URL ของ domain

---

## ขั้นตอนที่ 7 — ทดสอบเข้าใช้งาน

| Service | URL | Login |
|---------|-----|-------|
| Node-RED | http://localhost:1880 | username/password จาก `.env` |
| N8N (local) | http://localhost:5678 | สร้าง account ครั้งแรก |
| N8N (public) | `https://your-domain.ngrok-free.dev` | เดียวกับ local |
| ngrok Dashboard | http://localhost:4040 | ไม่ต้อง login |

---

## ขั้นตอนที่ 8 — ติดตั้ง OPC-UA Node ใน Node-RED (optional)

ข้ามขั้นตอนนี้ถ้ายังไม่ต้องการ OPC-UA

```bash
docker exec nodered npm install node-red-contrib-opcua --prefix /data
docker restart nodered
```

จากนั้นตั้งค่า OPC-UA endpoint ใน **Node-RED UI โดยตรง**:
- ดับเบิ้ลคลิก OpcUa-Client node → Endpoint → `opc.tcp://<IP>:4840`
- ไม่ต้องตั้งค่าใน `.env`

---

## ขั้นตอนที่ 9 — ตั้งค่า MQTT Credential ใน N8N

1. เปิด http://localhost:5678 → สร้างบัญชี Admin
2. Settings → Credentials → **Add Credential**
3. ค้นหา `MQTT` → เลือก **MQTT**
4. กรอก:
   - **Host:** `mosquitto` (ชื่อ service ใน Docker network — ไม่ใช่ `localhost`)
   - **Port:** `1883`
5. Save

---

## ขั้นตอนที่ 10 — Setup Google OAuth2 (Gmail / Google Drive)

> ข้ามขั้นตอนนี้ถ้ายังไม่ต้องการ Gmail / Google Drive

### 10.1 สร้าง Google Cloud Project

1. ไปที่ https://console.cloud.google.com
2. สร้าง Project ใหม่
3. Enable APIs: **Gmail API**, **Google Drive API**, **Generative Language API**

### 10.2 สร้าง OAuth2 Client ID

1. APIs & Services → **Credentials** → **Create Credentials** → **OAuth client ID**
2. Application type: **Web application**
3. Authorized redirect URIs → Add:
   ```
   https://your-domain.ngrok-free.dev/rest/oauth2-credential/callback
   ```
4. Save → เก็บ `Client ID` และ `Client Secret`

### 10.3 เพิ่ม Credentials ใน N8N

> **สำคัญ:** ต้องเปิด N8N ผ่าน ngrok URL เท่านั้น ไม่ใช่ localhost

1. เปิด `https://your-domain.ngrok-free.dev`
2. Settings → Credentials → Add Credential
3. Gmail: **Gmail OAuth2 API** → ใส่ Client ID + Secret → **Connect**
4. Drive: **Google Drive OAuth2 API** → ใส่ Client ID + Secret → **Connect**

### 10.4 Gemini API Key

1. สร้าง API Key ที่ https://aistudio.google.com/app/apikey
2. N8N: Settings → Credentials → New → **Google Gemini(PaLM) Api** → วาง Key

---

## ขั้นตอนที่ 11 — ทดสอบ MQTT

```bash
# Subscribe ดูข้อมูลทุก topic
docker exec -it mosquitto mosquitto_sub -t "smartfarm/#" -v

# เปิด terminal ใหม่ แล้ว publish ทดสอบ
docker exec mosquitto mosquitto_pub \
    -t "smartfarm/ESP32-FARM-001/telemetry" \
    -m '{"device":"ESP32-FARM-001","temperature":28.5,"humidity":65.2}'
```

หรือใช้ GUI: [MQTT Explorer](https://mqtt-explorer.com) → เชื่อมที่ `localhost:1883`

---

## คำสั่งที่ใช้บ่อย

```bash
# ดู status ทุก service
docker compose ps

# ดู logs
docker compose logs -f
docker compose logs -f ngrok
docker compose logs -f n8n
docker compose logs -f nodered
docker compose logs -f mosquitto

# Restart service เดียว (หลังแก้ .env)
docker compose up -d --force-recreate ngrok
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
- [ ] สมัครบัญชี ngrok + สร้าง Static Domain
- [ ] แก้ไข `.env` — ใส่ `NGROK_AUTHTOKEN`, `NGROK_DOMAIN`, `NGROK_URL`
- [ ] แก้ไข `.env` — ตั้งค่า `N8N_ENCRYPTION_KEY`
- [ ] สร้าง bcrypt hash ที่ https://bcrypt-generator.com (rounds=8 — ค่า default ของ Node-RED)
- [ ] ใส่ hash ลงใน `.env` ที่ `NR_ADMIN_PASSWORD_HASH`
- [ ] `docker compose pull` แล้ว `docker compose up -d`
- [ ] ตรวจสอบ ngrok tunnel: `docker logs ngrok` หรือ http://localhost:4040
- [ ] ทดสอบ login Node-RED ที่ http://localhost:1880
- [ ] ทดสอบ login N8N ที่ http://localhost:5678
- [ ] ติดตั้ง `node-red-contrib-opcua` ใน Node-RED และตั้ง endpoint ใน UI (ถ้าใช้ OPC-UA)
- [ ] ตั้งค่า MQTT Credential ใน N8N (host: `mosquitto`, port: `1883`)

### Setup OAuth2 (Google Services)
- [ ] Google Cloud: Enable Gmail API + Drive API + Generative Language API
- [ ] Google Cloud: สร้าง OAuth2 Client ID + ใส่ redirect URI
- [ ] เพิ่ม Gmail + Drive Credentials ใน N8N (ผ่าน ngrok URL เท่านั้น)
- [ ] สร้าง Gemini API Key + เพิ่มใน N8N

### ทดสอบ
- [ ] MQTT: `mosquitto_pub` → `mosquitto_sub` → รับได้
- [ ] Node-RED: OPC UA Client เชื่อม OPC Server ได้ — ตั้ง endpoint `opc.tcp://<IP>:4840` ใน node โดยตรง (ถ้าใช้ OPC-UA)
- [ ] N8N: MQTT Trigger รับข้อมูลจาก Node-RED ได้
- [ ] N8N: Gmail / Drive OAuth2 status = Connected

---

## Troubleshooting

| ปัญหา | วิธีแก้ |
|-------|---------|
| Node-RED login ไม่ได้ | `NR_ADMIN_PASSWORD_HASH` ต้องขึ้นต้นด้วย `$2b$` — ตรวจสอบว่า copy ครบ |
| Node-RED เข้าได้โดยไม่มี login | `NR_ADMIN_PASSWORD_HASH` ว่างหรือไม่ได้ส่งเข้า container |
| ngrok ไม่ขึ้น | `docker logs ngrok` — มักเป็น `NGROK_AUTHTOKEN` ผิดหรือ domain ไม่ตรง |
| OAuth2 callback ล้มเหลว | ต้องเปิด N8N ผ่าน ngrok URL ไม่ใช่ localhost |
| N8N เชื่อม MQTT ไม่ได้ | ใช้ hostname `mosquitto` ไม่ใช่ `localhost` |
| `mosquitto unhealthy` | `docker logs mosquitto` — มักเป็น mosquitto.conf ผิด |
| Node-RED ไม่โหลด OPC node | `docker restart nodered` แล้วรอ 30 วิ |
| Port 1883 ถูกใช้งาน | `netstat -ano \| findstr :1883` หา PID แล้ว `taskkill /PID xxx /F` |
| Docker ไม่ start | เปิด Docker Desktop ก่อนแล้วรอ engine พร้อม |
