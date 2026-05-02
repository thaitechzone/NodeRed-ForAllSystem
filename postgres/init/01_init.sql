-- ============================================================
-- IoT Platform — PostgreSQL Init Script
-- รันอัตโนมัติครั้งแรกที่ container สร้าง
-- ============================================================

-- ตารางเก็บข้อมูล telemetry จากเครื่องจักร
CREATE TABLE IF NOT EXISTS energy_telemetry (
    id               BIGSERIAL PRIMARY KEY,
    machine_id       VARCHAR(50)   NOT NULL,
    timestamp        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    active_power_kw  NUMERIC(10,3),
    reactive_power_kvar NUMERIC(10,3),
    apparent_power_kva  NUMERIC(10,3),
    power_factor     NUMERIC(5,3),
    current_max      NUMERIC(8,3),
    load_pct         NUMERIC(5,1),
    motor_rpm        INTEGER,
    frequency_hz     NUMERIC(6,2),
    energy_today_kwh NUMERIC(10,4),
    alarm_overcurrent BOOLEAN DEFAULT FALSE,
    spike_event      BOOLEAN DEFAULT FALSE
);

-- ตารางเก็บผล AI วิเคราะห์
CREATE TABLE IF NOT EXISTS ai_decisions (
    id              BIGSERIAL PRIMARY KEY,
    machine_id      VARCHAR(50)  NOT NULL,
    analyzed_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    reduce_power    BOOLEAN      NOT NULL,
    risk_level      VARCHAR(10),
    reason          TEXT,
    recommendation  TEXT,
    summary         TEXT,
    ai_model        VARCHAR(100),
    power_avg_kw    NUMERIC(10,3),
    load_avg_pct    NUMERIC(5,1)
);

-- Index สำหรับ query ตาม machine_id และ timestamp
CREATE INDEX IF NOT EXISTS idx_telemetry_machine_time
    ON energy_telemetry (machine_id, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_decisions_machine_time
    ON ai_decisions (machine_id, analyzed_at DESC);
