# Setup Credentials - Command Line Guide

> คู่มือการสร้าง Password Hash และ Tokens แบบ Command Line

---

## 📋 Table of Contents

1. [Node-RED Password Hash](#node-red-password-hash)
2. [N8N Encryption Key](#n8n-encryption-key)
3. [InfluxDB Admin Token](#influxdb-admin-token)
4. [สรุป & Next Steps](#สรุป--next-steps)

---

## 🔐 Node-RED Password Hash

### ต้องทำ: สร้าง bcrypt password hash

### Step 1: ติดตั้ง node-red-admin

**Windows PowerShell:**
```powershell
npm install -g node-red-admin
```

**Mac/Linux Terminal:**
```bash
npm install -g node-red-admin
```

### Step 2: สร้าง Password Hash

**Windows PowerShell:**
```powershell
node-red-admin hash-pw
```

**Mac/Linux Terminal:**
```bash
node-red-admin hash-pw
```

### Step 3: ใส่รหัสผ่าน

```
Password: (พิมพ์รหัสผ่านที่ต้องการ - ตัวอักษรไม่แสดง)
Confirm password: (พิมพ์รหัสผ่านอีกครั้ง)
```

### Step 4: Copy Hash ที่ได้

**Output:**
```
$2a$08$KLaz9xM2VLaIza/example/hash/output/here
```

**ใส่ลงใน .env:**
```env
NODERED_PASSWORD_HASH=$2a$08$KLaz9xM2VLaIza/example/hash/output/here
```

### ⚠️ ตรวจสอบ Hash

```
✓ ต้องเริ่มด้วย: $2a$ หรือ $2b$
✓ ต้องยาว: 60 ตัวอักษร
✓ ไม่มี: space หรือ newline
```

---

## 🔑 N8N Encryption Key

### ต้องทำ: สร้าง 32-character hex string

### Windows PowerShell

**วิธีที่ 1: ใช้ PowerShell command (เร็วสุด)**

```powershell
[System.Guid]::NewGuid().ToString().Replace("-","").Substring(0,32)
```

**Step-by-step:**
```powershell
# 1. เปิด PowerShell
Windows Key → พิมพ์ "PowerShell" → Enter

# 2. Copy command ด้านบน แล้ว Paste ใน PowerShell
[System.Guid]::NewGuid().ToString().Replace("-","").Substring(0,32)

# 3. Press Enter

# Output ควรจะเป็น:
# 8f3a2b1c9d7e5f4a6b2c1d9e8f7a3b2c
```

**ใส่ลงใน .env:**
```env
N8N_ENCRYPTION_KEY=8f3a2b1c9d7e5f4a6b2c1d9e8f7a3b2c
```

### Mac/Linux Terminal

**วิธีที่ 1: ใช้ openssl (เร็วสุด)**

```bash
openssl rand -hex 16
```

**Step-by-step:**
```bash
# 1. เปิด Terminal
Cmd+Space → พิมพ์ "Terminal" → Enter

# 2. Copy command ด้านบน แล้ว Paste ใน Terminal
openssl rand -hex 16

# 3. Press Enter

# Output ควรจะเป็น:
# 8f3a2b1c9d7e5f4a6b2c1d9e8f7a3b2c
```

**ใส่ลงใน .env:**
```env
N8N_ENCRYPTION_KEY=8f3a2b1c9d7e5f4a6b2c1d9e8f7a3b2c
```

### ⚠️ ตรวจสอบ Key

```
✓ ต้องยาว: 32 ตัวอักษร
✓ ต้องเป็น: hex (0-9, a-f)
✓ ไม่มี: dash (-) หรือเครื่องหมายพิเศษ
```

---

## 🎫 InfluxDB Admin Token

### ต้องทำ: สร้าง 64-character hex string

### Windows PowerShell

**วิธีที่ 1: ใช้ PowerShell command**

```powershell
[System.Guid]::NewGuid().ToString().Replace("-","") + [System.Guid]::NewGuid().ToString().Replace("-","")
```

**Step-by-step:**
```powershell
# 1. เปิด PowerShell

# 2. Copy & Paste:
[System.Guid]::NewGuid().ToString().Replace("-","") + [System.Guid]::NewGuid().ToString().Replace("-","")

# 3. Press Enter

# Output ควรจะเป็น:
# 8f3a2b1c9d7e5f4a6b2c1d9e8f7a3b2c8f3a2b1c9d7e5f4a6b2c1d9e8f7a3b2c
```

**ใส่ลงใน .env:**
```env
INFLUXDB_ADMIN_TOKEN=8f3a2b1c9d7e5f4a6b2c1d9e8f7a3b2c8f3a2b1c9d7e5f4a6b2c1d9e8f7a3b2c
```

### Mac/Linux Terminal

**วิธีที่ 1: ใช้ openssl**

```bash
openssl rand -hex 32
```

**Step-by-step:**
```bash
# 1. เปิด Terminal

# 2. Copy & Paste:
openssl rand -hex 32

# 3. Press Enter

# Output ควรจะเป็น:
# 8f3a2b1c9d7e5f4a6b2c1d9e8f7a3b2c8f3a2b1c9d7e5f4a6b2c1d9e8f7a3b2c
```

**ใส่ลงใน .env:**
```env
INFLUXDB_ADMIN_TOKEN=8f3a2b1c9d7e5f4a6b2c1d9e8f7a3b2c8f3a2b1c9d7e5f4a6b2c1d9e8f7a3b2c
```

### ⚠️ ตรวจสอบ Token

```
✓ ต้องยาว: 64 ตัวอักษร
✓ ต้องเป็น: hex (0-9, a-f)
✓ ไม่มี: dash (-) หรือเครื่องหมายพิเศษ
```

---

## 📋 สรุป & Next Steps

### สิ่งที่สร้างแล้ว

```
1. NODERED_PASSWORD_HASH ✓
   (จาก node-red-admin hash-pw)

2. N8N_ENCRYPTION_KEY ✓
   (32-char hex from PowerShell/openssl)

3. INFLUXDB_ADMIN_TOKEN ✓
   (64-char hex from PowerShell/openssl)
```

### ตอนนี้ .env ควรมี

```env
# ── Node-RED Login ────────────────────────────────────────
NODERED_USERNAME=admin
NODERED_PASSWORD_HASH=$2a$08$KLaz9xM2VLaIza/example/hash/output/here

# ── Cloudflare Tunnel (Optional) ──────────────────────────
CLOUDFLARE_TUNNEL_TOKEN=your-cloudflare-tunnel-token-here
N8N_DOMAIN=n8n.yourdomain.com

# ── N8N (SQLite Database) ────────────────────────────
N8N_ENCRYPTION_KEY=8f3a2b1c9d7e5f4a6b2c1d9e8f7a3b2c

# ── InfluxDB ──────────────────────────────────────────────
INFLUXDB_USERNAME=admin
INFLUXDB_PASSWORD=change-this-strong-password
INFLUXDB_ORG=iot_org
INFLUXDB_BUCKET=iot_bucket
INFLUXDB_ADMIN_TOKEN=8f3a2b1c9d7e5f4a6b2c1d9e8f7a3b2c8f3a2b1c9d7e5f4a6b2c1d9e8f7a3b2c

# ── Grafana ───────────────────────────────────────────────
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=change-this-strong-password

# ── Timezone ──────────────────────────────────────────────
TZ=Asia/Bangkok
```

### Step ถัดไป

1. ✅ สร้าง credentials (ทำเสร็จแล้ว)
2. ✅ แก้ไข .env ด้วยค่าที่สร้าง
3. 🚀 Start Docker Desktop:
   ```bash
   docker compose up -d
   ```
4. 🌐 ทดสอบ services:
   - http://localhost:1880 (Node-RED)
   - http://localhost:5678 (N8N)
   - http://localhost:8086 (InfluxDB)
   - http://localhost:3000 (Grafana)

---

## ❓ Troubleshooting

### ❌ "npm: command not found"

**แก้ไข:**
- ติดตั้ง Node.js จาก https://nodejs.org/
- Restart Terminal
- ลอง command อีกครั้ง

### ❌ "openssl: command not found" (Windows)

**แก้ไข:**
- ใช้ PowerShell command แทน:
  ```powershell
  openssl rand -hex 32
  ```
- หรือติดตั้ง Git Bash

### ❌ Hash/Token เสียหาย

**แก้ไข:**
- รันคำสั่งอีกครั้ง
- Copy-paste output ใหม่

---

## 📖 Reference

- [node-red-admin GitHub](https://github.com/node-red/node-red-admin)
- [OpenSSL Documentation](https://www.openssl.org/)
- [Node.js Official](https://nodejs.org/)
