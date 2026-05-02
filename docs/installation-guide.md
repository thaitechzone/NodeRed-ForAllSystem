# คู่มือติดตั้ง — Node-RED + N8N + MQTT + ngrok + Ollama

**สภาพแวดล้อมที่รองรับ**: Windows 11 + WSL2 + Docker Desktop + NVIDIA GPU  
**ทดสอบบน**: ThinkPad P52 · NVIDIA Quadro P1000 (4GB VRAM) · Driver 573.22 · CUDA 12.8

---

## สารบัญ

1. [ตรวจสอบ NVIDIA Driver](#ขั้นที่-1--ตรวจสอบ-nvidia-driver)
2. [เปิด WSL2 + Ubuntu](#ขั้นที่-2--เปิด-wsl2--ubuntu)
3. [ติดตั้ง Docker Desktop](#ขั้นที่-3--ติดตั้ง-docker-desktop)
4. [ติดตั้ง NVIDIA Container Toolkit](#ขั้นที่-4--ติดตั้ง-nvidia-container-toolkit-ใน-wsl2)
5. [เตรียม Project](#ขั้นที่-5--เตรียม-project)
6. [Start Stack](#ขั้นที่-6--start-stack)
7. [Pull Ollama Model](#ขั้นที่-7--pull-ollama-model)
8. [ทดสอบ Endpoints](#ขั้นที่-8--ทดสอบ-endpoints)
9. [ตั้งค่า Ollama ใน N8N](#ขั้นที่-9--ตั้งค่า-ollama-ใน-n8n)
10. [คำสั่งที่ใช้บ่อย](#คำสั่งที่ใช้บ่อย)
11. [การแก้ปัญหาเบื้องต้น](#การแก้ปัญหาเบื้องต้น)

---

## ขั้นที่ 1 — ตรวจสอบ NVIDIA Driver

เปิด **PowerShell** แล้วรัน:

```powershell
nvidia-smi
```

- เห็น GPU name และ Driver Version → ข้ามไปขั้นที่ 2
- ไม่เห็น → ดาวน์โหลด driver จาก [nvidia.com/drivers](https://www.nvidia.com/drivers) แล้วติดตั้ง

---

## ขั้นที่ 2 — เปิด WSL2 + Ubuntu

เปิด **PowerShell as Administrator**:

```powershell
wsl --install -d Ubuntu-22.04
wsl --set-default-version 2
```

รีสตาร์ทเครื่อง จากนั้นเปิด **Ubuntu** เพื่อตั้ง username และ password

**วิธีเปิด Ubuntu terminal** (เลือกวิธีใดก็ได้):
- กด Start → พิมพ์ `Ubuntu` → Enter
- เปิด PowerShell แล้วพิมพ์ `wsl`
- เปิด Windows Terminal → กดลูกศรข้าง `+` → เลือก `Ubuntu-22.04`

---

## ขั้นที่ 3 — ติดตั้ง Docker Desktop

1. ดาวน์โหลด **Docker Desktop for Windows** จาก [docker.com](https://www.docker.com/products/docker-desktop/)
2. ติดตั้งและเปิด Docker Desktop
3. Settings → **General** → เปิด `Use the WSL 2 based engine`
4. Settings → **Resources → WSL Integration** → เปิด `Ubuntu-22.04`
5. กด **Apply & Restart**

ตรวจสอบว่า Docker พร้อมใช้งาน (ใน Ubuntu terminal):

```bash
docker --version
docker compose version
```

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

**รีสตาร์ท Docker Desktop** จากนั้นทดสอบ GPU ใน container:

```bash
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```

ผลลัพธ์ที่ถูกต้อง: เห็นชื่อ GPU และ `CUDA Version` ปรากฏใน output

> **หมายเหตุ**: ใช้ tag `12.0.0` (มี patch version) ไม่ใช่ `12.0`

---

## ขั้นที่ 5 — เตรียม Project

Clone หรือ copy โฟลเดอร์ project ลงเครื่อง จากนั้นไปที่โฟลเดอร์นั้นใน Ubuntu terminal:

```bash
cd /mnt/c/<path-to-project>
# ตัวอย่าง: cd /mnt/c/Users/YourName/Documents/NodeRed-ForAllSystem
```

สร้างไฟล์ `.env`:

```bash
nano .env
```

ใส่ค่าตามนี้:

```env
TZ=Asia/Bangkok
NGROK_AUTHTOKEN=your_ngrok_token_here
NGROK_DOMAIN=your-domain.ngrok-free.app
NGROK_URL=https://your-domain.ngrok-free.app
N8N_ENCRYPTION_KEY=your_32_char_hex_key_here
```

สร้าง `N8N_ENCRYPTION_KEY` ด้วยคำสั่ง:

```bash
openssl rand -hex 16
```

**วิธีขอค่า ngrok:**
- สมัครที่ [ngrok.com](https://ngrok.com) → ได้ `NGROK_AUTHTOKEN`
- Dashboard → Cloud Edge → Domains → ได้ `NGROK_DOMAIN`

---

## ขั้นที่ 6 — Start Stack

```bash
docker compose up -d
```

ตรวจสอบว่าทุก service รันอยู่:

```bash
docker compose ps
```

ทุก service ต้องแสดงสถานะ `running` ครบ 5 ตัว:

| Service | Container | Port |
|---------|-----------|------|
| MQTT Broker | `mosquitto` | 1883, 9001 |
| Node-RED | `nodered` | 1880 |
| N8N | `n8n` | 5678 |
| Ollama | `ollama` | 11434 |
| ngrok | `ngrok` | 4040 |

---

## ขั้นที่ 7 — Pull Ollama Model

```bash
# แนะนำสำหรับ VRAM 4GB
docker exec -it ollama ollama pull llama3.2:3b

# ดูรายการ model ที่มี
docker exec -it ollama ollama list

# ตรวจสอบว่าใช้ GPU จริง
docker exec -it ollama ollama ps
```

### Models ที่เหมาะกับ GPU VRAM 4GB

| Model | VRAM | หมายเหตุ |
|-------|------|----------|
| `llama3.2:3b` | ~2.0 GB | **แนะนำ** — ภาษาไทยได้ดี |
| `phi3:mini` | ~2.3 GB | เร็ว เหมาะงาน reasoning |
| `gemma2:2b` | ~1.6 GB | เบาที่สุด |
| `llama3.2:7b` | ~4.5 GB | เกิน VRAM → fallback CPU |

---

## ขั้นที่ 8 — ทดสอบ Endpoints

เปิด browser ตรวจสอบแต่ละ service:

| Service | URL | หมายเหตุ |
|---------|-----|----------|
| Node-RED | http://localhost:1880 | Flow editor |
| N8N | http://localhost:5678 | Workflow automation |
| Ollama API | http://localhost:11434 | LLM API |
| ngrok Dashboard | http://localhost:4040 | Tunnel status |

ทดสอบ Ollama API จาก terminal:

```bash
curl http://localhost:11434/api/generate \
  -d '{"model":"llama3.2:3b","prompt":"สวัสดี","stream":false}'
```

ตรวจสอบ network connectivity ระหว่าง N8N กับ Ollama:

```bash
docker exec -it n8n wget -qO- http://ollama:11434/api/tags
```

ผลลัพธ์ที่ถูกต้อง: JSON แสดงรายการ models ที่ pull ไว้

---

## ขั้นที่ 9 — ตั้งค่า Ollama ใน N8N

N8N เรียก Ollama ผ่าน **OpenAI-compatible endpoint** (`/v1`) ซึ่งเชื่อถือได้กว่า node `lmChatOllama` ที่มีปัญหา credential ในบาง version

### สร้าง Credential

1. N8N → เมนูซ้าย → **Credentials** → **+ Add credential**
2. ค้นหา **`OpenAI`** → เลือก **OpenAI API**
3. ใส่ค่า:

| Field | ค่า |
|-------|-----|
| API Key | `ollama` |
| Base URL | `http://ollama:11434/v1` |

4. ตั้งชื่อ `Ollama via OpenAI` → **Save**

> `API Key` ใส่ค่าใดก็ได้ — Ollama ไม่ตรวจสอบ

### Import Workflow ทดสอบ

1. N8N → **+** (New Workflow) → **⋯** → **Import from file**
2. เลือกไฟล์ `flows/n8n-workflow5-ollama-agent.json`
3. คลิก node **OpenAI Chat Model** → ช่อง Credential → เลือก `Ollama via OpenAI`
4. กด **Test workflow**

โครงสร้าง workflow:

```
Manual Trigger → Set Prompt → AI Agent → Extract Response
                                  ↑
                        OpenAI Chat Model
                        (Ollama via OpenAI · llama3.2:3b)
```

---

## คำสั่งที่ใช้บ่อย

```bash
# เริ่ม / หยุด / restart stack
docker compose up -d
docker compose down
docker compose restart ollama

# ดู logs
docker compose logs -f ollama
docker compose logs -f n8n
docker compose logs -f nodered

# จัดการ Ollama models
docker exec -it ollama ollama list
docker exec -it ollama ollama pull llama3.2:3b
docker exec -it ollama ollama rm model-name

# chat โดยตรงใน terminal
docker exec -it ollama ollama run llama3.2:3b

# เข้าไปใน container
docker exec -it ollama bash
docker exec -it n8n sh
```

---

## การแก้ปัญหาเบื้องต้น

### GPU ไม่ถูกใช้งาน

```bash
# ตรวจสอบว่า Docker รู้จัก nvidia runtime
docker info | grep -i runtime
# ต้องเห็น: Runtimes: nvidia runc
```

ถ้าไม่เห็น → รัน `sudo nvidia-ctk runtime configure --runtime=docker` แล้วรีสตาร์ท Docker Desktop

### Ollama ไม่ start

```bash
docker compose logs ollama
```

ถ้า error เรื่อง GPU → แก้ `docker-compose.yml` โดย comment ส่วน `deploy.resources` ออก จะทำให้รันบน CPU แทน

### N8N ไม่ต่อ Ollama ได้

```bash
# ทดสอบ network จาก N8N container
docker exec -it n8n wget -qO- http://ollama:11434/api/tags
```

ถ้าไม่ผ่าน → ตรวจสอบว่าทั้งสอง container อยู่บน network เดียวกัน (`iot_network`):

```bash
docker network inspect iot_network | grep -A2 '"Name"'
```

### Out of Memory

```bash
# ลบ model ที่ไม่ใช้
docker exec -it ollama ollama rm model-name
```

### N8N AI Agent — fetch failed

ปัญหา: node `lmChatOllama` ใน N8N บาง version ไม่สามารถเชื่อมต่อ Ollama ได้  
วิธีแก้: ใช้ node **OpenAI Chat Model** กับ credential ที่ Base URL = `http://ollama:11434/v1` แทน (ดูขั้นที่ 9)
