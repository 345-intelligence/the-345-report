# Get an 'at-scale' manufacturing dataset for free

---

## Download two datasets
1. **5M rows**: For development
2. **50M rows**: For stress testing

---

**Step 1:** Headover to [Big Query](https://console.cloud.google.com/bigquery?invt=AbuCSQ&project=business-analytics-deg&ws=!1m0). Set up your sandbox, if required.

**Step 2:** Go to the [NYC Taxi Trips dataset](https://console.cloud.google.com/bigquery?ws=!1m5!1m4!4m3!1sbigquery-public-data!2snew_york_taxi_trips!3stlc_yellow_trips_2019)

**Step 3:** Run 02-nyc-taxi-trips below. 

*Important note:* about table size. This is an 84M row dataset. To avoid being charged for running the whole table, adjust the tablesample size to the desired return rate. As coded below, it is at .5% (~75MBs) or ~500K rows.

*Double note:* Limit **does not** reduce table scan, only tablesample does. 

**Step 4:** Once you're satisfied with your result and you want to download it, you will notice that it is too big to dump in Google Drive or a CSV. To get this to your local device, run 03-stream-from-bq-w-python.ps1 in PowerShell. There is no cap here (other than your machine's limitations).

*Step 4A:* Make sure you put in *your billing project on Line 8* of 03-stream-from-bq-w-python.ps1

**Step 5:** Have fun with a *massive* dataset! If you're looking for local tools to help you manage this data, try [DuckDB](https://duckdb.org/).
