-- =============================================================================
-- Sensor Data Data Engineering Assessment
-- Database Initialization Script
-- =============================================================================
-- This script runs automatically on first database startup via Docker.
-- 
-- Only creates BRONZE layer (raw data storage).
-- SILVER and GOLD layers are created and managed by dbt.
-- =============================================================================


-- =============================================================================
-- BRONZE LAYER: Raw data exactly as received
-- =============================================================================
-- Purpose: Audit trail, reprocessing capability, debugging
-- Written by: POST /data API
-- Read by: dbt (bronze → silver transformation)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS bronze;

CREATE TABLE bronze.raw_readings (
    id              BIGSERIAL       PRIMARY KEY,
    raw_line        TEXT            NOT NULL,
    ingested_at     TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- Index: Incremental processing (dbt reads rows newer than last run)
CREATE INDEX idx_bronze_ingested_at 
    ON bronze.raw_readings (ingested_at);

COMMENT ON TABLE bronze.raw_readings IS 'Raw sensor data exactly as received from POST /data API';
COMMENT ON COLUMN bronze.raw_readings.raw_line IS 'Original line, e.g., "1649941817 Voltage 1.34"';


-- =============================================================================
-- SILVER and GOLD layers are created by dbt
-- See: dbt/models/staging/ and dbt/models/marts/
-- =============================================================================


-- =============================================================================
-- VERIFICATION
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE '✓ Schema bronze created';
    RAISE NOTICE '✓ Table bronze.raw_readings created';
    RAISE NOTICE '✓ Index idx_bronze_ingested_at created';
    RAISE NOTICE '';
    RAISE NOTICE 'Silver and Gold layers will be created by dbt.';
    RAISE NOTICE 'Database initialization complete!';
END $$;