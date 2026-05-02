# ทดสอบ Ollama AI Agent ใน N8N

**สภาพแวดล้อม**: ThinkPad P52 · NVIDIA Quadro P1000 (4GB) · Windows 11 + WSL2 + Docker Desktop

---

## สรุปผล

| รายการ | ผล |
|--------|-----|
| Ollama container | ✅ Running |
| GPU (Quadro P1000) | ✅ ใช้งานได้ |
| Model `llama3.2:3b` | ✅ Pull แล้ว |
| N8N → Ollama network | ✅ เข้าถึงได้ |
| N8N AI Agent + Ollama | ✅ ทำงานได้ผ่าน OpenAI-compatible endpoint |

---

## สิ่งที่ค้นพบระหว่างทดสอบ

### node `lmChatOllama` ใช้ไม่ได้

N8N มี node `@n8n/n8n-nodes-langchain.lmChatOllama` สำหรับ Ollama โดยตรง แต่พบปัญหา:

```
fetch failed
The service refused the connection - perhaps it is offline
```

**สาเหตุ**: credential type `ollamaApi` ใน N8N บาง version มีปัญหาเรื่อง URL protocol — node ไม่ส่ง request ออกได้แม้ Ollama จะ online

### วิธีแก้ — ใช้ OpenAI-compatible endpoint แทน

Ollama รองรับ OpenAI API format ที่ `/v1/chat/completions` ทำให้ใช้ node `lmChatOpenAi` ชี้มาที่ Ollama ได้เลย

ยืนยันด้วยคำสั่งจากใน N8N container:

```bash
docker exec -it n8n wget -qO- \
  --post-data='{"model":"llama3.2:3b","messages":[{"role":"user","content":"hello"}],"stream":false}' \
  --header='Content-Type: application/json' \
  http://ollama:11434/v1/chat/completions
```

ผลลัพธ์:
```json
{
  "id": "chatcmpl-297",
  "object": "chat.completion",
  "model": "llama3.2:3b",
  "choices": [{
    "message": {
      "role": "assistant",
      "content": "Hello! It's nice to meet you..."
    },
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 26,
    "completion_tokens": 25,
    "total_tokens": 51
  }
}
```

---

## การตั้งค่าที่ใช้งานได้จริง

### 1. Credential ใน N8N

**ประเภท**: OpenAI API

| Field | ค่า |
|-------|-----|
| API Key | `ollama` |
| Base URL | `http://ollama:11434/v1` |
| ชื่อ | `Ollama via OpenAI` |

> API Key ใส่อะไรก็ได้ — Ollama ไม่ตรวจสอบ

### 2. โครงสร้าง Workflow

```
Manual Trigger → Set Prompt → AI Agent → Extract Response
                                  ↑
                        OpenAI Chat Model
                        (credential: Ollama via OpenAI)
                        (model: llama3.2:3b)
```

### 3. การตั้งค่า Node

#### Set Prompt (Code node)
```javascript
return [{
  json: {
    system_prompt: 'คุณเป็น AI วิศวกรพลังงานอุตสาหกรรม...',
    user_prompt: 'เครื่องจักร MC-01 มีค่า Power Factor = 0.75...'
  }
}];
```

#### AI Agent
| Parameter | ค่า |
|-----------|-----|
| Prompt Type | `Define below` |
| Text | `={{ $json.user_prompt }}` |
| System Message | `={{ $json.system_prompt }}` |

#### OpenAI Chat Model
| Parameter | ค่า |
|-----------|-----|
| Credential | `Ollama via OpenAI` |
| Model | `llama3.2:3b` |

#### Extract Response (Code node)
```javascript
const raw = $input.first().json;
const response = raw.output || raw.text || raw.response || JSON.stringify(raw);
return [{
  json: {
    agent_response: response,
    char_count: response.length
  }
}];
```

---

## ไฟล์ Workflow

บันทึกไว้ที่: `flows/n8n-workflow5-ollama-agent.json`

Import ผ่าน N8N UI: **+ New Workflow → ⋯ → Import from file**

หลัง import: คลิก node **OpenAI Chat Model** → เลือก credential `Ollama via OpenAI`

---

## GPU Info ขณะทดสอบ

```
NVIDIA-SMI 570.151   Driver Version: 573.22   CUDA Version: 12.8

GPU: Quadro P1000
VRAM: 18MiB / 4096MiB used (ก่อน load model)
```

Model `llama3.2:3b` ใช้ VRAM ประมาณ **2.0 GB** — เหมาะกับ Quadro P1000

---

## คำสั่งที่ใช้ตรวจสอบ

```bash
# ดู GPU จาก Docker
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi

# ดู models ที่ pull ไว้
docker exec -it ollama ollama list

# ทดสอบ Ollama API จาก N8N container
docker exec -it n8n wget -qO- http://ollama:11434/api/tags

# ทดสอบ OpenAI-compatible endpoint
docker exec -it n8n wget -qO- \
  --post-data='{"model":"llama3.2:3b","messages":[{"role":"user","content":"hello"}],"stream":false}' \
  --header='Content-Type: application/json' \
  http://ollama:11434/v1/chat/completions
```
