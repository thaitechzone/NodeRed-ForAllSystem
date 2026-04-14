#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  Node-RED + N8N + MQTT + Ngrok  — Management Script (Linux)
#  Working dir: ~/NodeRed  (หรือโฟลเดอร์ที่ clone มา)
#  ใช้งาน: chmod +x setup.sh && ./setup.sh
# ════════════════════════════════════════════════════════════

set -euo pipefail
cd "$(dirname "$0")"

# ── สี ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
OK="${GREEN}[OK]${RESET}"; WARN="${YELLOW}[WARN]${RESET}"; ERR="${RED}[ERROR]${RESET}"

# ── เมนูหลัก ────────────────────────────────────────────────
show_menu() {
  clear
  echo -e "${BOLD}"
  echo "  ╔══════════════════════════════════════════════════════════╗"
  echo "  ║     Node-RED + N8N + MQTT + Ngrok  —  VPS Stack         ║"
  echo "  ╠══════════════════════════════════════════════════════════╣"
  echo "  ║  [1] Setup & Start  (ครั้งแรก / pull images ใหม่)        ║"
  echo "  ║  [2] Start          (เริ่มต้น services)                  ║"
  echo "  ║  [3] Stop           (หยุด services)                      ║"
  echo "  ║  [4] Restart        (restart ทุก services)               ║"
  echo "  ║  [5] Status         (ดูสถานะ containers)                ║"
  echo "  ║  [6] Logs           (ดู logs แบบ real-time)             ║"
  echo "  ║  [7] Ngrok URL      (ดู public URL ปัจจุบัน)            ║"
  echo "  ║  [8] Reset / Clean  (ลบ volumes ทั้งหมด — ระวัง!)       ║"
  echo "  ║  [9] Exit                                                ║"
  echo "  ╚══════════════════════════════════════════════════════════╝"
  echo -e "${RESET}"
  read -rp "  เลือก [1-9]: " CHOICE
}

# ── ตรวจสอบ prerequisites ────────────────────────────────────
check_prereq() {
  if ! command -v docker &>/dev/null; then
    echo -e "${ERR} Docker ไม่ได้ติดตั้ง — รันคำสั่ง:"
    echo "       curl -fsSL https://get.docker.com | sh"
    exit 1
  fi

  if ! docker compose version &>/dev/null; then
    echo -e "${ERR} Docker Compose plugin ไม่พบ — อัปเดต Docker"
    exit 1
  fi

  if [[ ! -f ".env" ]]; then
    echo -e "${ERR} ไม่พบไฟล์ .env — สร้างก่อน:"
    echo "       cp .env.example .env && nano .env"
    exit 1
  fi

  # ตรวจ default values
  if grep -qi "your-subdomain.ngrok-free" .env 2>/dev/null; then
    echo -e "${WARN} NGROK_DOMAIN ใน .env ยังเป็นค่า default — แก้ไขก่อน"
  fi
  if grep -qi "change-this-to-random" .env 2>/dev/null; then
    echo -e "${WARN} N8N_ENCRYPTION_KEY ยังเป็นค่า default — ไม่ปลอดภัย!"
  fi
}

# ── แสดงสถานะ containers ────────────────────────────────────
show_status() {
  echo -e "${BOLD}  ┌─────────────────────────────────────────────────────────┐"
  echo "  │  Container Status                                        │"
  echo -e "  └─────────────────────────────────────────────────────────┘${RESET}"
  docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
}

# ── แสดง URLs ───────────────────────────────────────────────
show_urls() {
  # หา ngrok public URL จาก API
  NGROK_PUBLIC=""
  if curl -s http://localhost:4040/api/tunnels &>/dev/null; then
    NGROK_PUBLIC=$(curl -s http://localhost:4040/api/tunnels \
      | grep -o '"public_url":"https:[^"]*"' \
      | head -1 \
      | cut -d'"' -f4 2>/dev/null || true)
  fi

  echo ""
  echo -e "${BOLD}  ╔══════════════════════════════════════════════════════════╗"
  echo "  ║  Node-RED   →  http://$(hostname -I | awk '{print $1}'):1880"
  echo "  ║  N8N        →  http://$(hostname -I | awk '{print $1}'):5678"
  if [[ -n "$NGROK_PUBLIC" ]]; then
  echo "  ║  N8N Public →  ${NGROK_PUBLIC}"
  fi
  echo "  ║  Ngrok Dash →  http://$(hostname -I | awk '{print $1}'):4040"
  echo "  ║  MQTT TCP   →  $(hostname -I | awk '{print $1}'):1883"
  echo -e "  ╚══════════════════════════════════════════════════════════╝${RESET}"
}

# ── รอ Node-RED พร้อม ────────────────────────────────────────
wait_nodered() {
  echo -n "  รอ Node-RED พร้อม"
  for i in $(seq 1 12); do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:1880 \
       | grep -qE "^(200|301|302)$"; then
      echo -e " ${OK} พร้อมแล้ว (ลอง ${i} ครั้ง)"
      return 0
    fi
    echo -n "."
    sleep 5
  done
  echo -e " ${WARN} ยังไม่ตอบสนองหลัง 60s — ตรวจด้วย: docker compose logs nodered"
  return 1
}

# ════════════════════════════════════════════════════════════
#  Main loop
# ════════════════════════════════════════════════════════════
while true; do
  show_menu
  case "$CHOICE" in

    1)  # Setup & Start
      clear; echo ""
      check_prereq
      echo -e "  ${CYAN}[1/4] Pull Docker images...${RESET}"
      docker compose pull
      echo -e "  ${CYAN}[2/4] Start services...${RESET}"
      docker compose up -d
      echo -e "  ${CYAN}[3/4] รอ Node-RED...${RESET}"
      wait_nodered || true
      echo -e "  ${CYAN}[4/4] ติดตั้ง node-red-contrib-opcua...${RESET}"
      if docker exec nodered npm install node-red-contrib-opcua --prefix /data 2>/dev/null; then
        echo -e "  ${OK} ติดตั้ง opcua สำเร็จ — restart Node-RED..."
        docker restart nodered >/dev/null
        sleep 5
      else
        echo -e "  ${WARN} ติดตั้ง opcua ล้มเหลว — ลองผ่าน Node-RED UI แทน"
      fi
      echo ""
      show_status
      show_urls
      read -rp "  กด Enter เพื่อกลับเมนู..."
      ;;

    2)  # Start
      clear; echo ""
      check_prereq
      echo "  กำลังเริ่ม services..."
      docker compose up -d
      echo ""
      show_status
      show_urls
      read -rp "  กด Enter เพื่อกลับเมนู..."
      ;;

    3)  # Stop
      clear; echo ""
      echo "  กำลังหยุด services..."
      docker compose stop
      echo -e "  ${OK} หยุดทุก services แล้ว"
      read -rp "  กด Enter เพื่อกลับเมนู..."
      ;;

    4)  # Restart
      clear; echo ""
      echo "  กำลัง restart services..."
      docker compose restart
      echo -e "  ${OK} Restart เสร็จสิ้น"
      sleep 3
      show_status
      read -rp "  กด Enter เพื่อกลับเมนู..."
      ;;

    5)  # Status
      clear; echo ""
      show_status
      echo ""
      read -rp "  กด Enter เพื่อกลับเมนู..."
      ;;

    6)  # Logs
      clear; echo ""
      echo "  เลือก service:"
      echo "  [1] ทั้งหมด  [2] nodered  [3] n8n  [4] mosquitto  [5] ngrok"
      echo ""
      read -rp "  เลือก [1-5]: " LSVC
      case "$LSVC" in
        1) docker compose logs -f ;;
        2) docker compose logs -f nodered ;;
        3) docker compose logs -f n8n ;;
        4) docker compose logs -f mosquitto ;;
        5) docker compose logs -f ngrok ;;
        *) echo "ไม่ถูกต้อง" ;;
      esac
      ;;

    7)  # Ngrok URL
      clear; echo ""
      show_urls
      echo ""
      echo "  หรือดูรายละเอียด tunnel ทั้งหมด:"
      curl -s http://localhost:4040/api/tunnels 2>/dev/null \
        | python3 -m json.tool 2>/dev/null \
        || echo -e "  ${WARN} ngrok API ไม่ตอบสนอง — ตรวจสอบว่า ngrok container รันอยู่"
      echo ""
      read -rp "  กด Enter เพื่อกลับเมนู..."
      ;;

    8)  # Reset
      clear; echo ""
      echo -e "${RED}${BOLD}"
      echo "  ╔══════════════════════════════════════════════════════════╗"
      echo "  ║  [RESET] จะลบ volumes ทั้งหมด — ข้อมูลจะหายถาวร!        ║"
      echo -e "  ╚══════════════════════════════════════════════════════════╝${RESET}"
      echo ""
      read -rp "  พิมพ์ YES เพื่อยืนยัน: " CONFIRM
      if [[ "$CONFIRM" == "YES" ]]; then
        docker compose down -v
        echo -e "  ${OK} ลบ containers และ volumes ทั้งหมดแล้ว"
      else
        echo "  ยกเลิก"
      fi
      sleep 2
      ;;

    9)  # Exit
      echo "  Bye!"
      exit 0
      ;;

    *)
      echo -e "  ${WARN} กรุณาเลือก 1-9"
      sleep 1
      ;;
  esac
done
