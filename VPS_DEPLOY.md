# คู่มือ Deploy ไป VPS

> **เป้าหมาย**: ย้าย Docker Stack (Node-RED + N8N + MQTT + ngrok)
> จาก Windows Desktop ไปรันบน VPS Linux
> โดยยังคงใช้ **ngrok domain เดิม** — ไม่ต้องแก้ไข N8N, Google OAuth, หรือ webhook ใดๆ

---

## สิ่งที่ต้องเตรียม

| รายการ | รายละเอียด |
|--------|-----------|
| VPS | Ubuntu 22.04 LTS (แนะนำ), RAM 1GB+, Disk 10GB+ |
| SSH Key หรือ Password | สำหรับ login เข้า VPS |
| ไฟล์ `.env` | จาก Desktop ที่ใช้งานอยู่ |
| ngrok ที่ทำงานได้บน Desktop | ทดสอบแล้วว่า domain ถูกต้อง |

> **สำคัญ**: ngrok Free อนุญาต 1 agent ต่อ 1 domain ในเวลาเดียวกัน
> ต้องหยุด ngrok บน Desktop **ก่อน** start บน VPS

---

## ขั้นตอนที่ 1 — เตรียม VPS

### 1.1 เชื่อมต่อ SSH

```bash
ssh root@YOUR_VPS_IP
```

### 1.2 ติดตั้ง Docker (ครั้งเดียว)

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# ตรวจสอบ
docker --version
docker compose version
```

---

## ขั้นตอนที่ 2 — โอนไฟล์โปรเจกต์

### 2.1 Clone จาก Git (แนะนำ)

```bash
git clone https://github.com/YOUR_USERNAME/NodeRed.git
cd NodeRed
```

> ไฟล์ `.env` **ไม่อยู่ใน Git** — ต้องโอนแยกต่างหาก

### 2.2 โอนไฟล์ .env จาก Desktop ไป VPS

เปิด Terminal บน **Desktop (Windows)**:

```bash
scp d:\NodeRed\.env root@YOUR_VPS_IP:~/NodeRed/.env
```

> ถ้าไม่มี `scp` บน Windows ให้ใช้ [WinSCP](https://winscp.net)

### 2.3 ตรวจสอบไฟล์บน VPS

```bash
ls -la ~/NodeRed/
```

ต้องเห็นไฟล์เหล่านี้ครบ:
```
.env
docker-compose.yml
mosquitto/config/mosquitto.conf
nodered/settings.js
```

---

## ขั้นตอนที่ 3 — หยุด ngrok บน Desktop ก่อน

> ถ้าไม่หยุด — ngrok บน VPS จะ error: `tunnel session already active`

**บน Desktop (Windows)**:

```bash
cd d:\NodeRed
docker compose stop ngrok
```

---

## ขั้นตอนที่ 4 — Start Stack บน VPS

```bash
cd ~/NodeRed
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

## ขั้นตอนที่ 5 — ตรวจสอบ ngrok Tunnel

```bash
docker compose logs ngrok
# ควรเห็น: started tunnel  addr=http://n8n:5678  url=https://your-domain.ngrok-free.dev
```

---

## ขั้นตอนที่ 6 — ทดสอบเข้าใช้งาน

| Service | URL |
|---------|-----|
| Node-RED | `http://YOUR_VPS_IP:1880` |
| N8N (local) | `http://YOUR_VPS_IP:5678` |
| N8N (public) | `https://your-domain.ngrok-free.dev` — **domain เดิม ใช้ได้เลย** |
| ngrok Dashboard | `http://YOUR_VPS_IP:4040` |

---

## สรุปความแตกต่าง Desktop vs VPS

| | Desktop (Windows) | VPS (Linux) |
|--|--|--|
| Script | `setup.bat` | ไม่มี — ใช้ `docker compose` ตรงๆ |
| Node-RED | `localhost:1880` | `VPS_IP:1880` |
| N8N | `localhost:5678` | `VPS_IP:5678` |
| ngrok domain | **เดิม** | **เดิม (เหมือนกัน)** |
| `.env` | เดิม | **copy มา — ไม่ต้องแก้** |

---

## คำสั่งที่ใช้บ่อยบน VPS

```bash
# ดูสถานะ
docker compose ps

# ดู logs
docker compose logs -f
docker compose logs -f ngrok
docker compose logs -f n8n
docker compose logs -f nodered

# Restart service เดียว
docker compose restart n8n
docker compose restart ngrok

# หยุดทั้งหมด
docker compose stop

# อัปเดต images
docker compose pull && docker compose up -d
```

---

## Firewall VPS (ถ้าใช้ ufw)

```bash
sudo ufw allow 22      # SSH — ต้องเปิดเสมอ
sudo ufw allow 1880    # Node-RED
sudo ufw allow 5678    # N8N
sudo ufw allow 4040    # ngrok Dashboard (optional)
sudo ufw allow 1883    # MQTT (เปิดเฉพาะถ้า ESP32 ภายนอกต้องการ)
sudo ufw enable
sudo ufw status
```

---

## Troubleshooting

| ปัญหา | สาเหตุ | วิธีแก้ |
|-------|--------|---------|
| `ngrok: tunnel session already active` | ngrok Desktop ยังรันอยู่ | `docker compose stop ngrok` บน Desktop |
| `ERR_NGROK_108` | agent เกิน quota (free = 1) | หยุด ngrok บน Desktop ก่อน |
| Port เข้าไม่ได้จากนอก | Firewall VPS ปิดอยู่ | `sudo ufw allow PORT` |
| `.env` ไม่พบ | ลืมโอนมา | `scp .env root@VPS_IP:~/NodeRed/` |
| `mosquitto unhealthy` | mosquitto.conf ผิด | `docker compose logs mosquitto` |
