# คู่มือติดตั้ง IoT Automation Stack (Docker)

NodeRED + N8N + Home Assistant + InfluxDB + Grafana + Nginx Proxy Manager + Cloudflare Tunnel

---

## สิ่งที่ต้องมีก่อนเริ่ม

| รายการ | ตรวจสอบ |
|--------|---------|
| Docker Desktop | https://www.docker.com/products/docker-desktop |
| บัญชี Cloudflare (ฟรี) | https://dash.cloudflare.com/sign-up |
| โดเมนที่ชี้มา Cloudflare | ต้องมี domain ใน Cloudflare DNS |
| RAM | แนะนำ 8 GB ขึ้นไป |
| Disk ว่าง | 10 GB ขึ้นไป |

---

## ขั้นตอนที่ 1 — ติดตั้ง Docker

**Mac / Linux:**
```bash
# ติดตั้ง Docker Desktop จาก https://www.docker.com/products/docker-desktop
# จากนั้นตรวจสอบ:
docker --version
docker compose version
```

**Windows:**
```powershell
winget install Docker.DockerDesktop
```
Settings → General → เปิด **Use WSL 2 based engine** → Apply & Restart

---

## ขั้นตอนที่ 2 — สร้าง Cloudflare Tunnel

### 2.1 สร้าง Tunnel
1. ไปที่ https://one.dash.cloudflare.com
2. Networks → **Tunnels** → **Create a tunnel**
3. ตั้งชื่อ tunnel เช่น `iot-stack`
4. เลือก **Docker** → คัดลอก token จาก command ที่ได้ (ส่วนที่อยู่หลัง `--token`)

### 2.2 ตั้งค่า Public Hostname
ใน Tunnel → Public Hostname → Add:

| Field | ค่า |
|-------|-----|
| Subdomain | `n8n` |
| Domain | `yourdomain.com` |
| Service Type | HTTP |
| URL | `nginx-proxy-manager:80` |

---

## ขั้นตอนที่ 3 — ตั้งค่าไฟล์ .env

```bash
cp .env.example .env
```

แก้ไข `.env` ให้ครบทุกค่า:

```env
TZ=Asia/Bangkok

# Cloudflare
CLOUDFLARE_TUNNEL_TOKEN=ใส่-token-จาก-ขั้นตอน-2.1
N8N_DOMAIN=n8n.yourdomain.com

# N8N Encryption Key (สร้างด้วย: openssl rand -hex 16)
N8N_ENCRYPTION_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# PostgreSQL
POSTGRES_USER=iot_user
POSTGRES_PASSWORD=ตั้ง-password-ที่แข็งแกร่ง
POSTGRES_DB=iot_db

# InfluxDB
INFLUXDB_USERNAME=admin
INFLUXDB_PASSWORD=ตั้ง-password-ที่แข็งแกร่ง
INFLUXDB_ORG=iot_org
INFLUXDB_BUCKET=iot_bucket
# สร้างด้วย: openssl rand -hex 32
INFLUXDB_ADMIN_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Grafana
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=ตั้ง-password-ที่แข็งแกร่ง
```

---

## ขั้นตอนที่ 4 — Pull Images และ Start Stack

```bash
# Pull images ทั้งหมด
docker compose pull

# Start ทุก service
docker compose up -d

# ตรวจสอบสถานะ
docker compose ps
```

ผลลัพธ์ที่ควรเห็น (ทุก service ต้อง running):

```
NAME                 STATUS
mosquitto            running (healthy)
postgres             running (healthy)
influxdb             running (healthy)
nodered              running
n8n                  running
homeassistant        running (healthy)
grafana              running
nginx-proxy-manager  running (healthy)
cloudflared          running
```

---

## ขั้นตอนที่ 5 — ตั้งค่า Nginx Proxy Manager

1. เปิด http://localhost:81
2. Login: `admin@example.com` / `changeme` (เปลี่ยน password ทันทีหลัง login)
3. Hosts → **Proxy Hosts** → **Add Proxy Host**:

| Field | ค่า |
|-------|-----|
| Domain Names | `n8n.yourdomain.com` |
| Scheme | http |
| Forward Hostname | `n8n` |
| Forward Port | `5678` |
| Websockets Support | ✅ เปิด |

---

## ขั้นตอนที่ 6 — ตั้งค่า InfluxDB

1. เปิด http://localhost:8086
2. Login ด้วย `INFLUXDB_USERNAME` / `INFLUXDB_PASSWORD` (ที่ตั้งใน .env)
3. Organization, Bucket ถูกสร้างอัตโนมัติจาก .env แล้ว
4. ไปที่ **Load Data → API Tokens** → คัดลอก token สำหรับใช้ใน Node-RED / Grafana

---

## ขั้นตอนที่ 7 — ตั้งค่า Grafana

1. เปิด http://localhost:3000
2. Login: `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD`
3. **Connections → Data Sources → Add** → เลือก **InfluxDB**:

| Field | ค่า |
|-------|-----|
| Query Language | Flux |
| URL | `http://influxdb:8086` |
| Organization | ค่า `INFLUXDB_ORG` ใน .env |
| Token | ค่า `INFLUXDB_ADMIN_TOKEN` ใน .env |
| Default Bucket | ค่า `INFLUXDB_BUCKET` ใน .env |

4. **Save & Test** → ต้องขึ้น "datasource is working"

---

## ขั้นตอนที่ 8 — ตั้งค่า Home Assistant

1. เปิด http://localhost:8123
2. ทำตาม Onboarding wizard ครั้งแรก (ตั้งชื่อบ้าน, timezone, account)
3. ตั้งค่า MQTT Integration:
   - Settings → Devices & Services → **Add Integration** → ค้นหา **MQTT**
   - Broker: `mosquitto`, Port: `1883`

---

## ขั้นตอนที่ 9 — ตั้งค่า N8N

1. เปิด http://localhost:5678 → สร้าง Admin account
2. Settings → **Credentials** → เพิ่ม credentials ตามต้องการ:

**MQTT:**
- Host: `mosquitto`, Port: `1883`

**InfluxDB:**
- URL: `http://influxdb:8086`
- Token: ค่า `INFLUXDB_ADMIN_TOKEN`
- Organization: ค่า `INFLUXDB_ORG`

**Google Sheets / Gmail (OAuth2):**
> ต้องเปิด N8N **ผ่าน Cloudflare URL** (`https://n8n.yourdomain.com`) เท่านั้น
- Redirect URI: `https://n8n.yourdomain.com/rest/oauth2-credential/callback`

---

## ขั้นตอนที่ 10 — ทดสอบ MQTT

```bash
# Subscribe ดูข้อมูล
docker exec -it mosquitto mosquitto_sub -t "smartfarm/#" -v

# Publish ทดสอบ (เปิด terminal ใหม่)
docker exec mosquitto mosquitto_pub \
    -t "smartfarm/ESP32-001/telemetry" \
    -m '{"device":"ESP32-001","temperature":28.5}'
```

---

## คำสั่งที่ใช้บ่อย

```bash
# ดู status ทุก service
docker compose ps

# ดู logs
docker compose logs -f
docker compose logs -f cloudflared
docker compose logs -f n8n
docker compose logs -f homeassistant

# Restart service เดียว
docker compose up -d --force-recreate n8n
docker compose up -d --force-recreate cloudflared

# หยุดทั้งหมด
docker compose down

# ลบทุกอย่างรวม volumes (ข้อมูลหาย!)
docker compose down -v
```

---

## Checklist ติดตั้งครั้งแรก

### Infrastructure
- [ ] ติดตั้ง Docker Desktop
- [ ] สร้าง Cloudflare Tunnel + คัดลอก token
- [ ] ตั้งค่า Public Hostname ใน Cloudflare Dashboard
- [ ] คัดลอก `.env.example` → `.env` แล้วแก้ค่าทุกช่อง
- [ ] `docker compose pull` แล้ว `docker compose up -d`
- [ ] ตรวจสอบทุก service แสดง `running`: `docker compose ps`

### Services
- [ ] Nginx Proxy Manager: เพิ่ม Proxy Host สำหรับ `n8n.yourdomain.com`
- [ ] InfluxDB: login ได้ที่ http://localhost:8086
- [ ] Grafana: เพิ่ม InfluxDB datasource + test ผ่าน
- [ ] Home Assistant: ทำ onboarding ครั้งแรก + เพิ่ม MQTT integration
- [ ] N8N: สร้าง account + ตั้งค่า MQTT credential

### การเข้าถึงจาก internet
- [ ] เปิด `https://n8n.yourdomain.com` ได้จาก internet
- [ ] `docker logs cloudflared` ไม่มี error

---

## Troubleshooting

| ปัญหา | วิธีแก้ |
|-------|---------|
| cloudflared ไม่ขึ้น | `docker logs cloudflared` — ตรวจ `CLOUDFLARE_TUNNEL_TOKEN` ใน `.env` |
| N8N เปิดผ่าน domain ไม่ได้ | ตรวจว่า Nginx Proxy Manager เพิ่ม Proxy Host แล้ว |
| OAuth2 callback ล้มเหลว | เปิด N8N ผ่าน Cloudflare domain ไม่ใช่ localhost |
| N8N เชื่อม MQTT ไม่ได้ | ใช้ hostname `mosquitto` ไม่ใช่ `localhost` |
| N8N เชื่อม NodeRED ไม่ได้ | ใช้ `http://nodered:1880` ไม่ใช่ localhost |
| `influxdb unhealthy` | ลบ volume แล้วรันใหม่: `docker compose down influxdb && docker volume rm ..._influxdb_data` |
| `postgres unhealthy` | `docker logs postgres` — ตรวจ POSTGRES_* ใน .env |
| `mosquitto unhealthy` | `docker logs mosquitto` — ตรวจ mosquitto.conf |
| Port 80/443 ถูกใช้งาน | ตรวจว่าไม่มี web server อื่นรันอยู่บนเครื่อง |
| Home Assistant ช้า | start_period 60s — รอก่อนดู healthcheck |
