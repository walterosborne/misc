-- Read-only comparison of production and dev tables.
-- Run after both dev tables are populated. No tables are changed.
-- Production tables are in [NORTHGRUM\N35589]; dev tables are in [dbo].
SET NOCOUNT ON;

DECLARE @pairs TABLE (original_name sysname NOT NULL, dev_name sysname NOT NULL);
INSERT INTO @pairs (original_name, dev_name) VALUES
    (N'LaborForecastQuarterCompareFinal', N'LaborForecastQuarterCompareFinal_dev'),
    (N'HeadcountVSActuals', N'HeadcountVSActuals_dev');

DECLARE @original_schema sysname = N'NORTHGRUM\N35589';
DECLARE @dev_schema sysname = N'dbo';
DECLARE @original sysname, @dev sysname, @original_id int, @dev_id int;
DECLARE @columns nvarchar(max), @sql nvarchar(max);
DECLARE @original_rows bigint, @dev_rows bigint, @original_only bigint, @dev_only bigint;

DECLARE pair_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT original_name, dev_name FROM @pairs;
OPEN pair_cursor;
FETCH NEXT FROM pair_cursor INTO @original, @dev;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @original_id = OBJECT_ID(QUOTENAME(@original_schema) + N'.' + QUOTENAME(@original), N'U');
    SET @dev_id = OBJECT_ID(QUOTENAME(@dev_schema) + N'.' + QUOTENAME(@dev), N'U');
    IF @original_id IS NULL OR @dev_id IS NULL
    BEGIN
        SELECT @original AS original_table, @dev AS dev_table,
               CASE WHEN @original_id IS NULL THEN 'Missing original table' ELSE 'Missing dev table' END AS issue;
        FETCH NEXT FROM pair_cursor INTO @original, @dev;
        CONTINUE;
    END;

    -- Schema differences, including type/length, appear before the data results.
    SELECT @original AS original_table, @dev AS dev_table,
           COALESCE(o.name, d.name) AS column_name,
           CASE WHEN o.name IS NULL THEN 'dev only'
                WHEN d.name IS NULL THEN 'original only'
                ELSE 'different type or length' END AS issue,
           TYPE_NAME(o.user_type_id) AS original_type, o.max_length AS original_max_length,
           TYPE_NAME(d.user_type_id) AS dev_type, d.max_length AS dev_max_length
    FROM (SELECT * FROM sys.columns WHERE object_id = @original_id) AS o
    FULL OUTER JOIN (SELECT * FROM sys.columns WHERE object_id = @dev_id) AS d
      ON d.name = o.name
    WHERE o.name IS NULL OR d.name IS NULL
       OR o.system_type_id <> d.system_type_id
       OR o.max_length <> d.max_length
       OR o.precision <> d.precision OR o.scale <> d.scale
    ORDER BY column_name;

    -- Compare common business columns. Run-specific metadata is intentionally excluded.
    SELECT @columns = STRING_AGG(CONVERT(nvarchar(max), QUOTENAME(o.name)), N', ')
                       WITHIN GROUP (ORDER BY o.column_id)
    FROM sys.columns AS o
    JOIN sys.columns AS d ON d.object_id = @dev_id AND d.name = o.name
    WHERE o.object_id = @original_id
      AND o.name NOT IN (N'TimeStamp', N'Concat_File Name & Last Time Updated')
      AND TYPE_NAME(o.user_type_id) NOT IN
          (N'text', N'ntext', N'image', N'xml', N'geometry', N'geography')
      AND TYPE_NAME(d.user_type_id) NOT IN
          (N'text', N'ntext', N'image', N'xml', N'geometry', N'geography');

    IF @columns IS NULL
    BEGIN
        SELECT @original AS original_table, @dev AS dev_table, 'No comparable columns' AS issue;
        FETCH NEXT FROM pair_cursor INTO @original, @dev;
        CONTINUE;
    END;

    SET @sql = N'
SELECT @original_rows = COUNT_BIG(*) FROM ' + QUOTENAME(@original_schema) + N'.' + QUOTENAME(@original) + N';
SELECT @dev_rows = COUNT_BIG(*) FROM ' + QUOTENAME(@dev_schema) + N'.' + QUOTENAME(@dev) + N';
SELECT @original_only = COUNT_BIG(*) FROM (
    SELECT ' + @columns + N' FROM ' + QUOTENAME(@original_schema) + N'.' + QUOTENAME(@original) + N'
    EXCEPT
    SELECT ' + @columns + N' FROM ' + QUOTENAME(@dev_schema) + N'.' + QUOTENAME(@dev) + N'
) AS x;
SELECT @dev_only = COUNT_BIG(*) FROM (
    SELECT ' + @columns + N' FROM ' + QUOTENAME(@dev_schema) + N'.' + QUOTENAME(@dev) + N'
    EXCEPT
    SELECT ' + @columns + N' FROM ' + QUOTENAME(@original_schema) + N'.' + QUOTENAME(@original) + N'
) AS x;';
    EXEC sys.sp_executesql @sql,
        N'@original_rows bigint OUTPUT, @dev_rows bigint OUTPUT,
          @original_only bigint OUTPUT, @dev_only bigint OUTPUT',
        @original_rows OUTPUT, @dev_rows OUTPUT,
        @original_only OUTPUT, @dev_only OUTPUT;

    SELECT @original AS original_table, @dev AS dev_table,
           @original_rows AS original_rows, @dev_rows AS dev_rows,
           @original_only AS distinct_rows_only_in_original,
           @dev_only AS distinct_rows_only_in_dev,
           CASE WHEN @original_rows = @dev_rows
                     AND @original_only = 0 AND @dev_only = 0
                THEN 'MATCH on compared columns' ELSE 'DIFFERENT' END AS result;

    -- Up to 20 example rows from each side when data differs.
    IF @original_only > 0 OR @dev_only > 0
    BEGIN
        SET @sql = N'
SELECT TOP (20) ' + QUOTENAME(@original,'''') + N' AS source_table, x.*
FROM (SELECT ' + @columns + N' FROM ' + QUOTENAME(@original_schema) + N'.' + QUOTENAME(@original) + N'
      EXCEPT SELECT ' + @columns + N' FROM ' + QUOTENAME(@dev_schema) + N'.' + QUOTENAME(@dev) + N') AS x;
SELECT TOP (20) ' + QUOTENAME(@dev,'''') + N' AS source_table, x.*
FROM (SELECT ' + @columns + N' FROM ' + QUOTENAME(@dev_schema) + N'.' + QUOTENAME(@dev) + N'
      EXCEPT SELECT ' + @columns + N' FROM ' + QUOTENAME(@original_schema) + N'.' + QUOTENAME(@original) + N') AS x;';
        EXEC sys.sp_executesql @sql;
    END;
    FETCH NEXT FROM pair_cursor INTO @original, @dev;
END;
CLOSE pair_cursor;
DEALLOCATE pair_cursor;

-- EXCEPT compares distinct rows. Row counts also reveal total-count differences,
-- but offsetting duplicate counts require a separate key-level investigation.
