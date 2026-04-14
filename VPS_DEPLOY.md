# คู่มือ Deploy ไป VPS — Desktop สู่ VPS (Ngrok ยังคงเดิม)

> **เป้าหมาย**: ย้าย Docker Stack (Node-RED + N8N + MQTT + Ngrok) จาก Windows Desktop ไปรันบน VPS Linux  
> โดยยังคงใช้ **Ngrok domain เดิม** — ไม่ต้องแก้ไข N8N, Google OAuth, หรือ webhook ใดๆ

---

## สิ่งที่ต้องเตรียม

| รายการ | รายละเอียด |
|--------|-----------|
| VPS | Ubuntu 22.04 LTS (แนะนำ), RAM 2GB+, Disk 20GB+ |
| SSH Key หรือ Password | สำหรับ login เข้า VPS |
| ไฟล์ `.env` | จาก Desktop ที่ใช้งานอยู่ |
| Ngrok ที่ทำงานได้บน Desktop | ทดสอบแล้วว่า domain ถูกต้อง |

> **สำคัญ**: Ngrok Free อนุญาต 1 agent ต่อ 1 domain ในเวลาเดียวกัน  
> ต้องหยุด ngrok บน Desktop **ก่อน** start บน VPS

---

## ขั้นตอนที่ 1 — เตรียม VPS

### 1.1 เชื่อมต่อ SSH

```bash
ssh root@YOUR_VPS_IP
# หรือถ้าใช้ user อื่น
ssh ubuntu@YOUR_VPS_IP
```

### 1.2 ติดตั้ง Docker (ครั้งเดียว)

```bash
# ติดตั้ง Docker Engine
curl -fsSL https://get.docker.com | sh

# เพิ่ม user ปัจจุบันเข้า docker group (ไม่ต้องพิมพ์ sudo ทุกครั้ง)
sudo usermod -aG docker $USER

# โหลด group ใหม่โดยไม่ต้อง logout
newgrp docker

# ตรวจสอบ
docker --version
docker compose version
```

ผลลัพธ์ที่ควรเห็น:
```
Docker version 27.x.x
Docker Compose version v2.x.x
```

---

## ขั้นตอนที่ 2 — โอนไฟล์โปรเจกต์

### 2.1 Clone จาก Git (แนะนำ)

```bash
# บน VPS
git clone https://github.com/YOUR_USERNAME/NodeRed.git
cd NodeRed
```

> ไฟล์ `.env` **ไม่อยู่ใน Git** (อยู่ใน `.gitignore`) — ต้องโอนแยกต่างหาก

### 2.2 โอนไฟล์ .env จาก Desktop ไป VPS

เปิด Terminal บน **Desktop (Windows)**:

```bash
# วิธีที่ 1 — scp (ง่ายสุด)
scp d:\NodeRed\.env root@YOUR_VPS_IP:~/NodeRed/.env

# วิธีที่ 2 — copy ผ่าน VS Code Remote SSH
# เปิด VS Code → Remote Explorer → เชื่อม VPS → ลาก .env ไปวาง
```

> ถ้าไม่มี `scp` บน Windows ให้ใช้ [WinSCP](https://winscp.net) หรือ copy ด้วยมือ

### 2.3 ตรวจสอบไฟล์บน VPS

```bash
# บน VPS
ls -la ~/NodeRed/
```

ต้องเห็นไฟล์เหล่านี้ครบ:
```
.env                          ← โอนมาจาก Desktop
.env.example
docker-compose.yml
setup.sh
mosquitto/config/mosquitto.conf
nodered/settings.js
```

---

## ขั้นตอนที่ 3 — หยุด Ngrok บน Desktop ก่อน

> ถ้าไม่หยุด ngrok บน Desktop — ngrok บน VPS จะ error: `tunnel session already active`

**บน Desktop (Windows)** — เลือกวิธีใดวิธีหนึ่ง:

```bash
# วิธีที่ 1 — หยุดเฉพาะ ngrok
cd d:\NodeRed
docker compose stop ngrok

# วิธีที่ 2 — หยุดทั้งหมด
docker compose stop
```

ตรวจสอบว่า ngrok หยุดแล้ว:
```bash
docker compose ps
# ngrok ต้องแสดงสถานะ "exited"
```

---

## ขั้นตอนที่ 4 — Start Stack บน VPS

```bash
# บน VPS
cd ~/NodeRed

# ให้สิทธิ์ script (ครั้งแรกครั้งเดียว)
chmod +x setup.sh

# วิธีที่ 1 — ใช้ script (แนะนำ)
./setup.sh
# → เลือก [1] Setup & Start

# วิธีที่ 2 — ใช้คำสั่งตรง
docker compose pull
docker compose up -d
```

ตรวจสอบสถานะ:
```bash
docker compose ps
```

ผลลัพธ์ที่ควรเห็น:
```
NAME         STATUS
mosquitto    running (healthy)
nodered      running
n8n          running
ngrok        running
```

---

## ขั้นตอนที่ 5 — ตรวจสอบ Ngrok Tunnel

```bash
# ดู log ngrok
docker compose logs ngrok

# ควรเห็นบรรทัดแบบนี้:
# started tunnel  addr=http://n8n:5678  url=https://your-domain.ngrok-free.dev
```

หรือดูผ่าน API:
```bash
curl -s http://localhost:4040/api/tunnels | python3 -m json.tool
```

หรือเปิด browser:
```
http://YOUR_VPS_IP:4040
```

---

## ขั้นตอนที่ 6 — ทดสอบเข้าใช้งาน

| Service | URL | หมายเหตุ |
|---------|-----|---------|
| Node-RED | `http://YOUR_VPS_IP:1880` | ใช้ username/password จาก `.env` |
| N8N (local) | `http://YOUR_VPS_IP:5678` | เดียวกับ Desktop |
| N8N (public) | `https://your-domain.ngrok-free.dev` | **domain เดิม ใช้ได้เลย** |
| Ngrok Dashboard | `http://YOUR_VPS_IP:4040` | ดู tunnel status |

---

## สรุปความแตกต่าง Desktop vs VPS

| | Desktop (Windows) | VPS (Linux) |
|--|--|--|
| Script | `setup.bat` | `setup.sh` |
| เข้าถึง Node-RED | `localhost:1880` | `VPS_IP:1880` |
| เข้าถึง N8N | `localhost:5678` | `VPS_IP:5678` |
| Ngrok domain | **เดิม** | **เดิม (เหมือนกัน)** |
| `.env` | เดิม | **copy มา — ไม่ต้องแก้** |
| `docker-compose.yml` | เดิม | **เดิม — ไม่ต้องแก้** |

---

## คำสั่งที่ใช้บ่อยบน VPS

```bash
# ดูสถานะ
docker compose ps

# ดู logs แบบ real-time
docker compose logs -f

# ดูเฉพาะ ngrok
docker compose logs -f ngrok

# Restart service เดียว
docker compose restart ngrok
docker compose restart n8n

# หยุดทั้งหมด
docker compose stop

# เริ่มใหม่
docker compose start

# อัปเดต images (กรณีมี version ใหม่)
docker compose pull && docker compose up -d
```

---

## Troubleshooting

| ปัญหา | สาเหตุ | วิธีแก้ |
|-------|--------|---------|
| `ngrok: tunnel session already active` | ngrok Desktop ยังรันอยู่ | `docker compose stop ngrok` บน Desktop |
| `ERR_NGROK_108` | agent เกิน quota (free = 1) | หยุด ngrok บน Desktop ก่อน |
| Port 1880 / 5678 เข้าไม่ได้จากนอก | Firewall VPS ปิดอยู่ | `sudo ufw allow 1880` และ `sudo ufw allow 5678` |
| `.env` ไม่พบ | ลืมโอนมา | `scp .env root@VPS_IP:~/NodeRed/` |
| `mosquitto unhealthy` | mosquitto.conf ผิด | `docker compose logs mosquitto` |
| N8N webhook ไม่ทำงาน | ngrok ยังไม่พร้อม | รอ 30 วิ แล้ว `docker compose restart ngrok` |

---

## Firewall VPS (ถ้าใช้ ufw)

```bash
sudo ufw allow 22      # SSH — ต้องเปิดเสมอ
sudo ufw allow 1880    # Node-RED
sudo ufw allow 5678    # N8N
sudo ufw allow 4040    # Ngrok Dashboard (optional — เปิดเฉพาะถ้าต้องการ)
sudo ufw allow 1883    # MQTT (เปิดเฉพาะถ้า ESP32 / client ภายนอกต้องการ)
sudo ufw enable

# ตรวจสอบ
sudo ufw status
```

---

## ขั้นตอนถัดไป (Advanced)

เมื่อพร้อมจะ upgrade จาก ngrok → domain จริง:

- ดู branch `02_cloudflare_Connect` — ใช้ Cloudflare Tunnel แทน ngrok
- ต้องการ domain (`.com`, `.dev`, ฯลฯ) และชี้ DNS ไปที่ VPS
- Traefik จะออก SSL (Let's Encrypt) อัตโนมัติ
