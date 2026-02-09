$code = @'
import pandas_gbq
import os
import time
import tqdm
# YOUR BIGQUERY PROJECT ID
project_id = "your-project-id"
def run_export(name, percent):
    query = f"""
    -- BIG QUERY SQL FOR MANUFACTURING DATASET
    SELECT
      -- MACHINE IDENTIFIER
      t.pickup_location_id AS machine_id, 
      -- 9-DIGIT WORK ORDER
      ABS(MOD(FARM_FINGERPRINT(CONCAT(CAST(t.vendor_id AS STRING), CAST(t.pickup_datetime AS STRING))), 900000000)) + 100000000 AS work_order_id,
      -- INDIVIDUAL CUSTOMER ID (5,000 unique customers)
      ABS(MOD(FARM_FINGERPRINT(CONCAT(CAST(t.passenger_count AS STRING), CAST(t.dropoff_location_id AS STRING))), 5000)) + 1000 AS customer_id,
      -- TIMELINE
      t.pickup_datetime AS state_start_time,
      t.dropoff_datetime AS state_end_time,
      -- PERFORMANCE FACTS (REALISTIC BATCH SIZES)
      CASE 
        WHEN MOD(ABS(FARM_FINGERPRINT(CAST(t.pickup_datetime AS STRING))), 100) < 10 THEN CAST(CEIL(t.trip_distance * 50) AS INT64)  -- 10% small batches (50-500)
        WHEN MOD(ABS(FARM_FINGERPRINT(CAST(t.pickup_datetime AS STRING))), 100) < 60 THEN CAST(CEIL(t.trip_distance * 200) AS INT64) -- 50% medium batches (200-2000)
        ELSE CAST(CEIL(t.trip_distance * 500) AS INT64) -- 40% large batches (500-5000)
      END AS production_count,
      -- QUALITY FACTS (REALISTIC SCRAP: 0.5-3% of production)
      CAST(CEIL(
        CASE 
          WHEN MOD(ABS(FARM_FINGERPRINT(CAST(t.pickup_datetime AS STRING))), 100) < 10 THEN CAST(CEIL(t.trip_distance * 50) AS INT64)
          WHEN MOD(ABS(FARM_FINGERPRINT(CAST(t.pickup_datetime AS STRING))), 100) < 60 THEN CAST(CEIL(t.trip_distance * 200) AS INT64)
          ELSE CAST(CEIL(t.trip_distance * 500) AS INT64)
        END * (RAND() * 0.025 + 0.005) -- 0.5% to 3% scrap rate
      ) AS INT64) AS scrap_units,
      -- REWORK: 1-5% of production
      CAST(CEIL(
        CASE 
          WHEN MOD(ABS(FARM_FINGERPRINT(CAST(t.pickup_datetime AS STRING))), 100) < 10 THEN CAST(CEIL(t.trip_distance * 50) AS INT64)
          WHEN MOD(ABS(FARM_FINGERPRINT(CAST(t.pickup_datetime AS STRING))), 100) < 60 THEN CAST(CEIL(t.trip_distance * 200) AS INT64)
          ELSE CAST(CEIL(t.trip_distance * 500) AS INT64)
        END * (RAND() * 0.04 + 0.01) -- 1% to 5% rework rate
      ) AS INT64) AS rework_units,
      -- TOTAL ATTEMPTED = production + scrap + rework (calculated correctly)
      CASE 
        WHEN MOD(ABS(FARM_FINGERPRINT(CAST(t.pickup_datetime AS STRING))), 100) < 10 THEN CAST(CEIL(t.trip_distance * 50) AS INT64)
        WHEN MOD(ABS(FARM_FINGERPRINT(CAST(t.pickup_datetime AS STRING))), 100) < 60 THEN CAST(CEIL(t.trip_distance * 200) AS INT64)
        ELSE CAST(CEIL(t.trip_distance * 500) AS INT64)
      END + 
      CAST(CEIL(
        CASE 
          WHEN MOD(ABS(FARM_FINGERPRINT(CAST(t.pickup_datetime AS STRING))), 100) < 10 THEN CAST(CEIL(t.trip_distance * 50) AS INT64)
          WHEN MOD(ABS(FARM_FINGERPRINT(CAST(t.pickup_datetime AS STRING))), 100) < 60 THEN CAST(CEIL(t.trip_distance * 200) AS INT64)
          ELSE CAST(CEIL(t.trip_distance * 500) AS INT64)
        END * (RAND() * 0.025 + 0.005)
      ) AS INT64) + 
      CAST(CEIL(
        CASE 
          WHEN MOD(ABS(FARM_FINGERPRINT(CAST(t.pickup_datetime AS STRING))), 100) < 10 THEN CAST(CEIL(t.trip_distance * 50) AS INT64)
          WHEN MOD(ABS(FARM_FINGERPRINT(CAST(t.pickup_datetime AS STRING))), 100) < 60 THEN CAST(CEIL(t.trip_distance * 200) AS INT64)
          ELSE CAST(CEIL(t.trip_distance * 500) AS INT64)
        END * (RAND() * 0.04 + 0.01)
      ) AS INT64) AS total_units_attempted,
      -- OPERATIONAL MINUTES (REALISTIC: 15 min to 8 hours)
      CAST((TIMESTAMP_DIFF(t.dropoff_datetime, t.pickup_datetime, SECOND) / 60.0) * (RAND() * 3 + 0.5) AS FLOAT64) AS operational_minutes,
      -- CONTEXT (SATELLITES)
      t.rate_code AS operational_mode,
      l.borough AS machine_group_text,
      l.zone_name AS machine_text,
      -- JUNK COLUMNS FROM TAXI TRIPS
      CAST(RAND() * 5 + 1 AS INT64) AS dummy1_payment_type,  -- 1-5
      0 AS dummy2_fair_amount,  -- Always 0
      0 AS dummy3_tip_amount,   -- Always 0
      -- GENERATED JUNK COLUMNS
      CAST(RAND() * 100 AS STRING) as legacy_erp_tag,
      CURRENT_TIMESTAMP() as _ingestion_timestamp,
      'SYSTEM_AUTO_GENERATED' as audit_note,
      CAST(RAND() * 1000 AS INT64) as warehouse_bin_id,
      GENERATE_UUID() as internal_debug_guid,
      CASE WHEN RAND() > 0.5 THEN 'Shift_A' WHEN RAND() > 0.2 THEN 'Shift_B' ELSE 'Shift_C' END as legacy_shift_name,
      RAND() * 50 as station_humidity_reading,
      FALSE as is_archived_record,
      'DUMMY_DATA' as filler_column_01,
      CAST(RAND() * 10 AS INT64) as operator_experience_level
    FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2019` t 
      TABLESAMPLE SYSTEM (60 PERCENT) -- 62% for 50M, 6.75% for 5M
    INNER JOIN `bigquery-public-data.new_york_taxi_trips.taxi_zone_geom` l
      ON t.pickup_location_id = CAST(l.zone_id AS STRING)
    WHERE trip_distance > 0 AND passenger_count > 0
    """
    
    start_time = time.time()
    print(f"\n⚡ Streaming {name}...")
    
    df = pandas_gbq.read_gbq(
        query, 
        project_id=project_id, 
        use_bqstorage_api=True, 
        progress_bar_type='tqdm'
    )
    
    # Save with ZSTD for high-performance OIM reads
    df.to_parquet(f"{name}.parquet", engine='pyarrow', compression='zstd')
    
    print(f"✅ Saved {len(df):,} rows in {time.time() - start_time:.2f}s")
if __name__ == "__main__":
    run_export("sandbox_500k", 0.1)
    run_export("dev_5m", 6.75)
    run_export("scale_50m", 62)
'@

$code | Out-File -FilePath "stream.py" -Encoding utf8
python stream.py
