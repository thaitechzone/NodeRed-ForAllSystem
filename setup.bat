@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

:: ════════════════════════════════════════════════════════════
::  Node-RED + N8N + MQTT  — Management Script
::  Working dir: d:\NodeRed
:: ════════════════════════════════════════════════════════════

cd /d "%~dp0"

:MENU
cls
echo.
echo  ╔══════════════════════════════════════════════════════════╗
echo  ║        Node-RED + N8N + MQTT  —  Local Stack            ║
echo  ╠══════════════════════════════════════════════════════════╣
echo  ║  [1] Setup ^& Start  (ครั้งแรก / pull images ใหม่)       ║
echo  ║  [2] Start           (เริ่มต้น services)                 ║
echo  ║  [3] Stop            (หยุด services)                     ║
echo  ║  [4] Restart         (restart ทุก services)              ║
echo  ║  [5] Status          (ดูสถานะ containers)               ║
echo  ║  [6] Logs            (ดู logs แบบ real-time)            ║
echo  ║  [7] Open Browser    (เปิด UI ทั้งหมด)                  ║
echo  ║  [8] Reset / Clean   (ลบ volumes ทั้งหมด — ระวัง!)      ║
echo  ║  [9] Exit                                                ║
echo  ╚══════════════════════════════════════════════════════════╝
echo.
set /p CHOICE="  เลือก [1-9]: "

if "%CHOICE%"=="1" goto SETUP
if "%CHOICE%"=="2" goto START
if "%CHOICE%"=="3" goto STOP
if "%CHOICE%"=="4" goto RESTART
if "%CHOICE%"=="5" goto STATUS
if "%CHOICE%"=="6" goto LOGS
if "%CHOICE%"=="7" goto BROWSER
if "%CHOICE%"=="8" goto RESET
if "%CHOICE%"=="9" goto EOF
echo  [WARN] กรุณาเลือก 1-9
timeout /t 1 /nobreak >nul
goto MENU

:: ────────────────────────────────────────────────────────────
:CHECK_PREREQ
:: ────────────────────────────────────────────────────────────
docker --version >nul 2>&1
if errorlevel 1 (
    echo.
    echo  [ERROR] Docker ไม่ได้ติดตั้ง กรุณาติดตั้ง Docker Desktop ก่อน
    echo          https://www.docker.com/products/docker-desktop
    pause & exit /b 1
)

docker compose version >nul 2>&1
if errorlevel 1 (
    echo.
    echo  [ERROR] Docker Compose ไม่พบ กรุณาอัปเดต Docker Desktop
    pause & exit /b 1
)

if not exist ".env" (
    echo.
    echo  [ERROR] ไม่พบไฟล์ .env — สร้างจาก .env.example ก่อน:
    echo          copy .env.example .env
    pause & exit /b 1
)

:: ตรวจ default values ที่ยังไม่ได้แก้
findstr /i "your-subdomain.ngrok-free.app" .env >nul 2>&1
if not errorlevel 1 (
    echo.
    echo  [WARN] NGROK_URL ใน .env ยังเป็นค่า default — N8N webhook อาจใช้ไม่ได้
    echo         แก้ไขไฟล์ .env ก่อนหากต้องการใช้ ngrok
    echo.
)
findstr /i "change-this-to-random" .env >nul 2>&1
if not errorlevel 1 (
    echo  [WARN] N8N_ENCRYPTION_KEY ใน .env ยังเป็นค่า default — ไม่ปลอดภัย!
    echo         แก้ไข .env โดยใช้คำสั่ง:
    echo         node -e "console.log(require('crypto').randomBytes(16).toString('hex'))"
    echo.
)
exit /b 0

:: ────────────────────────────────────────────────────────────
:SETUP
:: ────────────────────────────────────────────────────────────
cls
echo.
echo  [SETUP] เริ่มกระบวนการ Setup...
echo.
call :CHECK_PREREQ
if errorlevel 1 goto MENU

echo  [1/5] Pull Docker images...
docker compose pull
if errorlevel 1 ( echo  [ERROR] pull ล้มเหลว & pause & goto MENU )

echo.
echo  [2/5] Start services...
docker compose up -d
if errorlevel 1 ( echo  [ERROR] start ล้มเหลว & pause & goto MENU )

echo.
echo  [3/5] รอ Node-RED พร้อม (health check)...
call :WAIT_NODERED
if errorlevel 1 (
    echo  [WARN] Node-RED ยังไม่ตอบสนองหลังจาก 60s — ตรวจ logs ด้วย docker compose logs nodered
)

echo.
echo  [4/5] ติดตั้ง node-red-contrib-opcua...
docker exec nodered npm install node-red-contrib-opcua --prefix /data 2>nul
if errorlevel 1 (
    echo  [WARN] ติดตั้ง node-red-contrib-opcua ล้มเหลว — ลองติดตั้งผ่าน Node-RED UI แทน
) else (
    echo  [OK]  ติดตั้ง node-red-contrib-opcua สำเร็จ
    docker restart nodered >nul
    echo  [OK]  Restart Node-RED แล้ว
    timeout /t 5 /nobreak >nul
)

echo.
echo  [5/5] ตรวจสถานะ...
call :SHOW_STATUS
echo.
echo  Setup เสร็จสิ้น!
call :SHOW_URLS
pause & goto MENU

:: ────────────────────────────────────────────────────────────
:START
:: ────────────────────────────────────────────────────────────
cls
echo.
call :CHECK_PREREQ
if errorlevel 1 goto MENU
echo  กำลังเริ่ม services...
docker compose up -d
if errorlevel 1 ( echo  [ERROR] start ล้มเหลว & pause & goto MENU )
echo.
call :SHOW_STATUS
call :SHOW_URLS
pause & goto MENU

:: ────────────────────────────────────────────────────────────
:STOP
:: ────────────────────────────────────────────────────────────
cls
echo.
echo  กำลังหยุด services...
docker compose stop
echo  [OK] หยุดทุก services แล้ว
pause & goto MENU

:: ────────────────────────────────────────────────────────────
:RESTART
:: ────────────────────────────────────────────────────────────
cls
echo.
echo  กำลัง restart services...
docker compose restart
echo  [OK] Restart เสร็จสิ้น
timeout /t 3 /nobreak >nul
call :SHOW_STATUS
pause & goto MENU

:: ────────────────────────────────────────────────────────────
:STATUS
:: ────────────────────────────────────────────────────────────
cls
echo.
call :SHOW_STATUS
echo.
pause & goto MENU

:: ────────────────────────────────────────────────────────────
:LOGS
:: ────────────────────────────────────────────────────────────
cls
echo.
echo  เลือก service ที่ต้องการดู logs:
echo  [1] ทั้งหมด   [2] nodered   [3] n8n   [4] mosquitto
echo.
set /p LSERVICE="  เลือก [1-4]: "
if "%LSERVICE%"=="1" docker compose logs -f
if "%LSERVICE%"=="2" docker compose logs -f nodered
if "%LSERVICE%"=="3" docker compose logs -f n8n
if "%LSERVICE%"=="4" docker compose logs -f mosquitto
goto MENU

:: ────────────────────────────────────────────────────────────
:BROWSER
:: ────────────────────────────────────────────────────────────
echo.
echo  กำลังเปิด browser...
start http://localhost:1880
timeout /t 1 /nobreak >nul
start http://localhost:5678
echo  [OK] เปิด Node-RED (1880) และ N8N (5678) แล้ว
timeout /t 2 /nobreak >nul
goto MENU

:: ────────────────────────────────────────────────────────────
:RESET
:: ────────────────────────────────────────────────────────────
cls
echo.
echo  ╔══════════════════════════════════════════════════════════╗
echo  ║  [RESET] จะลบ volumes ทั้งหมด — ข้อมูลจะหายถาวร!       ║
echo  ╚══════════════════════════════════════════════════════════╝
echo.
set /p CONFIRM="  พิมพ์ YES เพื่อยืนยัน: "
if /i not "%CONFIRM%"=="YES" (
    echo  ยกเลิก
    timeout /t 2 /nobreak >nul
    goto MENU
)
docker compose down -v
echo  [OK] ลบ containers และ volumes ทั้งหมดแล้ว
pause & goto MENU

:: ────────────────────────────────────────────────────────────
:: Helper: รอ Node-RED ด้วย HTTP polling (สูงสุด 60s)
:: ────────────────────────────────────────────────────────────
:WAIT_NODERED
setlocal
set TRIES=0
:POLL
set /a TRIES+=1
if %TRIES% GTR 12 ( endlocal & exit /b 1 )
curl -s -o nul -w "%%{http_code}" http://localhost:1880 2>nul | findstr "200 301 302" >nul 2>&1
if not errorlevel 1 (
    echo  [OK]  Node-RED พร้อมแล้ว (ลอง %TRIES% ครั้ง)
    endlocal & exit /b 0
)
echo  [....] รอ... (%TRIES%/12)
timeout /t 5 /nobreak >nul
goto POLL

:: ────────────────────────────────────────────────────────────
:: Helper: แสดงสถานะ containers
:: ────────────────────────────────────────────────────────────
:SHOW_STATUS
echo  ┌─────────────────────────────────────────────────────────┐
echo  │  Container Status                                        │
echo  └─────────────────────────────────────────────────────────┘
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
exit /b 0

:: ────────────────────────────────────────────────────────────
:: Helper: แสดง URLs
:: ────────────────────────────────────────────────────────────
:SHOW_URLS
echo.
echo  ╔══════════════════════════════════════════════════════════╗
echo  ║  Node-RED  →  http://localhost:1880                      ║
echo  ║  N8N       →  http://localhost:5678                      ║
echo  ║  MQTT TCP  →  localhost:1883                             ║
echo  ║  MQTT WS   →  localhost:9001                             ║
echo  ╚══════════════════════════════════════════════════════════╝
exit /b 0

:EOF
endlocal
