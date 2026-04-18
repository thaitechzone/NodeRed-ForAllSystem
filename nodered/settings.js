module.exports = {
    // ─── Web UI ──────────────────────────────────────────────
    uiPort: process.env.PORT || 1880,
    uiHost: "0.0.0.0",

    // ─── Security ─────────────────────────────────────────────
    // สร้าง password hash ที่ https://bcrypt-generator.com (rounds=8)
    // แล้วใส่ค่าที่ได้ลงใน .env ที่ตัวแปร NR_ADMIN_PASSWORD_HASH
    adminAuth: {
        type: "credentials",
        users: [{
            username: process.env.NR_ADMIN_USERNAME || "admin",
            password: process.env.NR_ADMIN_PASSWORD_HASH,
            permissions: "*"
        }]
    },

    // ─── Timezone ────────────────────────────────────────────
    timezone: "Asia/Bangkok",

    // ─── Logging ─────────────────────────────────────────────
    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: false
        }
    },

    // ─── Editor ──────────────────────────────────────────────
    editorTheme: {
        projects: {
            enabled: false
        },
        palette: {
            // nodes ที่ติดตั้งเพิ่ม
        }
    },

    // ─── Context Storage ─────────────────────────────────────
    contextStorage: {
        default: {
            module: "memory"
        },
        file: {
            module: "localfilesystem"
        }
    },

    // ─── Function Global Context ──────────────────────────────
    functionGlobalContext: {},

    // ─── Node Settings ────────────────────────────────────────
    debugMaxLength: 1000,
    mqttReconnectTime: 15000,
    serialReconnectTime: 15000,
}
