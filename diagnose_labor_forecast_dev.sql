-- Read-only, compact follow-up to compare_labor_forecast_dev.sql.
-- Run in NGDS_WS_Supply after both notebook output cells finish.
-- Production: [NORTHGRUM\N35589]; notebook outputs: [dbo].
SET NOCOUNT ON;

-- Compare month/type/category row counts and major measures.
-- A zero or large gap identifies the stage/source to investigate next.
WITH forecast_rows AS (
    SELECT N'original' AS side,
           CONVERT(char(7), TRY_CONVERT(date, [DateTime_Out]), 120) AS forecast_month,
           NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(255), [Type]))), N'') AS forecast_type,
           NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(255), [Category]))), N'') AS category,
           TRY_CONVERT(float, [NEW Hours]) AS new_hours,
           TRY_CONVERT(float, [Hours]) AS prior_hours,
           TRY_CONVERT(float, [NEW FTEs]) AS new_ftes,
           TRY_CONVERT(float, [FTEs]) AS prior_ftes
    FROM [NORTHGRUM\N35589].[LaborForecastQuarterCompareFinal]
    UNION ALL
    SELECT N'dev',
           CONVERT(char(7), TRY_CONVERT(date, [DateTime_Out]), 120),
           NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(255), [Type]))), N''),
           NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(255), [Category]))), N''),
           TRY_CONVERT(float, [NEW Hours]),
           TRY_CONVERT(float, [Hours]),
           TRY_CONVERT(float, [NEW FTEs]),
           TRY_CONVERT(float, [FTEs])
    FROM [dbo].[LaborForecastQuarterCompareFinal_dev]
),
forecast_summary AS (
    SELECT forecast_month, forecast_type, category,
           SUM(CASE WHEN side = N'original' THEN CONVERT(bigint, 1) ELSE CONVERT(bigint, 0) END) AS original_rows,
           SUM(CASE WHEN side = N'dev' THEN CONVERT(bigint, 1) ELSE CONVERT(bigint, 0) END) AS dev_rows,
           SUM(CASE WHEN side = N'original' THEN new_hours ELSE 0 END) AS original_new_hours,
           SUM(CASE WHEN side = N'dev' THEN new_hours ELSE 0 END) AS dev_new_hours,
           SUM(CASE WHEN side = N'original' THEN prior_hours ELSE 0 END) AS original_prior_hours,
           SUM(CASE WHEN side = N'dev' THEN prior_hours ELSE 0 END) AS dev_prior_hours,
           SUM(CASE WHEN side = N'original' THEN new_ftes ELSE 0 END) AS original_new_ftes,
           SUM(CASE WHEN side = N'dev' THEN new_ftes ELSE 0 END) AS dev_new_ftes
    FROM forecast_rows
    GROUP BY forecast_month, forecast_type, category
)
SELECT forecast_month, forecast_type, category,
       original_rows, dev_rows, dev_rows - original_rows AS row_difference,
       original_new_hours, dev_new_hours,
       original_prior_hours, dev_prior_hours,
       original_new_ftes, dev_new_ftes
FROM forecast_summary
WHERE original_rows <> dev_rows
   OR ABS(COALESCE(original_new_hours, 0) - COALESCE(dev_new_hours, 0)) > 0.01
   OR ABS(COALESCE(original_prior_hours, 0) - COALESCE(dev_prior_hours, 0)) > 0.01
   OR ABS(COALESCE(original_new_ftes, 0) - COALESCE(dev_new_ftes, 0)) > 0.01
ORDER BY forecast_month, forecast_type, category;

-- Headcount by Type: determine whether gaps are in needs, actuals, or both.
WITH headcount_rows AS (
    SELECT N'original' AS side,
           COALESCE(NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(255), [Type]))), N''), N'<NULL>') AS forecast_type,
           TRY_CONVERT(float, [FTE Need]) AS fte_need,
           TRY_CONVERT(float, [Headcount Actuals]) AS headcount_actuals
    FROM [NORTHGRUM\N35589].[HeadcountVSActuals]
    UNION ALL
    SELECT N'dev',
           COALESCE(NULLIF(LTRIM(RTRIM(CONVERT(nvarchar(255), [Type]))), N''), N'<NULL>'),
           TRY_CONVERT(float, [FTE Need]),
           TRY_CONVERT(float, [Headcount Actuals])
    FROM [dbo].[HeadcountVSActuals_dev]
)
SELECT forecast_type,
       SUM(CASE WHEN side = N'original' THEN 1 ELSE 0 END) AS original_rows,
       SUM(CASE WHEN side = N'dev' THEN 1 ELSE 0 END) AS dev_rows,
       SUM(CASE WHEN side = N'original' THEN fte_need ELSE 0 END) AS original_fte_need,
       SUM(CASE WHEN side = N'dev' THEN fte_need ELSE 0 END) AS dev_fte_need,
       SUM(CASE WHEN side = N'original' THEN headcount_actuals ELSE 0 END) AS original_headcount,
       SUM(CASE WHEN side = N'dev' THEN headcount_actuals ELSE 0 END) AS dev_headcount
FROM headcount_rows
GROUP BY forecast_type
ORDER BY forecast_type;

-- Source metadata: check whether the Alteryx table and notebook were built
-- from the same workbook versions. The metadata formats may differ.
SELECT N'original' AS side, [TimeStamp] AS output_timestamp,
       LEFT(CONVERT(nvarchar(max), [Concat_File Name & Last Time Updated]), 1000) AS input_files
FROM [NORTHGRUM\N35589].[LaborForecastQuarterCompareFinal]
ORDER BY TRY_CONVERT(datetime2, [TimeStamp]) DESC
OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY;
SELECT N'dev' AS side, [TimeStamp] AS output_timestamp,
       LEFT(CONVERT(nvarchar(max), [Concat_File Name & Last Time Updated]), 1000) AS input_files
FROM [dbo].[LaborForecastQuarterCompareFinal_dev]
ORDER BY TRY_CONVERT(datetime2, [TimeStamp]) DESC
OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY;

-- The month summary showed 99 extra production Labor Forecast rows per month
-- from Oct 2026 through Aug 2027. Locate the October cohort by business keys.
WITH october_rows AS (
    SELECT N'original' AS side,
           CONVERT(nvarchar(255), [Program]) AS program,
           CONVERT(nvarchar(255), [Project Family]) AS project_family,
           CONVERT(nvarchar(255), [Lane]) AS lane,
           CONVERT(nvarchar(255), [Segment]) AS segment,
           CONVERT(nvarchar(255), [Firm/FO-SS/New]) AS firm_category,
           CONVERT(nvarchar(255), [GLC]) AS glc
    FROM [NORTHGRUM\N35589].[LaborForecastQuarterCompareFinal]
    WHERE [Type] = N'Labor Forecast'
      AND TRY_CONVERT(date, [DateTime_Out]) >= '2026-10-01'
      AND TRY_CONVERT(date, [DateTime_Out]) < '2026-11-01'
      AND [Category] = N'Hours'
    UNION ALL
    SELECT N'dev', CONVERT(nvarchar(255), [Program]),
           CONVERT(nvarchar(255), [Project Family]),
           CONVERT(nvarchar(255), [Lane]), CONVERT(nvarchar(255), [Segment]),
           CONVERT(nvarchar(255), [Firm/FO-SS/New]), CONVERT(nvarchar(255), [GLC])
    FROM [dbo].[LaborForecastQuarterCompareFinal_dev]
    WHERE [Type] = N'Labor Forecast'
      AND TRY_CONVERT(date, [DateTime_Out]) >= '2026-10-01'
      AND TRY_CONVERT(date, [DateTime_Out]) < '2026-11-01'
      AND [Category] = N'Hours'
),
key_counts AS (
    SELECT program, project_family, lane, segment, firm_category, glc,
           SUM(CASE WHEN side = N'original' THEN 1 ELSE 0 END) AS original_rows,
           SUM(CASE WHEN side = N'dev' THEN 1 ELSE 0 END) AS dev_rows
    FROM october_rows
    GROUP BY program, project_family, lane, segment, firm_category, glc
)
SELECT TOP (50) program, project_family, lane, segment, firm_category, glc,
       original_rows, dev_rows, dev_rows - original_rows AS row_difference
FROM key_counts
WHERE original_rows <> dev_rows
ORDER BY ABS(dev_rows - original_rows) DESC, program, glc;
