# IoT Automation Stack (Docker)

NodeRED + N8N + Home Assistant + InfluxDB + Grafana + Nginx Proxy Manager + Cloudflare Tunnel

---

## สถาปัตยกรรมระบบ

```
Internet
   │
   │  HTTPS (Cloudflare Tunnel)
   ▼
┌──────────────────┐
│   Cloudflare     │  Zero Trust Tunnel
│   Network        │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐     ┌────────────────────┐
│ Nginx Proxy Mgr  │────►│       N8N          │  Workflow Automation
│  port 80/443/81  │     │    port 5678       │  AI / Gmail / Sheets
└──────────────────┘     └────────────────────┘
         │
         ├────────────────►  NodeRED    (port 1880)  Flow-based IoT
         ├────────────────►  InfluxDB   (port 8086)  Time-series DB
         ├────────────────►  Grafana    (port 3000)  Dashboard
         └────────────────►  HomeAsst   (port 8123)  Home Automation

┌──────────────────┐     ┌────────────────────┐
│   Mosquitto      │────►│     NodeRED        │
│  MQTT Broker     │     │                    │
│  port 1883/9001  │     └────────────────────┘
└──────────────────┘

┌──────────────────┐
│   PostgreSQL     │  N8N backend database
│   port 5432      │
└──────────────────┘
```

---

## Services

| Service | URL / Port | หมายเหตุ |
|---------|-----------|---------|
| Node-RED | http://localhost:1880 | Flow editor + MQTT + OPC-UA |
| N8N (local) | http://localhost:5678 | Workflow automation |
| N8N (public) | `https://<N8N_DOMAIN>` | ผ่าน Cloudflare Tunnel |
| Home Assistant | http://localhost:8123 | Home automation |
| InfluxDB | http://localhost:8086 | Time-series database UI |
| Grafana | http://localhost:3000 | Dashboard (admin / GRAFANA_ADMIN_PASSWORD) |
| Nginx Proxy Manager | http://localhost:81 | Reverse proxy admin (admin@example.com / changeme) |
| MQTT Broker | `localhost:1883` | จาก host / ESP32 |
| MQTT (Docker internal) | `mosquitto:1883` | จาก container อื่น |
| MQTT WebSocket | `localhost:9001` | สำหรับ browser client |

---

## โครงสร้างไฟล์

```
NodeRed-ForAllSystem/
  ├── .env                        ← ตั้งค่าทั้งหมด (ไม่อยู่ใน Git)
  ├── .env.example                ← Template สำหรับ .env
  ├── docker-compose.yml          ← กำหนด services ทั้งหมด
  ├── README.md                   ← เอกสารภาพรวม
  ├── INSTALL.md                  ← คู่มือติดตั้งทีละขั้นตอน
  ├── PROJECT-MANUAL.md           ← คู่มือระบบ Smart Energy
  ├── mosquitto/config/
  │     └── mosquitto.conf        ← MQTT broker config
  ├── nodered/
  │     └── settings.js           ← Node-RED config
  ├── flows/                      ← Node-RED / N8N flow exports
  └── esp32-firmware-NodeRED/     ← Firmware ESP32
```

---

## ตัวแปร .env

```env
# Timezone
TZ=Asia/Bangkok

# Cloudflare Tunnel
CLOUDFLARE_TUNNEL_TOKEN=your-tunnel-token
N8N_DOMAIN=n8n.yourdomain.com

# N8N
N8N_ENCRYPTION_KEY=random-32-char-hex     # openssl rand -hex 16

# PostgreSQL (N8N backend)
POSTGRES_USER=iot_user
POSTGRES_PASSWORD=strong-password
POSTGRES_DB=iot_db

# InfluxDB
INFLUXDB_USERNAME=admin
INFLUXDB_PASSWORD=strong-password
INFLUXDB_ORG=iot_org
INFLUXDB_BUCKET=iot_bucket
INFLUXDB_ADMIN_TOKEN=random-64-char-hex   # openssl rand -hex 32

# Grafana
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=strong-password
```

---

## Services ใน docker-compose.yml

| Container | Image | หน้าที่ |
|-----------|-------|---------|
| `mosquitto` | eclipse-mosquitto:2 | MQTT Broker |
| `postgres` | postgres:16 | Database สำหรับ N8N |
| `influxdb` | influxdb:2.7 | Time-series database |
| `nodered` | nodered/node-red:latest | Flow automation |
| `n8n` | n8nio/n8n:latest | Workflow automation |
| `homeassistant` | homeassistant/home-assistant:stable | Home automation |
| `grafana` | grafana/grafana:latest | Data visualization |
| `nginx-proxy-manager` | jc21/nginx-proxy-manager:latest | Reverse proxy |
| `cloudflared` | cloudflare/cloudflared:latest | Cloudflare Tunnel |

---

## Data Flow

```
ESP32 / Sensor / PLC
        │  MQTT
        ▼
   Mosquitto ──► NodeRED ──► InfluxDB ──► Grafana
                    │
                    └────────► N8N ──► AI / Gmail / Sheets
                                │
                         Home Assistant
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
docker compose logs -f n8n
docker compose logs -f cloudflared

# Restart service เดียว
docker compose up -d --force-recreate n8n
docker compose up -d --force-recreate cloudflared

# หยุดทั้งหมด (volumes ยังอยู่)
docker compose down

# ลบทุกอย่างรวม volumes (ข้อมูลหาย!)
docker compose down -v
```

---

## MQTT Topic Structure

| Topic | ทิศทาง | ใช้งาน |
|-------|--------|--------|
| `smartfarm/<DEVICE_ID>/telemetry` | ESP32 → Broker | ข้อมูล sensor |
| `smartfarm/<DEVICE_ID>/status` | ESP32 → Broker | สถานะ online/offline |
| `smartfarm/<DEVICE_ID>/command` | N8N/NodeRED → ESP32 | ควบคุม relay |

---

## Cloudflare Tunnel Setup

1. ไปที่ [Cloudflare Zero Trust](https://one.dash.cloudflare.com) → Networks → Tunnels
2. สร้าง Tunnel → คัดลอก **token** → ใส่ใน `.env`
3. เพิ่ม **Public Hostname**: `n8n.yourdomain.com` → `http://nginx-proxy-manager:80`
4. ใน **Nginx Proxy Manager** (http://localhost:81) เพิ่ม Proxy Host:
   - Domain: `n8n.yourdomain.com`
   - Forward Hostname: `n8n`
   - Forward Port: `5678`

---

## OAuth2 Setup (Gmail / Google Drive)

1. Google Console → Create OAuth2 Client ID
2. Authorized redirect URIs:
   ```
   https://n8n.yourdomain.com/rest/oauth2-credential/callback
   ```
3. เปิด N8N **ผ่าน Cloudflare URL เท่านั้น** เมื่อทำ OAuth2

---

## Troubleshooting

| ปัญหา | วิธีแก้ |
|-------|---------|
| cloudflared ไม่ขึ้น | `docker logs cloudflared` — ตรวจ `CLOUDFLARE_TUNNEL_TOKEN` ใน `.env` |
| OAuth2 callback ล้มเหลว | เปิด N8N ผ่าน Cloudflare domain ไม่ใช่ localhost |
| N8N เชื่อม MQTT ไม่ได้ | ใช้ hostname `mosquitto` ไม่ใช่ `localhost` |
| N8N เชื่อม NodeRED ไม่ได้ | ใช้ `http://nodered:1880` ไม่ใช่ localhost |
| `mosquitto unhealthy` | `docker logs mosquitto` — ตรวจ mosquitto.conf |
| `postgres unhealthy` | `docker logs postgres` — ตรวจ POSTGRES_* ใน .env |
| InfluxDB init ล้มเหลว | ลบ volume แล้วรันใหม่: `docker compose down -v influxdb` |
| Nginx Proxy Manager ไม่ขึ้น | รอ 30 วิ แล้วเช็ค port 81 อีกครั้ง |
| Port ถูกใช้งานอยู่ (Mac) | `lsof -i :1883` หา PID แล้ว `kill <PID>` |
