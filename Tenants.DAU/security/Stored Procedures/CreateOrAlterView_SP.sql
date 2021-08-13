CREATE PROC [security].[CreateOrAlterView_SP]
		@BatchId BIGINT
		, @SchemaName VARCHAR(100)
		, @TableOrViewName VARCHAR(100)
		, @DeploymentIndicator BIT
		, @DebugIndicator BIT
		, @DeployGrantsIndicator BIT
AS
/*
-- =============================================================================
-- Procedure Name       - CreateOrAlterView_SP
-- Author               - Pradeep Srikakolapu, Microsoft
-- Date Created         - 4/10/2021
-- Description          - Generates and creates RLS and CLS scripts for a table 
--
-- Input parameters:
-- @BatchId							- Batch Id generated for this deployment
-- @SchemaName						- Name of the Schema
-- @TableOrViewName					- Name of the table or view
-- @DeploymentIndicator				- Indicator to deploy RLS and CLS scripts or not
-- @DebugIndicator					- Indicator to debug the code or not

--
-- Sample call:
-- EXEC [security].[CreateOrAlterView_SP]
-- @BatchId = 1
-- , @SchemaName = ''
-- , @TableOrViewName = ''
-- , @DeploymentIndicator = 0
-- , @DebugIndicator = 1
-- , @DeployGrantsIndicator = 1
--
-- =============================================================================
-- Revisions:
--
--  Date        Developer   Change Description
--  ----------  ----------  --------------------------------------------------
-- =============================================================================
*/
BEGIN
	
	DECLARE @viewName VARCHAR(200)
	DECLARE @createViewClause VARCHAR(MAX)
	DECLARE @selectClause VARCHAR(MAX)
	DECLARE @columnClause VARCHAR(MAX)
	DECLARE @fromClause VARCHAR(MAX)
	DECLARE @rowFilterClause VARCHAR(MAX)
	DECLARE @ViewSchemaName VARCHAR(MAX)
	DECLARE @FunctionNames VARCHAR(MAX)
	DECLARE @NoOfClsColumnsToDefine INT = 0
	DECLARE @Counter INT = 1
	DECLARE @AppliedOnColumnName VARCHAR(MAX)
	DECLARE @Script VARCHAR(MAX)
	DECLARE @Activity VARCHAR(MAX)
	DECLARE @Text VARCHAR(MAX)
	DECLARE @IsView BIT
	DECLARE @ViewScript VARCHAR(MAX)
	
BEGIN TRY
	
	-- Create view statement. Substrings enclosed in <> will be replaced by actual values
	SET @createViewClause = 'CREATE VIEW <Schema>.<TableName>' + CHAR(13) + 'AS' + CHAR(13)
	
	-- Replacing schema name, table name from createView Clause
	-- Replacing _t with _v from table schema.
	SET @ViewSchemaName = LEFT(@SchemaName, len(@SchemaName) -2) + '_V'
	SELECT @createViewClause = REPLACE(@createViewClause, '<Schema>' , @ViewSchemaName)
	SELECT @createViewClause = REPLACE(@createViewClause, '<TableName>' , @TableOrViewName)

	-- Setting view name
	SET @viewName = @ViewSchemaName + '.' + @TableOrViewName
	-- Generate select statement & schema.table for from clause
	SET @selectClause = 'SELECT '
	SET @fromClause = CHAR(13) + 'FROM ' + @SchemaName + '.' + @TableOrViewName

	-- Get the RLS function names after deploying RLS function
	EXEC security.IterateRls_SP 
	@BatchId = @BatchId
	, @SchemaName = @SchemaName
	, @TableOrViewName = @TableOrViewName
	, @DeploymentIndicator = @DeploymentIndicator
	, @DebugIndicator = @DebugIndicator
	, @FunctionNames = @FunctionNames OUTPUT 

	-- If no RLS functions are configured and applied, @FunctionNames will be null
	IF @FunctionNames IS NOT NULL
	BEGIN
		-- Trimming spaces at the front and end
		SELECT @rowFilterClause = TRIM(@FunctionNames)
		-- If RLS functions are created, then add cross apply
		IF LEN(@rowFilterClause) > 0
		BEGIN
			SET @fromClause = @fromClause + ' CROSS APPLY '
		END

		-- The function names are seperated by a space. Replace ' ' with CROSS APPLY so that 
		-- cross apply is applied between all RLS functions and  the view.
		SELECT @rowFilterClause = REPLACE(@rowFilterClause, ' ' , ' CROSS APPLY ')
	END
	ELSE
	BEGIN
		SET @rowFilterClause = ''
	END

	-- Logging RLS functions with CROSS APPLY
	SET @Activity = 'Row Filter clause for [' + @SchemaName + '].[' + @TableOrViewName + ']'
	EXEC [security].[InsertLog_SP] 
	@BatchId = @BatchId
	, @ActivityName = @Activity
	, @Text = @rowFilterClause
	, @DebugIndicator = @DebugIndicator

	-- Following code is to generate/Construct CLS

	-- check if the object is view or not
	IF EXISTS 
	(
		SELECT 1 FROM SYS.Schemas s 
		INNER JOIN SYS.Views t 
			ON s.SCHEMA_ID = T.SCHEMA_ID AND s.name = @SchemaName AND t.name = @TableOrViewName
	)
		SET @IsView = 1
	ELSE
		SET @IsView = 0

	-- Drop the object if exists
	IF OBJECT_ID(N'tempdb..#ClsToApply') IS NOT NULL
	BEGIN
		DROP TABLE #ClsToApply
	END

	-- Create a temporary table with the list of columns for which the CLS should be applied on
	CREATE TABLE #ClsToApply
	WITH
	(
		DISTRIBUTION = ROUND_ROBIN
	) 
	AS
	SELECT ROW_NUMBER() OVER(ORDER BY ColumnName ASC) AS Row#
	, ColumnName
	, CAST('' AS VARCHAR(8000)) AS Script
	FROM [security].[CLSConfiguration]
	WHERE SchemaName = @SchemaName
	AND TableName = @TableOrViewName
	AND IsEnabled = 1
	GROUP BY ColumnName
	
	SELECT @NoOfClsColumnsToDefine = COUNT(1) 
	FROM #ClsToApply

	-- For each column, generate the CLS
	WHILE  @Counter <= @NoOfClsColumnsToDefine
	BEGIN
		
		SELECT @AppliedOnColumnName	= ColumnName
		FROM #ClsToApply
		WHERE Row# = @Counter
		
		IF @IsView = 0
			EXEC [security].[GenerateClsStatement_SP] 
			@BatchId = @BatchId
			, @SchemaName = @SchemaName
			, @TableName = @TableOrViewName
			, @AppliedOnColumnName = @AppliedOnColumnName
			, @DebugIndicator = @DebugIndicator
			, @Script = @Script OUTPUT
		ELSE
			EXEC security.GenerateClsStatementForViews_SP 
			@BatchId = @BatchId
			, @SchemaName = @SchemaName
			, @ViewName = @TableOrViewName
			, @AppliedOnColumnName = @AppliedOnColumnName
			, @DebugIndicator = @DebugIndicator
			, @Script = @Script OUTPUT

		IF @Script IS NOT NULL
		BEGIN	
			UPDATE #ClsToApply
			SET Script = @Script
			WHERE Row# = @Counter;

		END
		ELSE
		BEGIN
			SET @Activity = 'WARNING, this might be caused due incorrect CLS configuration'
			SET @Text = 'Returned NULL after applying CLS for ' + @SchemaName + '.' + @TableOrViewName + '.' + @AppliedOnColumnName 
			EXEC [security].[InsertLog_SP] 
			@BatchId = @BatchId
			, @ActivityName = @Activity
			, @Text = @Text
			, @DebugIndicator = @DebugIndicator
		END
		SET @counter = @Counter+1
	END

	-- Construct the list of columns from system tables for @Table
	IF @IsView = 0
		SELECT @columnClause = STRING_AGG(CAST(ColumnName AS VARCHAR(MAX)), CHAR(13) + ',') WITHIN GROUP (ORDER BY ColumnOrder ASC)
		FROM 
		(
			SELECT CASE WHEN cta.ColumnName IS NOT NULL THEN 'CASE' + CHAR(13) + cta.Script + CHAR(13) + ' ELSE NULL END AS [' + cta.ColumnName + ']'
			ELSE '[' + c.ColumnName + ']' END AS ColumnName
			, ColumnOrder FROM 
			(
				SELECT col.name AS ColumnName
				, col.column_id AS ColumnOrder
				FROM SYS.TABLES AS tab
				INNER JOIN SYS.SCHEMAS AS sch
					ON tab.schema_id = sch.schema_id 
				INNER JOIN SYS.COLUMNS AS col
					ON tab.object_id = col.object_id		
				WHERE sch.name = @SchemaName AND tab.name = @TableOrViewName
			) c
			LEFT JOIN  #ClsToApply cta
				ON c.ColumnName = cta.ColumnName			
		) ColumnsList
	
	IF @IsView = 1
		SELECT @columnClause = STRING_AGG(CAST(ColumnName AS VARCHAR(MAX)), CHAR(13) + ',') WITHIN GROUP (ORDER BY ColumnOrder ASC)
		FROM 
		(
			SELECT CASE WHEN cta.ColumnName IS NOT NULL THEN 'CASE' + CHAR(13) + cta.Script + CHAR(13) + ' ELSE NULL END AS [' + cta.ColumnName + ']'
			ELSE '[' + c.ColumnName + ']' END AS ColumnName
			, ColumnOrder FROM
			(
				SELECT col.name AS ColumnName
				, col.column_id AS ColumnOrder
				FROM SYS.Views AS tab
				INNER JOIN SYS.SCHEMAS AS sch
					ON tab.schema_id = sch.schema_id 
				INNER JOIN SYS.COLUMNS AS col
					ON tab.object_id = col.object_id		
				WHERE sch.name = @SchemaName AND tab.name = @TableOrViewName
			) c
			LEFT JOIN  #ClsToApply cta
				ON c.ColumnName = cta.ColumnName
		) ColumnsList
		

	-- If view already exists, alter the view
	IF OBJECT_ID(@viewName, 'V') IS NOT NULL
		SELECT @createViewClause = REPLACE(@createViewClause, 'CREATE VIEW' , 'ALTER VIEW')	

	-- Logging @Text	
	SET @ViewScript = @createViewClause + @selectClause + @columnClause + @fromClause + @rowFilterClause

	IF @DeploymentIndicator = 1
	BEGIN

		EXEC (@ViewScript)
		
		SET @Activity = 'Deployed View for [' + @SchemaName + '].[' + @TableOrViewName + ']'
		EXEC [security].[InsertLog_SP] 
		@BatchId = @BatchId
		, @ActivityName = 'View Deployment completed...'
		, @Text = @Activity
		, @DebugIndicator = @DebugIndicator
				
	END
	
	INSERT INTO [security].[GeneratedObjectScripts] (BatchId, SchemaName, TableName, ScriptType, Script)
	VALUES (@BatchId, @SchemaName, @TableOrViewName, 'View', @ViewScript)
	
	SET @Activity = 'Generated View script for [' + @SchemaName + '].[' + @TableOrViewName + ']'	
	EXEC [security].[InsertLog_SP] 
	@BatchId = @BatchId
	, @ActivityName = @Activity
	, @Text = @ViewScript
	, @DebugIndicator = @DebugIndicator

	-- Manage Grants
	IF EXISTS 
	(
		SELECT 1 FROM [security].[AccessToSecuredViewsConfiguration] 
		WHERE SchemaName = @SchemaName
	)
	BEGIN

		-- Drop the object if exists
		IF OBJECT_ID(N'tempdb..#GrantsToApply') IS NOT NULL
		BEGIN
			DROP TABLE #GrantsToApply
		END

		CREATE TABLE #GrantsToApply
		WITH
		(
			DISTRIBUTION = ROUND_ROBIN
		) 
		AS
		SELECT ROW_NUMBER() OVER(ORDER BY GrantStatement ASC) AS Row#
		, CAST (GrantStatement AS VARCHAR(500)) AS GrantStatement
		FROM 
		(
			SELECT GrantType + ' ' + [Grant] + ' ON SCHEMA:: ' + @ViewSchemaName + ' TO [' + AdGroupOrRoleName + ']' AS GrantStatement
			FROM [security].[AccessToSecuredViewsConfiguration]
			WHERE SchemaName = @SchemaName
			AND (TableName = '*' OR TableName IS NULL)

			UNION ALL

			SELECT GrantType + ' ' + [Grant] + ' ON ' + @viewName + ' TO [' + AdGroupOrRoleName + ']' AS GrantStatement
			FROM [security].[AccessToSecuredViewsConfiguration]
			WHERE SchemaName = @SchemaName
			AND TableName = @TableOrViewName
		) Grants
		SET @Counter = 1			

		DECLARE @Query NVARCHAR(MAX), @NoOfGrants INT

		SELECT @NoOfGrants = COUNT(1)
		FROM #GrantsToApply

		SELECT @Text = STRING_AGG (GrantStatement, CHAR(13)) 
		FROM #GrantsToApply 

		SET @Activity = 'Grant Statements for ' + @viewName
		EXEC [security].[InsertLog_SP] 
		@BatchId = @BatchId
		, @ActivityName = @Activity
		, @Text = @Text
		, @DebugIndicator = @DebugIndicator

		IF @DeployGrantsIndicator = 1
		BEGIN

			WHILE @Counter <= @NoOfGrants
			BEGIN				
				SELECT @Query = GrantStatement
				FROM #GrantsToApply
				WHERE Row# = @Counter


				EXEC (@Query)
				SET @Counter = @Counter + 1
								
			END
		END
		INSERT INTO [security].[GeneratedObjectScripts] (BatchId, SchemaName, TableName, ScriptType, Script)
		VALUES (@BatchId, @SchemaName, @TableOrViewName, 'GrantStatements', @Text)
		DROP TABLE #GrantsToApply
	END
END TRY
BEGIN CATCH
    DECLARE @Error VARCHAR(MAX)
	SELECT @Error = CAST(ERROR_SEVERITY() AS VARCHAR) + '/' + CAST(ERROR_STATE() AS VARCHAR) + '/' + ERROR_PROCEDURE() + '/' + ERROR_MESSAGE()

	-- Inserting log entry for error
	-- Should not throw error
	EXEC [security].[InsertLog_SP] 
	@BatchId = @BatchId
	, @ActivityName = 'ERROR_SEVERITY/ERROR_STATE/ERROR_PROCEDURE/ERROR_MESSAGE........'
	, @Text = @Error
	, @DebugIndicator = @DebugIndicator;
END CATCH
END
GO