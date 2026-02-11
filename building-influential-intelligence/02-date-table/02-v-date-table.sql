/* 
-------------------------------------
V_DATE_TABLE
-------------------------------------
Author:   David Gastineau
Week ends on Sunday (week starts Monday)
Start/End controlled in params CTE
Timezone: America/Chicago
-------------------------------------
*/

WITH
/* =========================
   PARAMETERS (edit here)
   ========================= */
params AS (
  SELECT
    'America/Chicago' AS tz,

    -- ✅ "Parameter": start date
    
    -- Hard coded
    DATE '2026-01-01' AS start_date, 
    -- Dynamic | Comment above and activate below to use
    -- DATE_TRUNC(DATE_SUB(CURRENT_DATE('America/Chicago'), INTERVAL 0 YEAR), YEAR) AS start_date,

    -- ✅ "Parameter": end date (default = end of year, today + x years)

    -- Hard coded
    -- DATE '2026-12-31' AS end_date,
    -- Dynamic | Comment below and activate above to use
    LAST_DAY(DATE_ADD(CURRENT_DATE('America/Chicago'), INTERVAL 0 YEAR), YEAR) AS end_date,

    -- Anchor values computed once
    CURRENT_DATE('America/Chicago') AS today,
    EXTRACT(YEAR FROM CURRENT_DATE('America/Chicago')) AS curr_year,
    EXTRACT(QUARTER FROM CURRENT_DATE('America/Chicago')) AS curr_quarter,
    EXTRACT(MONTH FROM CURRENT_DATE('America/Chicago')) AS curr_month,
    DATE_TRUNC(CURRENT_DATE('America/Chicago'), WEEK(MONDAY)) AS curr_week_start
),

/* =========================
   CALENDAR SPINE
   ========================= */
calendar AS (
  SELECT day
  FROM params p,
  UNNEST(GENERATE_DATE_ARRAY(p.start_date, p.end_date, INTERVAL 1 DAY)) AS day
),

/* =========================
   BASE FIELDS (compute once)
   ========================= */
base AS (
  SELECT
    c.day AS date,

    /*--YEAR--------------------------------------------------------*/
    EXTRACT(YEAR FROM c.day) AS year,
    FORMAT_DATE('%Y', c.day) AS year_text,
    DATE_TRUNC(c.day, YEAR) AS start_of_year,
    LAST_DAY(c.day, YEAR) AS end_of_year,

    /*--QUARTER-----------------------------------------------------*/
    EXTRACT(QUARTER FROM c.day) AS quarter_number,
    CONCAT('Q', CAST(EXTRACT(QUARTER FROM c.day) AS STRING)) AS quarter,
    CONCAT('Q', CAST(EXTRACT(QUARTER FROM c.day) AS STRING), ' ', FORMAT_DATE('%Y', c.day)) AS quarter_year,
    (EXTRACT(YEAR FROM c.day) * 10 + EXTRACT(QUARTER FROM c.day)) AS quarternyear,
    DATE_TRUNC(c.day, QUARTER) AS start_of_quarter,
    LAST_DAY(c.day, QUARTER) AS end_of_quarter,

    /*--MONTH-------------------------------------------------------*/
    EXTRACT(MONTH FROM c.day) AS month_number,
    FORMAT_DATE('%B', c.day) AS month_name,
    FORMAT_DATE('%b', c.day) AS month_name_short,
    FORMAT_DATE('%d', c.day) AS day_of_month,
    DATE_TRUNC(c.day, MONTH) AS start_of_month,
    LAST_DAY(c.day, MONTH) AS end_of_month,
    FORMAT_DATE('%b %Y', c.day) AS month_year,
    (EXTRACT(YEAR FROM c.day) * 100 + EXTRACT(MONTH FROM c.day)) AS monthnyear,

    /*--WEEK (Mon start / Sun end)----------------------------------*/
    DATE_TRUNC(c.day, WEEK(MONDAY)) AS start_of_week,
    LAST_DAY(c.day, WEEK(MONDAY)) AS end_of_week,

    FORMAT_DATE('%U', c.day) AS week_number,
    CONCAT('W', CAST(FORMAT_DATE('%U', c.day) AS INT64), ' ', FORMAT_DATE('%Y', c.day)) AS week_year,

    CONCAT(
      CAST(EXTRACT(YEAR FROM LAST_DAY(c.day, WEEK(MONDAY))) AS STRING),
      LPAD(CAST(EXTRACT(WEEK FROM LAST_DAY(c.day, WEEK(MONDAY))) AS STRING), 2, '0')
    ) AS weeknyear,

    /*--DAY---------------------------------------------------------*/
    -- ISO-like day of week number 
    CAST(FORMAT_DATE('%u', c.day) AS INT64) AS day_of_week_number,
    FORMAT_DATE('%A', c.day) AS day_name,
    FORMAT_DATE('%a', c.day) AS day_name_short,

    -- Date key
    CAST(FORMAT_DATE('%Y%m%d', c.day) AS INT64) AS date_key

  FROM calendar c
),

/* =========================
   HOLIDAY NAME (single source of truth)
   ========================= */
holidays AS (
  SELECT
    b.*,

    CASE
      -- NEW YEAR'S DAY
      WHEN EXTRACT(MONTH FROM b.date) = 1 AND EXTRACT(DAY FROM b.date) = 1
        THEN "New Year's Day"

      -- MARTIN LUTHER KING DAY (3rd Monday in January)
      WHEN EXTRACT(MONTH FROM b.date) = 1
        AND EXTRACT(DAYOFWEEK FROM b.date) = 2  -- Monday (Sun=1)
        AND EXTRACT(DAY FROM b.date) BETWEEN 15 AND 21
        THEN 'MLK Day'

      -- MEMORIAL DAY (last Monday in May)
      WHEN EXTRACT(MONTH FROM b.date) = 5
        AND EXTRACT(DAYOFWEEK FROM b.date) = 2
        AND b.date >= DATE_SUB(b.end_of_month, INTERVAL 6 DAY)
        THEN 'Memorial Day'

      -- INDEPENDENCE DAY
      WHEN EXTRACT(MONTH FROM b.date) = 7 AND EXTRACT(DAY FROM b.date) = 4
        THEN 'Independence Day'

      -- LABOR DAY (1st Monday in September)
      WHEN EXTRACT(MONTH FROM b.date) = 9
        AND EXTRACT(DAYOFWEEK FROM b.date) = 2
        AND EXTRACT(DAY FROM b.date) <= 7
        THEN 'Labor Day'

      -- THANKSGIVING (4th Thursday in November)
      WHEN EXTRACT(MONTH FROM b.date) = 11
        AND EXTRACT(DAYOFWEEK FROM b.date) = 5  -- Thursday
        AND EXTRACT(DAY FROM b.date) BETWEEN 22 AND 28
        THEN 'Thanksgiving Day'

      -- DAY AFTER THANKSGIVING (Friday after Thanksgiving)
      WHEN EXTRACT(MONTH FROM b.date) = 11
        AND EXTRACT(DAYOFWEEK FROM b.date) = 6  -- Friday
        AND EXTRACT(DAY FROM b.date) BETWEEN 23 AND 29
        AND EXTRACT(DAYOFWEEK FROM DATE_SUB(b.date, INTERVAL 1 DAY)) = 5
        AND EXTRACT(DAY FROM DATE_SUB(b.date, INTERVAL 1 DAY)) BETWEEN 22 AND 28
        THEN 'Day After Thanksgiving'

      -- CHRISTMAS EVE
      WHEN EXTRACT(MONTH FROM b.date) = 12 AND EXTRACT(DAY FROM b.date) = 24
        THEN 'Christmas Eve'

      -- CHRISTMAS DAY
      WHEN EXTRACT(MONTH FROM b.date) = 12 AND EXTRACT(DAY FROM b.date) = 25
        THEN 'Christmas Day'

      ELSE NULL
    END AS holiday_name

  FROM base b
),

/* =========================
   FINAL SHAPING
   ========================= */
final AS (
  SELECT
    h.date AS date,

    /*--YEAR--------------------------------------------------------*/
    h.year,
    h.year_text,
    (h.year - p.curr_year) AS offset_year,
    h.start_of_year,
    h.end_of_year,
    (p.today > h.end_of_year) AS year_completed,

    /*--QUARTER-----------------------------------------------------*/
    h.quarter_number,
    h.quarter,
    h.quarter_year,
    h.quarternyear,
    ((h.year * 4 + h.quarter_number) - (p.curr_year * 4 + p.curr_quarter)) AS offset_quarter,
    h.start_of_quarter,
    h.end_of_quarter,
    (p.today > h.end_of_quarter) AS quarter_complete,

    /*--MONTH-------------------------------------------------------*/
    h.month_number,
    h.month_name,
    h.month_name_short,
    h.day_of_month,
    h.start_of_month,
    h.end_of_month,
    h.month_year,
    h.monthnyear,
    ((h.year * 12 + h.month_number) - (p.curr_year * 12 + p.curr_month)) AS offset_month,
    (p.today > h.end_of_month) AS month_complete,

    /*--WEEK--------------------------------------------------------*/
    h.week_number,
    h.week_year,
    h.weeknyear,

    -- Stable offset: difference between week starts (Monday-based weeks)
    DATE_DIFF(h.start_of_week, p.curr_week_start, WEEK) AS offset_week,

    h.start_of_week,
    h.end_of_week,
    (p.today > h.end_of_week) AS week_complete,

    /*--DAY---------------------------------------------------------*/
    h.day_of_week_number,
    h.day_name,
    h.day_name_short,

    DATE_DIFF(h.date, p.today, DAY) AS offset_day,
    IF(h.date < p.today, 1, 0) AS past_due,
    (h.date < p.today) AS past_due_boolean,
    (h.date > p.today) AS after_today,

    /*--WEEKDAY / HOLIDAY / BUSINESS DAY----------------------------*/
    (h.day_of_week_number <= 5) AS weekday,
    (h.holiday_name IS NOT NULL) AS holiday,
    h.holiday_name,
    ((h.day_of_week_number <= 5) AND h.holiday_name IS NULL) AS business_day,

    /*--OPTIONAL KEY-----------------------------------------------*/
    h.date_key

  FROM holidays h
  CROSS JOIN params p
)

SELECT
  * 
FROM final
ORDER BY date;
