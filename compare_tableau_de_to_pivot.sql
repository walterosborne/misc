-- Read-only reconciliation of raw monthly DE and processed forecast output.
-- Run in NGDS_WS_Supply after both dev uploads finish.
-- The raw table retains the DE basis used to generate its monthly totals.
SET NOCOUNT ON;

-- 1. Segment-level totals for each forecast month.
-- Raw values come from current workbook rows before downstream enrichment.
WITH raw_values AS (
    SELECT r.[DE Basis] AS de_basis,
           NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(255),r.[Segment]))),N'') AS segment,
           m.forecast_month, TRY_CONVERT(float,m.de_value) AS raw_de
    FROM [dbo].[LaborForecastRawDEBySegment_dev] AS r
    CROSS APPLY (VALUES
        (CONVERT(date,'2026-10-01'),r.[Oct-26]),
        (CONVERT(date,'2026-11-01'),r.[Nov-26]),
        (CONVERT(date,'2026-12-01'),r.[Dec-26]),
        (CONVERT(date,'2027-01-01'),r.[Jan-27]),
        (CONVERT(date,'2027-02-01'),r.[Feb-27]),
        (CONVERT(date,'2027-03-01'),r.[Mar-27]),
        (CONVERT(date,'2027-04-01'),r.[Apr-27]),
        (CONVERT(date,'2027-05-01'),r.[May-27]),
        (CONVERT(date,'2027-06-01'),r.[Jun-27]),
        (CONVERT(date,'2027-07-01'),r.[Jul-27]),
        (CONVERT(date,'2027-08-01'),r.[Aug-27]),
        (CONVERT(date,'2027-09-01'),r.[Sep-27])
    ) AS m(forecast_month,de_value)
),
rows AS (
    SELECT N'original' AS side, TRY_CONVERT(date,[DateTime_Out]) AS forecast_date,
           NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(255),[Segment]))),N'') AS segment,
           NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(255),[Category]))),N'') AS category,
           TRY_CONVERT(float,[NEW DE]) AS new_de,
           TRY_CONVERT(float,[Direct Equivalence]) AS prior_de
    FROM [NORTHGRUM\N35589].[LaborForecastQuarterCompareFinal]
    UNION ALL
    SELECT N'dev', TRY_CONVERT(date,[DateTime_Out]),
           NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(255),[Segment]))),N''),
           NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(255),[Category]))),N''),
           TRY_CONVERT(float,[NEW DE]), TRY_CONVERT(float,[Direct Equivalence])
    FROM [dbo].[LaborForecastQuarterCompareFinal_dev]
),
processed AS (
    SELECT DATEFROMPARTS(YEAR(forecast_date),MONTH(forecast_date),1) AS forecast_month,
           COALESCE(segment,N'(blank)') AS segment, side,
           COUNT_BIG(*) AS row_count,
           SUM(new_de) AS new_de, SUM(prior_de) AS prior_de
    FROM rows
    WHERE forecast_date >= '2026-10-01' AND forecast_date < '2027-10-01'
      AND category = N'Hours'
    GROUP BY DATEFROMPARTS(YEAR(forecast_date),MONTH(forecast_date),1),
             COALESCE(segment,N'(blank)'),side
),
paired AS (
    SELECT r.de_basis,COALESCE(r.forecast_month,p.forecast_month) AS forecast_month,
           COALESCE(r.segment,p.segment) AS segment,
           r.raw_de,
           MAX(CASE WHEN p.side=N'original' THEN p.row_count END) AS original_rows,
           MAX(CASE WHEN p.side=N'dev' THEN p.row_count END) AS dev_rows,
           MAX(CASE WHEN p.side=N'original' THEN p.new_de END) AS original_new_de,
           MAX(CASE WHEN p.side=N'dev' THEN p.new_de END) AS dev_new_de,
           MAX(CASE WHEN p.side=N'original' THEN p.prior_de END) AS original_prior_de,
           MAX(CASE WHEN p.side=N'dev' THEN p.prior_de END) AS dev_prior_de
    FROM raw_values AS r
    FULL OUTER JOIN processed AS p
      ON p.forecast_month=r.forecast_month
     AND p.segment=COALESCE(r.segment,N'(blank)')
    GROUP BY r.de_basis,COALESCE(r.forecast_month,p.forecast_month),
             COALESCE(r.segment,p.segment),r.raw_de
)
SELECT CONVERT(char(7),forecast_month,120) AS forecast_month,
       segment,de_basis,ROUND(raw_de,3) AS raw_de,
       original_rows,dev_rows,
       ROUND(original_new_de,3) AS original_new_de,
       ROUND(dev_new_de,3) AS dev_new_de,
       ROUND(raw_de-original_new_de,3) AS raw_minus_original,
       ROUND(raw_de-dev_new_de,3) AS raw_minus_dev,
       ROUND(original_prior_de,3) AS original_prior_de,
       ROUND(dev_prior_de,3) AS dev_prior_de
FROM paired
ORDER BY forecast_month,segment;

-- 2. Monthly processed totals by Type and across all Types.
-- No Segment filter is applied.
WITH rows AS (
    SELECT N'original' AS side, TRY_CONVERT(date,[DateTime_Out]) AS forecast_date,
           COALESCE(NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(255),[Type]))),N''),N'<NULL>') AS forecast_type,
           NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(255),[Category]))),N'') AS category,
           TRY_CONVERT(float,[NEW DE]) AS new_de,
           TRY_CONVERT(float,[Direct Equivalence]) AS prior_de,
           TRY_CONVERT(float,[NEW Hours]) AS new_hours,
           TRY_CONVERT(float,[Hours]) AS prior_hours
    FROM [NORTHGRUM\N35589].[LaborForecastQuarterCompareFinal]
    UNION ALL
    SELECT N'dev',TRY_CONVERT(date,[DateTime_Out]),
           COALESCE(NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(255),[Type]))),N''),N'<NULL>'),
           NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(255),[Category]))),N''),
           TRY_CONVERT(float,[NEW DE]),TRY_CONVERT(float,[Direct Equivalence]),
           TRY_CONVERT(float,[NEW Hours]),TRY_CONVERT(float,[Hours])
    FROM [dbo].[LaborForecastQuarterCompareFinal_dev]
)
SELECT CONVERT(char(7),forecast_date,120) AS forecast_month, side,
       CASE WHEN GROUPING(forecast_type)=1 THEN N'ALL TYPES' ELSE forecast_type END AS forecast_type,
       COUNT_BIG(*) AS rows, ROUND(SUM(new_de),3) AS new_de,
       ROUND(SUM(prior_de),3) AS prior_de,
       ROUND(SUM(new_hours),3) AS new_hours,
       ROUND(SUM(prior_hours),3) AS prior_hours
FROM rows
WHERE forecast_date >= '2026-10-01' AND forecast_date < '2027-10-01'
  AND category = N'Hours'
GROUP BY DATEFROMPARTS(YEAR(forecast_date),MONTH(forecast_date),1),
         CONVERT(char(7),forecast_date,120),side,ROLLUP(forecast_type)
ORDER BY forecast_month,side,
         CASE WHEN GROUPING(forecast_type)=1 THEN 1 ELSE 0 END,forecast_type;

-- 3. Find records the SQL chart query excludes: missing/invalid month,
-- non-Hours Category, or missing DE.
WITH rows AS (
    SELECT N'original' AS side,[DateTime_Out] AS raw_date,
           CONVERT(nvarchar(255),[Category]) AS category,
           CONVERT(nvarchar(255),[Type]) AS forecast_type,
           TRY_CONVERT(float,[NEW DE]) AS new_de
    FROM [NORTHGRUM\N35589].[LaborForecastQuarterCompareFinal]
    UNION ALL
    SELECT N'dev',[DateTime_Out],CONVERT(nvarchar(255),[Category]),
           CONVERT(nvarchar(255),[Type]),TRY_CONVERT(float,[NEW DE])
    FROM [dbo].[LaborForecastQuarterCompareFinal_dev]
)
SELECT side,
       CASE WHEN TRY_CONVERT(date,raw_date) IS NULL THEN N'missing/invalid date'
            WHEN TRY_CONVERT(date,raw_date) < '2026-10-01'
              OR TRY_CONVERT(date,raw_date) >= '2027-10-01' THEN N'outside 12 months'
            WHEN category IS NULL OR LTRIM(RTRIM(category)) <> N'Hours' THEN N'non-Hours category'
            WHEN new_de IS NULL THEN N'missing NEW DE'
            ELSE N'included in chart query' END AS bucket,
       COUNT_BIG(*) AS rows
FROM rows
GROUP BY side,
         CASE WHEN TRY_CONVERT(date,raw_date) IS NULL THEN N'missing/invalid date'
              WHEN TRY_CONVERT(date,raw_date) < '2026-10-01'
                OR TRY_CONVERT(date,raw_date) >= '2027-10-01' THEN N'outside 12 months'
              WHEN category IS NULL OR LTRIM(RTRIM(category)) <> N'Hours' THEN N'non-Hours category'
              WHEN new_de IS NULL THEN N'missing NEW DE'
              ELSE N'included in chart query' END
ORDER BY side,bucket;
