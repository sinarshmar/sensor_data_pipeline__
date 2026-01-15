/*
    Staging model: Bronze → Silver

    Transforms raw sensor data into typed, validated readings.

    Input:  bronze.raw_readings (raw lines like "1649941817 Voltage 1.34")
    Output: silver.stg_readings (typed columns: reading_time, metric_name, metric_value)

    Strategy: Incremental with merge (deduplicates on raw_id)
    Watermark: ingested_at from source, compared against processed_at in target
*/

{{
    config(
        materialized='incremental',
        unique_key='raw_id',
        incremental_strategy='merge',
        post_hook=[
            "CREATE INDEX IF NOT EXISTS idx_silver_reading_date ON {{ this }} (reading_date)",
            "CREATE INDEX IF NOT EXISTS idx_silver_date_metric ON {{ this }} (reading_date, metric_name)"
        ]
    )
}}

WITH raw_data AS (
    SELECT
        id AS raw_id,
        raw_line,
        ingested_at
    FROM bronze.raw_readings

    {% if is_incremental() %}
    -- Only process rows ingested after the last run
        WHERE ingested_at > (
            SELECT COALESCE(MAX(target.processed_at), '1970-01-01'::timestamptz)
            FROM {{ this }} AS target
        )
    {% endif %}
),

parsed AS (
    SELECT
        raw_id,
        ingested_at,

        -- Split the raw line into parts
        -- Format: "{timestamp} {metric_name} {value}"
        SPLIT_PART(raw_line, ' ', 1) AS timestamp_str,
        SPLIT_PART(raw_line, ' ', 2) AS metric_name,
        SPLIT_PART(raw_line, ' ', 3) AS value_str
    FROM raw_data
    WHERE
        raw_line IS NOT NULL
        AND LENGTH(TRIM(raw_line)) > 0
),

validated AS (
    SELECT
        raw_id,
        ingested_at,
        timestamp_str,
        metric_name,
        value_str,

        -- Validate: timestamp is numeric and positive
        timestamp_str ~ '^\d+$' AS is_valid_timestamp,

        -- Validate: metric_name starts with letter
        metric_name ~ '^[A-Za-z]' AS is_valid_name,

        -- Validate: value is numeric
        value_str ~ '^-?\d+\.?\d*$' AS is_valid_value
    FROM parsed
),

typed AS (
    SELECT
        -- Include raw_id for deduplication (unique_key)
        raw_id,

        -- Convert Unix timestamp to timestamptz
        metric_name,

        value_str::double precision AS metric_value,

        -- Convert value to float
        TO_TIMESTAMP(timestamp_str::bigint)::date AS reading_date,

        -- Extract date for indexing/partitioning
        TO_TIMESTAMP(timestamp_str::bigint) AS reading_time,

        -- Track when processed (used as watermark for next incremental run)
        NOW() AS processed_at

    FROM validated
    WHERE
        is_valid_timestamp
        AND is_valid_name
        AND is_valid_value
)

SELECT
    raw_id,
    reading_time,
    metric_name,
    metric_value,
    reading_date,
    processed_at
FROM typed
