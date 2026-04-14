# Node-RED + N8N + Grafana + InfluxDB + MQTT Stack (Docker)

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
                                    └────┬───────┬────┘
                                         │       │
                              MQTT       │       │ InfluxDB Line Protocol
                          (port 1883)    │       │ (port 8086)
                                    ┌────▼────┐  ┌────▼────────┐
                                    │Mosquitto│  │  InfluxDB   │  Time-Series DB
                                    │  MQTT   │  │ (port 8086) │  เก็บข้อมูล sensor
                                    │  Broker │  └────┬────────┘
                                    └────┬────┘       │ Flux Query
                                         │       ┌────▼────────┐
                                         │       │   Grafana   │  Dashboard & Visualization
                                         │       │ (port 3000) │
                                         │       └─────────────┘
                                    MQTT │
                                    ┌────▼────────┐
                                    │     N8N     │  Workflow Automation
                                    │ (port 5678) │  Gemini / Gmail / Drive
                                    └────┬────────┘
                                         │ tunnel (Docker internal)
                                    ┌────▼────────┐
                                    │    ngrok    │  Public HTTPS → N8N:5678
                                    │  (Docker)   │  ใช้สำหรับ OAuth2 / Webhook
                                    │ (port 4040) │  Dashboard: localhost:4040
                                    └─────────────┘
```

> **ngrok รันเป็น Docker container** — ไม่ต้องติดตั้งโปรแกรมเพิ่มในเครื่อง  
> รันและหยุดพร้อม `docker compose up/down` อัตโนมัติ

---

## Services สรุป

| Service | URL / Port | หมายเหตุ |
|---------|-----------|---------|
| Node-RED UI | http://localhost:1880 | Flow editor + OPC-UA + MQTT |
| InfluxDB UI | http://localhost:8086 | Time-series database + Data Explorer |
| Grafana UI | http://localhost:3000 | Dashboard & Visualization |
| N8N UI (local) | http://localhost:5678 | Workflow automation |
| N8N UI (public) | `https://<NGROK_DOMAIN>` | ใช้สำหรับ OAuth2 / Webhook |
| ngrok Dashboard | http://localhost:4040 | ดู tunnel status |
| MQTT Broker | `localhost:1883` | จาก Windows host / ESP32 |
| MQTT (Docker internal) | `mosquitto:1883` | จาก container อื่น |
| MQTT WebSocket | `localhost:9001` | สำหรับ browser client |

---

## โครงสร้างไฟล์

```
d:\NodeRed\
  ├── .env                        ← ตั้งค่าทั้งหมดไว้ที่นี่ (ไม่อยู่ใน Git)
  ├── .env.example                ← template สำหรับ copy เป็น .env
  ├── docker-compose.yml          ← กำหนด services ทั้งหมด (6 services)
  ├── setup.bat                   ← Management script (Windows)
  ├── setup.sh                    ← Management script (Linux / VPS)
  ├── INSTALL.md                  ← คู่มือติดตั้งฉบับเต็ม
  ├── VPS_DEPLOY.md               ← คู่มือ deploy ไป VPS
  ├── mosquitto\
  │     └── config\
  │           └── mosquitto.conf  ← config ของ MQTT broker
  ├── nodered\
  │     └── settings.js           ← config ของ Node-RED
  └── grafana\
        └── provisioning\
              └── datasources\
                    └── influxdb.yml  ← auto-configure InfluxDB datasource
```

---

## ไฟล์ .env (ตั้งค่าก่อนรัน)

```env
# ─── Timezone ────────────────────────────────────────────
TZ=Asia/Bangkok

# ─── Ngrok ───────────────────────────────────────────────
NGROK_AUTHTOKEN=your-authtoken-here
NGROK_DOMAIN=your-domain.ngrok-free.dev      # ไม่มี https://
NGROK_URL=https://your-domain.ngrok-free.dev # มี https://

# ─── N8N ─────────────────────────────────────────────────
N8N_ENCRYPTION_KEY=change-this-to-random-32-char-string

# ─── Node-RED Admin Auth ─────────────────────────────────
NR_ADMIN_USERNAME=admin
NR_ADMIN_PASSWORD_HASH=$2b$08$REPLACE_THIS_WITH_REAL_HASH

# ─── OPC Server ──────────────────────────────────────────
OPC_SERVER_IP=192.168.1.100
OPC_SERVER_PORT=4840

# ─── InfluxDB ────────────────────────────────────────────
INFLUXDB_ORG=iot
INFLUXDB_BUCKET=sensors
INFLUXDB_USERNAME=admin
INFLUXDB_PASSWORD=ChangeMe1234!
INFLUXDB_TOKEN=change-this-to-random-64-char-string

# ─── Grafana ─────────────────────────────────────────────
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=ChangeMe1234!
```

### Generate INFLUXDB_TOKEN

เลือกวิธีใดวิธีหนึ่ง:

```bash
# Node.js
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

# PowerShell
-join ((1..64) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) })

# Docker
docker run --rm alpine sh -c "cat /dev/urandom | tr -dc 'a-f0-9' | head -c 64"
```

### Generate NR_ADMIN_PASSWORD_HASH

```bash
# Docker (ไม่ต้องติดตั้ง Node.js)
docker run --rm -it nodered/node-red node-red-admin hash-pw
```

> หมายเหตุ `NGROK_DOMAIN` vs `NGROK_URL`:  
> ngrok CLI รับแค่ hostname เปล่า → ใช้ `NGROK_DOMAIN`  
> N8N ต้องการ URL เต็ม → ใช้ `NGROK_URL`

---

## docker-compose.yml — Services ทั้งหมด

### Service 1: influxdb (Time-Series Database)

```yaml
influxdb:
  image: influxdb:2
  ports:
    - "8086:8086"
  environment:
    - DOCKER_INFLUXDB_INIT_MODE=setup       # auto-setup ครั้งแรก
    - DOCKER_INFLUXDB_INIT_USERNAME=...
    - DOCKER_INFLUXDB_INIT_PASSWORD=...
    - DOCKER_INFLUXDB_INIT_ORG=iot
    - DOCKER_INFLUXDB_INIT_BUCKET=sensors
    - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=...
  healthcheck:
    test: ["CMD", "influx", "ping"]
```

- ตั้งค่า org/bucket/token อัตโนมัติผ่าน `DOCKER_INFLUXDB_INIT_*`
- Services อื่นรอ InfluxDB healthy ก่อนผ่าน `depends_on: condition: service_healthy`

### Service 2: grafana (Dashboard)

```yaml
grafana:
  image: grafana/grafana:latest
  ports:
    - "3000:3000"
  volumes:
    - grafana_data:/var/lib/grafana
    - ./grafana/provisioning:/etc/grafana/provisioning:ro
  depends_on:
    influxdb:
      condition: service_healthy
```

- `grafana/provisioning/datasources/influxdb.yml` — auto-configure InfluxDB datasource ตั้งแต่ start ครั้งแรก ไม่ต้องตั้งค่าด้วยมือ

### Service 3: mosquitto (MQTT Broker)

```yaml
mosquitto:
  image: eclipse-mosquitto:2
  ports:
    - "1883:1883"   # MQTT protocol
    - "9001:9001"   # WebSocket
  healthcheck:
    test: ["CMD", "mosquitto_sub", "-t", "$$SYS/#", "-C", "1", "-W", "3"]
```

### Service 4: nodered (OPC-UA + MQTT + InfluxDB)

```yaml
nodered:
  image: nodered/node-red:latest
  ports:
    - "1880:1880"
  depends_on:
    mosquitto:
      condition: service_healthy
```

Nodes ที่ต้องติดตั้งเพิ่ม:
```bash
docker exec nodered npm install node-red-contrib-opcua --prefix /data
docker exec nodered npm install node-red-contrib-influxdb --prefix /data
docker restart nodered
```

### Service 5: n8n (Workflow Automation)

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

### Service 6: ngrok (Tunnel)

```yaml
ngrok:
  image: ngrok/ngrok:latest
  command: http --domain=${NGROK_DOMAIN} n8n:5678
  ports:
    - "4040:4040"
```

---

## Data Flow

```
ESP32 / PLC / OPC-UA
        │
        ▼
    Node-RED  ──── MQTT ────►  Mosquitto  ────►  N8N (automation)
        │
        │ node-red-contrib-influxdb
        ▼
    InfluxDB (เก็บข้อมูล time-series)
        │
        │ Flux Query
        ▼
    Grafana (แสดงผล Dashboard)
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
docker compose logs -f influxdb
docker compose logs -f grafana
docker compose logs -f ngrok

# Restart service เดียว (หลังแก้ .env)
docker compose up -d --force-recreate grafana
docker compose up -d --force-recreate influxdb
docker compose up -d --force-recreate n8n

# หยุดทั้งหมด (volumes ยังอยู่)
docker compose down

# ลบทุกอย่างรวม volumes (ข้อมูลหาย!)
docker compose down -v
```

---

## MQTT Topic Structure

| Topic | ทิศทาง | ใช้งาน |
|-------|--------|--------|
| `plc/data/temperature` | Node-RED → N8N / InfluxDB | ค่า Sensor อุณหภูมิ |
| `plc/data/pressure` | Node-RED → N8N / InfluxDB | ค่า Sensor ความดัน |
| `plc/data/status` | Node-RED → N8N | สถานะเครื่องจักร |
| `plc/command/setpoint` | N8N → Node-RED | สั่งค่า Setpoint |
| `plc/command/start` | N8N → Node-RED | สั่งเดินเครื่อง |
| `plc/command/stop` | N8N → Node-RED | สั่งหยุดเครื่อง |

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
| InfluxDB ไม่ start | `INFLUXDB_PASSWORD` ต้องยาว 8+ ตัวอักษร |
| Grafana datasource error | ตรวจ `INFLUXDB_TOKEN` ใน `.env` ต้องตรงกัน |
| ไม่เห็นข้อมูลใน Grafana | ตรวจ Node-RED flow — InfluxDB Out node ตั้ง bucket/org ให้ถูก |
| Port 1883 ถูกใช้งาน | `netstat -ano \| findstr :1883` หา PID แล้ว `taskkill /PID xxx /F` |
