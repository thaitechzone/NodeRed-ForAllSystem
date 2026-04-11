# SmartFarm — ติดตั้งบน VPS (Contabo)

> **เป้าหมาย:** รัน Docker Stack เดิม (Node-RED + N8N + Mosquitto + Cloudflare Tunnel) บน VPS Linux  
> **VPS:** Contabo | **OS:** Ubuntu 22.04 LTS | **เครื่องมือ:** PuTTY (SSH), WinSCP (ถ่ายไฟล์)  
> **ผลลัพธ์:** เข้าใช้งานได้จากทุกที่ตลอด 24/7 โดยไม่ต้องเปิดคอมพิวเตอร์ที่บ้าน

---

## สารบัญ

1. [สิ่งที่ต้องเตรียม](#1-สิ่งที่ตองเตรียม)
2. [เชื่อมต่อ VPS ผ่าน PuTTY](#2-เชื่อมตอ-vps-ผาน-putty)
3. [ตั้งค่าเซิร์ฟเวอร์ครั้งแรก](#3-ตั้งคาเซิรฟเวอรครั้งแรก)
4. [ติดตั้ง Docker Engine](#4-ติดตั้ง-docker-engine)
5. [โอนไฟล์โปรเจกต์ขึ้น VPS](#5-โอนไฟลโปรเจกตขึ้น-vps)
6. [ตั้งค่าไฟล์ .env](#6-ตั้งคาไฟล-env)
7. [Start Docker Stack](#7-start-docker-stack)
8. [ตั้งค่า Public Hostname ใน Cloudflare](#8-ตั้งคา-public-hostname-ใน-cloudflare)
9. [ตั้งค่า Node-RED และ N8N](#9-ตั้งคา-node-red-และ-n8n)
10. [ทดสอบระบบ](#10-ทดสอบระบบ)
11. [คำสั่งที่ใช้บ่อยบน VPS](#11-คำสั่งที่ใชบอยบน-vps)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. สิ่งที่ต้องเตรียม

### VPS Contabo
- สั่งซื้อที่ [contabo.com](https://contabo.com) → **Cloud VPS** หรือ **VPS S** ขึ้นไป
- เลือก OS: **Ubuntu 22.04 LTS** (แนะนำ)
- หลังสั่งซื้อ Contabo จะส่ง email มีข้อมูล:
  - **IP Address** เช่น `123.456.789.10`
  - **Root Password**

### โปรแกรมบนเครื่อง Windows
| โปรแกรม | ใช้ทำอะไร | ดาวน์โหลด |
|---------|----------|-----------|
| **PuTTY** | SSH เข้า VPS พิมพ์คำสั่ง | [putty.org](https://www.putty.org) |
| **WinSCP** | ถ่ายไฟล์ Windows → VPS | [winscp.net](https://winscp.net) |

### Cloudflare
- บัญชี Cloudflare + domain `thaitechsync.com` ที่ตั้งค่าไว้แล้ว
- Tunnel token (`eyJ...`) จาก Zero Trust Dashboard — ใช้ tunnel เดิมได้เลย

---

## 2. เชื่อมต่อ VPS ผ่าน PuTTY

### 2.1 ตั้งค่า PuTTY

1. เปิด PuTTY
2. กรอก **Host Name:** `123.456.789.10` (IP จาก email Contabo)
3. **Port:** `22`
4. **Connection type:** SSH
5. (ไม่บังคับ) Saved Sessions → ตั้งชื่อ `contabo-smartfarm` → **Save**
6. คลิก **Open**

### 2.2 Login ครั้งแรก

```
login as: root
root@123.456.789.10's password: [ใส่ password จาก email Contabo]
```

> PuTTY อาจถาม "The server's host key is not cached" → คลิก **Accept**

เมื่อ login สำเร็จจะเห็น:
```
root@vps-xxxxxxxxx:~#
```

---

## 3. ตั้งค่าเซิร์ฟเวอร์ครั้งแรก

### 3.1 อัปเดต System

```bash
apt update && apt upgrade -y
```

### 3.2 สร้าง User สำหรับใช้งาน (แนะนำ — ไม่ใช้ root ตลอด)

```bash
# สร้าง user ชื่อ smartfarm
adduser smartfarm

# เพิ่มเข้ากลุ่ม sudo และ docker
usermod -aG sudo smartfarm
```

### 3.3 ตั้งค่า Firewall (UFW)

```bash
# เปิด UFW
ufw allow OpenSSH
ufw allow 1880/tcp    # Node-RED (เฉพาะถ้าต้องการเข้าโดยตรง — ไม่จำเป็นถ้าใช้ Cloudflare Tunnel)
ufw allow 1883/tcp    # MQTT
ufw enable
```

ตรวจสอบ:
```bash
ufw status
```

> **หมายเหตุ:** Port 5678 (N8N) และ 1880 (Node-RED) ไม่จำเป็นต้องเปิดถ้าเข้าผ่าน Cloudflare Tunnel เท่านั้น  
> เปิด port 1880 เฉพาะถ้าต้องการเข้า Node-RED โดยตรงจาก IP (ไม่แนะนำสำหรับ production)

### 3.4 ติดตั้ง Tools พื้นฐาน

```bash
apt install -y git curl wget nano unzip
```

---

## 4. ติดตั้ง Docker Engine

> Docker บน Linux ใช้ **Docker Engine** (ไม่ใช่ Docker Desktop)  
> ขั้นตอนนี้ทำครั้งเดียว

### 4.1 ติดตั้ง Docker Engine

```bash
# เพิ่ม Docker GPG key และ repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

# ติดตั้ง
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

### 4.2 เพิ่ม User เข้ากลุ่ม docker

```bash
usermod -aG docker smartfarm
```

### 4.3 ตรวจสอบ

```bash
docker --version
docker compose version
```

ผลลัพธ์ที่ควรเห็น:
```
Docker version 26.x.x, build xxxxxxx
Docker Compose version v2.x.x
```

### 4.4 ตั้งค่าให้ Docker start อัตโนมัติเมื่อ VPS reboot

```bash
systemctl enable docker
systemctl start docker
```

---

## 5. โอนไฟล์โปรเจกต์ขึ้น VPS

เลือกวิธีใดวิธีหนึ่ง:

---

### วิธี A — ใช้ Git (แนะนำ ถ้าโปรเจกต์อยู่บน GitHub)

```bash
# บน VPS — clone เฉพาะ branch ที่ต้องการ
cd /opt
git clone -b 02_cloudflare_Connect https://github.com/YOUR_USERNAME/YOUR_REPO.git smartfarm
cd smartfarm
```

> **ถ้า clone ไปแล้ว** แล้วค่อย checkout branch:
> ```bash
> git checkout 02_cloudflare_Connect
> ```
>
> ตรวจสอบว่า checkout ถูก branch:
> ```bash
> git branch
> # ควรเห็น * 02_cloudflare_Connect
> ```

---

### วิธี B — ใช้ WinSCP (ถ่ายไฟล์จาก Windows โดยตรง)

**บนเครื่อง Windows — เปิด WinSCP:**

1. เปิด WinSCP → **New Session**
2. กรอก:
   - **File protocol:** SFTP
   - **Host name:** `123.456.789.10`
   - **Port:** `22`
   - **User name:** `root`
   - **Password:** (password Contabo)
3. คลิก **Login**
4. ฝั่งขวา (VPS) นำทางไปที่ `/opt/`
5. สร้างโฟลเดอร์ใหม่ชื่อ `smartfarm`
6. ลากไฟล์จากเครื่อง Windows (ฝั่งซ้าย) ไปวางที่ `/opt/smartfarm/`

ไฟล์ที่ต้องโอน:
```
docker-compose.yml
.env
mosquitto/
nodered/
flows/
```

> **หมายเหตุ:** ไม่ต้องโอนไฟล์ `.md` — ไม่จำเป็นสำหรับการรันระบบ

---

### ตรวจสอบไฟล์บน VPS

```bash
ls -la /opt/smartfarm/
```

ควรเห็น:
```
docker-compose.yml
.env
mosquitto/
nodered/
flows/
```

---

## 6. ตั้งค่าไฟล์ .env

```bash
cd /opt/smartfarm
nano .env
```

แก้ไขค่าให้ครบ:

```env
# ─── Timezone ────────────────────────────────────────────
TZ=Asia/Bangkok

# ─── Cloudflare Tunnel ───────────────────────────────────
CLOUDFLARE_TUNNEL_TOKEN=eyJhIjoixxxxxxxxxxxxxxxxxxxxxxxx...
CF_TUNNEL_URL=https://n8n.thaitechsync.com

# ─── N8N ─────────────────────────────────────────────────
N8N_ENCRYPTION_KEY=change-this-to-random-32-char-string

# ─── OPC Server (ถ้าไม่มี OPC ปล่อยค่าเดิมได้) ──────────
OPC_SERVER_IP=192.168.1.100
OPC_SERVER_PORT=4840
```

บันทึก: กด `Ctrl+X` → `Y` → `Enter`

> **สร้าง N8N_ENCRYPTION_KEY แบบ random:**
> ```bash
> openssl rand -hex 16
> ```
> นำค่าที่ได้ไปใส่ใน `.env`

---

## 7. Start Docker Stack

```bash
cd /opt/smartfarm

# Pull images ทั้งหมด
docker compose pull

# Start ทั้งหมด (background)
docker compose up -d
```

### ตรวจสอบ Status

```bash
docker compose ps
```

ผลลัพธ์ที่ต้องเห็น (รอประมาณ 30-60 วิ):

```
NAME          IMAGE                             STATUS
cloudflared   cloudflare/cloudflared:latest     Up X seconds
mosquitto     eclipse-mosquitto:2               Up X seconds (healthy)
n8n           n8nio/n8n:latest                  Up X seconds (healthy)
nodered       nodered/node-red:latest           Up X seconds (healthy)
```

### ตรวจสอบ Cloudflare Tunnel เชื่อมแล้ว

```bash
docker logs cloudflared --tail=10
```

ต้องเห็น:
```
INF Registered tunnel connection connIndex=0 ... location=sin15
INF Registered tunnel connection connIndex=1 ... location=sin15
```

---

## 8. ตั้งค่า Public Hostname ใน Cloudflare

> ถ้าทำไว้แล้วตั้งแต่ใช้งานบนเครื่องบ้าน ไม่ต้องทำซ้ำ — tunnel เดิมรองรับทุก IP ที่ใช้ token เดิม

เปิด [one.dash.cloudflare.com](https://one.dash.cloudflare.com) → **Networks → Tunnels** → คลิก tunnel → **Edit** → แท็บ **Public Hostname**

ตรวจสอบว่ามี hostname ครบ:

| Subdomain | Domain | Service | URL |
|-----------|--------|---------|-----|
| `n8n` | `thaitechsync.com` | HTTP | `n8n:5678` |
| `nodered` | `thaitechsync.com` | HTTP | `nodered:1880` |

ถ้ายังไม่มี → **Add a public hostname** แล้วกรอกตามตารางด้านบน

---

## 9. ตั้งค่า Node-RED และ N8N

### 9.1 Node-RED

เปิด `https://nodered.thaitechsync.com` → Login:

| Field | ค่า |
|-------|-----|
| Username | `admin` |
| Password | `admin1234` |

Import flow:
1. เมนู **☰** → **Import**
2. เลือกไฟล์ `flows/smartfarm-nodered-full.json`
3. **Deploy**

### 9.2 N8N

เปิด `https://n8n.thaitechsync.com` → สร้างบัญชี Admin (ครั้งแรก)

Import workflow:
1. **+** → **⋮** → **Import from file**
2. เลือกไฟล์ `flows/n8n-smartfarm-autocontrol.json`
3. Toggle **Inactive → Active**

---

## 10. ทดสอบระบบ

### 10.1 ตรวจสอบ Services

```bash
docker compose ps
```

### 10.2 ทดสอบ N8N Webhook

```bash
curl -X POST https://n8n.thaitechsync.com/webhook/smartfarm-telemetry \
  -H "Content-Type: application/json" \
  -d '{"board_id":"ESP32-FARM-001","timestamp":1000,"rssi":-55,"sensors":{"water_temp":26.0,"air_temp":30.0,"air_humidity":70.0,"water_overflow":false,"water_dry":false},"relays":{"relay1_pump":false,"relay2_fan":false,"relay3_heater":false}}'
```

ผลลัพธ์ที่ถูกต้อง: HTTP 200

### 10.3 ตรวจสอบ MQTT

```bash
# ทดสอบส่ง MQTT ผ่าน mosquitto container
docker exec mosquitto mosquitto_pub \
  -h localhost -p 1883 \
  -t "smartfarm/ESP32-FARM-001/telemetry" \
  -m '{"test":"ok"}'
```

### 10.4 Checklist

| # | ทดสอบ | ผล |
|---|-------|----|
| 1 | `docker compose ps` — ทุก container `Up` | |
| 2 | `docker logs cloudflared` — เห็น `Registered tunnel connection` | |
| 3 | เปิด `https://n8n.thaitechsync.com` — เห็นหน้า N8N | |
| 4 | เปิด `https://nodered.thaitechsync.com` — เห็นหน้า Login | |
| 5 | curl webhook — ได้ HTTP 200 | |

---

## 11. คำสั่งที่ใช้บ่อยบน VPS

```bash
# ── เข้าโฟลเดอร์โปรเจกต์ ────────────────────────────────
cd /opt/smartfarm

# ── Start / Stop ────────────────────────────────────────
docker compose up -d                          # Start ทั้งหมด
docker compose down                           # Stop ทั้งหมด
docker compose restart                        # Restart ทั้งหมด

# ── Status & Logs ───────────────────────────────────────
docker compose ps                             # ดู status
docker compose logs -f                        # ดู logs ทุก service (real-time)
docker compose logs -f cloudflared            # ดู logs cloudflared
docker compose logs -f n8n                    # ดู logs n8n
docker compose logs -f nodered               # ดู logs node-red

# ── Restart service เดียว ───────────────────────────────
docker compose up -d --force-recreate n8n
docker compose up -d --force-recreate cloudflared
docker restart nodered

# ── อัปเดต images ───────────────────────────────────────
docker compose pull && docker compose up -d

# ── ดู resource usage ───────────────────────────────────
docker stats

# ── ตรวจสอบ disk ────────────────────────────────────────
df -h

# ── ดู IP สาธารณะ VPS ──────────────────────────────────
curl ifconfig.me
```

### ตั้งให้ Stack start อัตโนมัติหลัง VPS reboot

`restart: unless-stopped` ใน `docker-compose.yml` จัดการให้แล้ว — containers จะ start อัตโนมัติทุกครั้งที่ Docker daemon start

ตรวจสอบว่า Docker daemon start อัตโนมัติ:
```bash
systemctl is-enabled docker
# ควรได้: enabled
```

---

## 12. Troubleshooting

| ปัญหา | สาเหตุ | วิธีแก้ |
|-------|--------|---------|
| PuTTY "Connection refused" | VPS ยังไม่พร้อม / port 22 ปิด | รอ 2-3 นาทีหลัง boot, ตรวจสอบ IP ถูกไหม |
| `docker: command not found` | ยังไม่ได้ติดตั้ง Docker | ทำซ้ำขั้นตอนที่ 4 |
| `Permission denied` ตอนรัน docker | user ยังไม่อยู่ใน group docker | `usermod -aG docker $USER` แล้ว logout/login ใหม่ |
| `cloudflared` Restarting | Token ไม่ถูกต้อง | Zero Trust → Configure → Docker → คัดลอก token ใหม่ |
| N8N Webhook 404 | Workflow ยัง Inactive | N8N → Workflow → เปิด Active toggle |
| `Mismatching encryption keys` | N8N_ENCRYPTION_KEY ไม่ตรง volume | อ่าน key จริง: `docker run --rm -v smartfarm_n8n_data:/d --entrypoint="" alpine sh -c "cat /d/config"` |
| `mosquitto unhealthy` | mosquitto.conf ผิด | `docker logs mosquitto` ตรวจสอบ error |
| ไม่สามารถเปิด URL สาธารณะ | DNS ยังไม่ propagate | รอ 1-5 นาที, ลอง `nslookup n8n.thaitechsync.com` |
| Disk เต็ม | Docker images/logs สะสม | `docker system prune -f` ลบ images ที่ไม่ใช้ |

---

## ข้อแตกต่างสำคัญ — VPS vs เครื่องบ้าน

| | เครื่องบ้าน (Windows) | VPS (Linux) |
|--|----------------------|-------------|
| Docker | Docker Desktop | Docker Engine |
| คำสั่ง compose | `docker compose` | `docker compose` (เหมือนกัน) |
| path โปรเจกต์ | `d:\NodeRed` | `/opt/smartfarm` |
| เปิดตลอด 24/7 | ต้องเปิดคอมตลอด | ทำงานอัตโนมัติ |
| IP สาธารณะ | เปลี่ยนตามISP (dynamic) | คงที่ (static) |
| Cloudflare Tunnel | จำเป็น (IP เปลี่ยน) | ยังใช้ได้ แต่สามารถ port-forward ตรงได้ถ้าต้องการ |
| Firewall | Windows Firewall | UFW |
