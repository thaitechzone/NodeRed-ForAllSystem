module.exports = {
    // ─── Web UI ──────────────────────────────────────────────
    uiPort: process.env.PORT || 1880,
    uiHost: "0.0.0.0",

    // ─── Security ─────────────────────────────────────────────
    // สร้าง password hash ที่ https://bcrypt-generator.com (rounds=8)
    // แล้วใส่ค่าที่ได้ลงใน .env ที่ตัวแปร NR_ADMIN_PASSWORD_HASH
    // 
    // วิธีสร้าง hash:
    // 1. ไปที่ https://bcrypt-generator.com
    // 2. ใส่ password ที่ต้องการ (เช่น admin)
    // 3. เลือก rounds = 8
    // 4. คัดลอก hash ที่ได้ (ต้องขึ้นต้นด้วย $2a$08$ หรือ $2b$08$)
    // 5. นำไปใส่ใน .env ที่ NR_ADMIN_PASSWORD_HASH
    // adminAuth: {
    //     type: "credentials",
    //     users: [{
    //         username: process.env.NR_ADMIN_USERNAME || "admin",
    //         password: process.env.NR_ADMIN_PASSWORD_HASH || "$2a$08$0tiQX3iR0J.CwzdfG4pC..25y9aClLJSzDB8CfrCC1gBkyIU2RLAu",
    //         permissions: "*"
    //     }]
    // },

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
