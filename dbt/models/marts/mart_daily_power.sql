/*
    Mart model: Silver → Gold

    Calculates daily Power: AVG(Voltage) × AVG(Current) per day.

    Input:  silver.stg_readings (Voltage and Current readings)
    Output: gold.daily_power (one Power value per day)

    Strategy: Incremental with merge (upserts on reading_date)

    Note: reading_time is set to midnight UTC of the calculation day
          to match the expected output format for GET /data
*/

{{
    config(
        materialized='incremental',
        unique_key='reading_date',
        incremental_strategy='merge',
        post_hook=[
            "CREATE INDEX IF NOT EXISTS idx_gold_reading_date ON {{ this }} (reading_date)"
        ]
    )
}}

WITH source_readings AS (
    SELECT
        reading_date,
        metric_name,
        metric_value,
        processed_at
    FROM {{ ref('stg_readings') }}
    WHERE
        metric_name IN ('Voltage', 'Current')

        {% if is_incremental() %}
            -- Only include days that have new data since last run
            AND reading_date IN (
                SELECT DISTINCT new_data.reading_date
                FROM {{ ref('stg_readings') }} AS new_data
                WHERE new_data.processed_at > (
                    SELECT COALESCE(MAX(target.calculated_at), '1970-01-01'::timestamptz)
                    FROM {{ this }} AS target
                )
            )
        {% endif %}
),

daily_averages AS (
    SELECT
        reading_date,
        AVG(CASE WHEN metric_name = 'Voltage' THEN metric_value END) AS avg_voltage,
        AVG(CASE WHEN metric_name = 'Current' THEN metric_value END) AS avg_current
    FROM source_readings
    GROUP BY reading_date
),

power_calculation AS (
    SELECT
        reading_date,
        avg_voltage,
        avg_current,
        avg_voltage * avg_current AS power_value
    FROM daily_averages
    -- Only calculate Power if we have BOTH Voltage and Current for that day
    WHERE
        avg_voltage IS NOT NULL
        AND avg_current IS NOT NULL
)

SELECT
    -- Midnight UTC of the calculation day
    'Power' AS metric_name,

    -- Fixed metric name for Power readings
    power_value AS metric_value,

    -- Calculated Power value
    reading_date,

    -- Date for indexing/filtering (unique key)
    (reading_date::timestamp AT TIME ZONE 'UTC') AS reading_time,

    -- Audit timestamp
    NOW() AS calculated_at

FROM power_calculation
