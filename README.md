# NodeRed-ForAllSystem — Node-RED + N8N + Cloudflare Tunnel

> **Platform:** Windows 11 Pro | **Working dir:** `d:\NodeRed`

---

## สถาปัตยกรรมระบบ

```
ESP32 Device
    │ MQTT (broker.hivemq.com:1883)
    ▼
┌──────────────────────────────────────────────────┐
│  Docker Stack                                    │
│                                                  │
│  ┌──────────┐  MQTT  ┌───────────┐               │
│  │ Node-RED │◄──────►│ Mosquitto │               │
│  │  :1880   │        │   :1883   │               │
│  └────┬─────┘        └───────────┘               │
│       │ HTTP POST /webhook/smartfarm-*            │
│       ▼                                          │
│  ┌──────────┐        ┌─────────────┐             │
│  │   N8N    │◄───────│ cloudflared │◄── Internet │
│  │  :5678   │        │   tunnel    │             │
│  └──────────┘        └─────────────┘             │
└──────────────────────────────────────────────────┘
         │
         ▼
https://n8n.thaitechsync.com
```

---

## Services

| Service | URL | หมายเหตุ |
|---------|-----|---------|
| Node-RED | http://localhost:1880 | Flow editor |
| N8N (local) | http://localhost:5678 | Workflow automation |
| N8N (public) | https://n8n.thaitechsync.com | ผ่าน Cloudflare Tunnel |
| MQTT (local) | localhost:1883 | จาก Windows host |
| MQTT (Docker) | mosquitto:1883 | จาก container อื่น |

---

## เอกสาร

| ไฟล์ | เนื้อหา |
|------|---------|
| [SETUP.md](SETUP.md) | **คู่มือตั้งค่าบนเครื่องบ้าน (Windows + Docker Desktop)** |
| [VPS_SETUP.md](VPS_SETUP.md) | **คู่มือติดตั้งบน VPS Contabo ผ่าน PuTTY** |
| [INSTALL.md](INSTALL.md) | ติดตั้ง Docker + OAuth2 (Google Services) |
| [N8NAutomation.md](N8NAutomation.md) | N8N Webhook + Auto Relay Control |
| [ESP32MQTTTester.md](ESP32MQTTTester.md) | ทดสอบ MQTT กับ ESP32 |

---

## Quick Start

```bash
# 1. แก้ไข .env ใส่ CLOUDFLARE_TUNNEL_TOKEN และ CF_TUNNEL_URL
# 2. Start
docker compose up -d

# 3. ตรวจสอบ
docker compose ps
docker logs cloudflared --tail=5
```

ดูรายละเอียดทั้งหมดที่ [SETUP.md](SETUP.md)
