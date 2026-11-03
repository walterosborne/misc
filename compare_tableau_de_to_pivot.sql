-- Read-only reconciliation of reference DE totals with SQL output.
-- Run in NGDS_WS_Supply. No objects are created or changed.
-- Original: [NORTHGRUM\N35589].[LaborForecastQuarterCompareFinal]
-- Notebook: [dbo].[LaborForecastQuarterCompareFinal_dev]
--
-- Reference values are rounded to whole DE by Segment.
-- Compare the SQL measures and their deltas; a difference under 0.5
-- can be ordinary display rounding. Compare the by-Type result using
-- the same date range, measure, and filters.
SET NOCOUNT ON;

DECLARE @pivot TABLE (
    forecast_month date NOT NULL,
    segment nvarchar(100) NOT NULL,
    pivot_de float NOT NULL,
    PRIMARY KEY (forecast_month, segment)
);
INSERT INTO @pivot (forecast_month, segment, pivot_de) VALUES
('2026-10-01',N'AP&S',188),('2026-10-01',N'NCTA',63),('2026-10-01',N'Propulsion & Controls',409),
('2026-11-01',N'AP&S',215),('2026-11-01',N'NCTA',38),('2026-11-01',N'Propulsion & Controls',412),
('2026-12-01',N'AP&S',196),('2026-12-01',N'NCTA',25),('2026-12-01',N'Propulsion & Controls',457),
('2027-01-01',N'AP&S',266),('2027-01-01',N'NCTA',94),('2027-01-01',N'Propulsion & Controls',534),
('2027-02-01',N'AP&S',271),('2027-02-01',N'NCTA',74),('2027-02-01',N'Propulsion & Controls',507),
('2027-03-01',N'AP&S',298),('2027-03-01',N'NCTA',80),('2027-03-01',N'Propulsion & Controls',428),
('2027-04-01',N'AP&S',278),('2027-04-01',N'NCTA',96),('2027-04-01',N'Propulsion & Controls',387),
('2027-05-01',N'AP&S',272),('2027-05-01',N'NCTA',95),('2027-05-01',N'Propulsion & Controls',386),
('2027-06-01',N'AP&S',280),('2027-06-01',N'NCTA',90),('2027-06-01',N'Propulsion & Controls',332),
('2027-07-01',N'AP&S',323),('2027-07-01',N'NCTA',133),('2027-07-01',N'Propulsion & Controls',375),
('2027-08-01',N'AP&S',294),('2027-08-01',N'NCTA',128),('2027-08-01',N'Propulsion & Controls',366),
('2027-09-01',N'AP&S',320),('2027-09-01',N'NCTA',127),('2027-09-01',N'Propulsion & Controls',373);

-- 1. Segment-level totals for both DE fields.
-- The all-Type total includes both Labor Forecast and Opportunity.
WITH rows AS (
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
totals AS (
    SELECT DATEFROMPARTS(YEAR(forecast_date),MONTH(forecast_date),1) AS forecast_month,
           segment, side, COUNT_BIG(*) AS row_count,
           SUM(new_de) AS new_de, SUM(prior_de) AS prior_de
    FROM rows
    WHERE forecast_date >= '2026-10-01' AND forecast_date < '2027-10-01'
      AND category = N'Hours'
    GROUP BY DATEFROMPARTS(YEAR(forecast_date),MONTH(forecast_date),1),segment,side
)
SELECT CONVERT(char(7),p.forecast_month,120) AS forecast_month, p.segment,
       p.pivot_de, o.row_count AS original_rows, d.row_count AS dev_rows,
       ROUND(o.new_de,3) AS original_new_de, ROUND(d.new_de,3) AS dev_new_de,
       ROUND(o.new_de-p.pivot_de,3) AS original_new_minus_pivot,
       ROUND(d.new_de-p.pivot_de,3) AS dev_new_minus_pivot,
       ROUND(o.prior_de,3) AS original_prior_de,
       ROUND(d.prior_de,3) AS dev_prior_de,
       ROUND(o.prior_de-p.pivot_de,3) AS original_prior_minus_pivot
FROM @pivot AS p
LEFT JOIN totals AS o ON o.forecast_month=p.forecast_month AND o.segment=p.segment AND o.side=N'original'
LEFT JOIN totals AS d ON d.forecast_month=p.forecast_month AND d.segment=p.segment AND d.side=N'dev'
ORDER BY p.forecast_month,p.segment;

-- 2. Monthly totals by Type and across all Types.
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
