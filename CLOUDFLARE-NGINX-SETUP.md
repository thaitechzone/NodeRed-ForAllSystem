# ตั้งค่า Cloudflare Tunnel + Nginx Proxy Manager

สร้าง Subdomain สำหรับแต่ละ Container

---

## ภาพรวม

```
Internet
  │  HTTPS (Cloudflare จัดการ SSL อัตโนมัติ)
  ▼
Cloudflare DNS
  │
  ▼
Cloudflare Tunnel (cloudflared container)
  │
  ▼
Nginx Proxy Manager :80  ← routing ตาม domain name
  │
  ├── n8n.yourdomain.com      →  n8n:5678
  ├── nodered.yourdomain.com  →  nodered:1880
  ├── grafana.yourdomain.com  →  grafana:3000
  └── ha.yourdomain.com       →  homeassistant:8123
```

> Cloudflare Tunnel เชื่อมระหว่าง Cloudflare Network กับ Nginx Proxy Manager ภายใน Docker  
> **ไม่ต้องเปิด Port 80/443 ที่ Router** — Tunnel ทำงานแบบ outbound เท่านั้น

---

## ส่วนที่ 1 — Cloudflare Tunnel: เพิ่ม Public Hostnames

1. ไปที่ https://one.dash.cloudflare.com
2. **Networks → Tunnels** → คลิก tunnel ที่สร้างไว้ → **Edit**
3. แท็บ **Public Hostname → Add a public hostname**

เพิ่มทีละ hostname ตามตารางนี้ (ทุกตัวชี้ไปที่ `nginx-proxy-manager:80`):

| Subdomain | Domain | Type | URL |
|-----------|--------|------|-----|
| `n8n` | yourdomain.com | HTTP | `nginx-proxy-manager:80` |
| `nodered` | yourdomain.com | HTTP | `nginx-proxy-manager:80` |
| `grafana` | yourdomain.com | HTTP | `nginx-proxy-manager:80` |
| `ha` | yourdomain.com | HTTP | `nginx-proxy-manager:80` |

กด **Save** หลังเพิ่มแต่ละ hostname

> Cloudflare จัดการ DNS Record และ SSL Certificate ให้อัตโนมัติ  
> ไม่ต้องสร้าง DNS Record แยกในหน้า Cloudflare DNS

---

## ส่วนที่ 2 — Nginx Proxy Manager: ตั้งค่า Proxy Host

เปิด http://localhost:81

**Login ครั้งแรก:**
- Email: `admin@example.com`
- Password: `changeme`
- เปลี่ยน email และ password ทันทีหลัง login

---

### วิธีเพิ่ม Proxy Host (ทำซ้ำสำหรับแต่ละ service)

**Hosts → Proxy Hosts → Add Proxy Host**

---

### N8N

| Field | ค่า |
|-------|-----|
| Domain Names | `n8n.yourdomain.com` |
| Scheme | `http` |
| Forward Hostname / IP | `n8n` |
| Forward Port | `5678` |
| Cache Assets | ปิด |
| Block Common Exploits | ✅ เปิด |
| Websockets Support | ✅ เปิด |

---

### Node-RED

| Field | ค่า |
|-------|-----|
| Domain Names | `nodered.yourdomain.com` |
| Scheme | `http` |
| Forward Hostname / IP | `nodered` |
| Forward Port | `1880` |
| Block Common Exploits | ✅ เปิด |
| Websockets Support | ✅ เปิด (Dashboard ต้องใช้ WebSocket) |

---

### Grafana

| Field | ค่า |
|-------|-----|
| Domain Names | `grafana.yourdomain.com` |
| Scheme | `http` |
| Forward Hostname / IP | `grafana` |
| Forward Port | `3000` |
| Block Common Exploits | ✅ เปิด |
| Websockets Support | ✅ เปิด |

---

### Home Assistant

| Field | ค่า |
|-------|-----|
| Domain Names | `ha.yourdomain.com` |
| Scheme | `http` |
| Forward Hostname / IP | `homeassistant` |
| Forward Port | `8123` |
| Block Common Exploits | ✅ เปิด |
| Websockets Support | ✅ เปิด (จำเป็น — HA ใช้ WebSocket หนัก) |

---

## ส่วนที่ 3 — ตั้งค่าเพิ่มเติมสำหรับ Home Assistant

Home Assistant ต้องรู้ว่าอยู่เบื้องหลัง Reverse Proxy ไม่เช่นนั้นจะ block การเชื่อมต่อ

เปิดไฟล์ `configuration.yaml` ใน Home Assistant:

**Settings → System → Edit configuration.yaml** หรือใช้คำสั่ง:

```bash
docker exec -it homeassistant bash
vi /config/configuration.yaml
```

เพิ่มส่วนนี้:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.16.0.0/12
    - 192.168.0.0/16
```

บันทึกแล้ว restart:

```bash
docker compose restart homeassistant
```

---

## ส่วนที่ 4 — อัปเดท .env

เปิด `.env` แล้วอัปเดท `N8N_DOMAIN` ให้ตรงกับ subdomain ที่ตั้งไว้:

```env
N8N_DOMAIN=n8n.yourdomain.com
```

Recreate N8N เพื่อให้ใช้ค่าใหม่:

```bash
docker compose up -d --force-recreate n8n
```

---

## ส่วนที่ 5 — ทดสอบ

### ตรวจสอบ Tunnel

```bash
docker compose logs -f cloudflared
```

ผลลัพธ์ที่ถูกต้อง:
```
INF Connection ... registered connIndex=0
INF Connection ... registered connIndex=1
```

### ทดสอบเปิดจาก Browser

| URL | Service |
|-----|---------|
| https://n8n.yourdomain.com | N8N Workflow |
| https://nodered.yourdomain.com | Node-RED |
| https://grafana.yourdomain.com | Grafana |
| https://ha.yourdomain.com | Home Assistant |

### ทดสอบ N8N Webhook

```bash
curl -X POST https://n8n.yourdomain.com/webhook-test/test \
  -H "Content-Type: application/json" \
  -d '{"test": true}'
```

---

## Troubleshooting

| ปัญหา | วิธีแก้ |
|-------|---------|
| เปิด subdomain แล้วขึ้น 502 Bad Gateway | ตรวจชื่อ container ใน Forward Hostname — ต้องตรงกับชื่อใน docker-compose.yml |
| cloudflared log มี "failed to connect" | ตรวจว่า nginx-proxy-manager container healthy: `docker compose ps` |
| Home Assistant redirect loop / 400 error | ต้องเพิ่ม `trusted_proxies` ใน configuration.yaml (ส่วนที่ 3) |
| SSL Certificate ไม่ออก | Cloudflare จัดการ SSL เอง ไม่ต้องตั้งค่าใน Nginx Proxy Manager |
| N8N Webhook URL ผิด | ตรวจ `N8N_DOMAIN` ใน `.env` แล้ว `docker compose up -d --force-recreate n8n` |
| Node-RED Dashboard โหลดไม่ขึ้น | ตรวจว่าเปิด Websockets Support ใน Nginx Proxy Manager |
