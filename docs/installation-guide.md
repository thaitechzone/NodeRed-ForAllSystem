# คู่มือติดตั้ง — Node-RED + N8N + MQTT + ngrok + Ollama

**สำหรับ**: ThinkPad P52 · NVIDIA Quadro P1000 (4GB) · Windows 11

---

## ขั้นที่ 1 — ตรวจสอบ NVIDIA Driver (Windows)

เปิด PowerShell แล้วรัน:

```powershell
nvidia-smi
```

- ถ้าเห็น driver version และ Quadro P1000 → ข้ามไปขั้นที่ 2
- ถ้าไม่มี → ดาวน์โหลด driver สำหรับ **Quadro P1000** จาก NVIDIA และติดตั้ง

---

## ขั้นที่ 2 — เปิด WSL2 + Ubuntu

เปิด PowerShell as **Administrator**:

```powershell
wsl --install -d Ubuntu-22.04
wsl --set-default-version 2
```

รีสตาร์ทเครื่อง แล้วเปิด Ubuntu เพื่อตั้ง username/password

---

## ขั้นที่ 3 — ติดตั้ง Docker Desktop

1. ดาวน์โหลด **Docker Desktop for Windows** และติดตั้ง
2. เปิด Settings → **General** → เปิด `Use WSL 2 based engine`
3. เปิด Settings → **Resources → WSL Integration** → เปิด `Ubuntu-22.04`
4. กด **Apply & Restart**

---

## ขั้นที่ 4 — ติดตั้ง NVIDIA Container Toolkit ใน WSL2

> คำสั่งทั้งหมดในขั้นนี้รันใน **Ubuntu terminal**

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
```

รีสตาร์ท Docker Desktop แล้วทดสอบ:

```bash
docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi
```

ผลลัพธ์ที่ถูกต้อง: เห็น **Quadro P1000** ปรากฏใน output

---

## ขั้นที่ 5 — เตรียม Project

```bash
cd /mnt/c/Users/LeP52ExPower/OneDrive/Documents/GitHub/NodeRed-ForAllSystem
```

สร้าง `.env` file:

```bash
nano .env
```

ใส่ค่าตามนี้:

```env
TZ=Asia/Bangkok
NGROK_AUTHTOKEN=your_token_here
NGROK_DOMAIN=your-domain.ngrok-free.app
NGROK_URL=https://your-domain.ngrok-free.app
N8N_ENCRYPTION_KEY=your_32_char_hex_key_here
```

> สร้าง `N8N_ENCRYPTION_KEY` ด้วยคำสั่ง: `openssl rand -hex 16`

---

## ขั้นที่ 6 — Start Stack

```bash
docker compose up -d
```

ตรวจสอบ services ทุกตัว:

```bash
docker compose ps
```

ทุก service ต้องแสดงสถานะ `running`

---

## ขั้นที่ 7 — Pull Ollama Model

```bash
# แนะนำสำหรับ VRAM 4GB
docker exec -it ollama ollama pull llama3.2:3b
docker exec -it ollama ollama pull phi3:mini

# ดูรายการ model ที่มี
docker exec -it ollama ollama list

# ตรวจสอบว่าใช้ GPU จริง
docker exec -it ollama ollama ps
```

### Models ที่เหมาะกับ Quadro P1000 (4GB VRAM)

| Model | VRAM | หมายเหตุ |
|-------|------|----------|
| `llama3.2:3b` | ~2.0 GB | แนะนำ — ภาษาไทยได้ดี |
| `phi3:mini` | ~2.3 GB | เร็ว เหมาะงาน reasoning |
| `gemma2:2b` | ~1.6 GB | เบาที่สุด |
| `llama3.2:7b` | ~4.5 GB | เกิน VRAM → รัน CPU แทน |

---

## ขั้นที่ 8 — ทดสอบ Endpoints

| Service | URL |
|---------|-----|
| Node-RED | http://localhost:1880 |
| N8N | http://localhost:5678 |
| Ollama API | http://localhost:11434 |
| ngrok Dashboard | http://localhost:4040 |

ทดสอบ Ollama API:

```bash
curl http://localhost:11434/api/generate \
  -d '{"model":"llama3.2:3b","prompt":"สวัสดี","stream":false}'
```

เรียกจาก Node-RED หรือ N8N ใช้ URL: `http://ollama:11434`

---

## คำสั่งที่ใช้บ่อย

```bash
# เริ่ม / หยุด / restart stack
docker compose up -d
docker compose down
docker compose restart ollama

# ดู logs
docker compose logs -f ollama
docker compose logs -f nodered

# เข้าไปใน Ollama container
docker exec -it ollama bash

# chat โดยตรงใน terminal
docker exec -it ollama ollama run llama3.2:3b
```

---

## การแก้ปัญหาเบื้องต้น

**GPU ไม่ถูกใช้งาน**
```bash
# ตรวจสอบ NVIDIA runtime ใน Docker
docker info | grep -i runtime
# ต้องเห็น: Runtimes: nvidia runc
```

**Ollama ไม่ start**
```bash
docker compose logs ollama
# ถ้า error เรื่อง GPU ให้ comment section deploy ใน docker-compose.yml ออก
```

**Out of memory**
```bash
# ลบ model ที่ไม่ใช้
docker exec -it ollama ollama rm model-name
```
