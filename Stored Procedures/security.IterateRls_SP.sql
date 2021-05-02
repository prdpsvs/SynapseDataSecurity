CREATE PROC [security].[IterateRls_SP]
		@BatchId BIGINT
		, @SchemaName VARCHAR(100)
		, @TableOrViewName VARCHAR(100)
		, @DeploymentIndicator BIT
		, @DebugIndicator BIT
		, @FunctionNames VARCHAR(MAX) OUTPUT 
AS
/*
-- =============================================================================
-- Procedure Name       - IterateRls_SP
-- Author               - Pradeep Srikakolapu, Microsoft
-- Date Created         - 4/10/2021
-- Description          - Iterate each column to create RLS function per column 
--
-- Input parameters:
-- @BatchId							- Batch Id generated for this deployment
-- @SchemaName						- Name of the schema
-- @TableOrViewName					- Name of the table or view
-- @DeploymentIndicator				- Indicator to deploy RLS and CLS scripts or not
-- @DebugIndicator					- Indicator to debug the code or not
-- @FunctionNames					- Name of functions scripted delimited with comma
--
-- Sample call:
-- DECLARE @FunctionNames VARCHAR(MAX)
-- EXEC security.IterateRls_SP 
-- @BatchId = 1
-- , @SchemaName = 'pradeep'
-- , @TableOrViewName = 'cdw'
-- , @DeploymentIndicator = 0
-- , @DebugIndicator = 1
-- , @FunctionNames = @FunctionNames OUTPUT
-- SELECT @FunctionNames
--
-- =============================================================================
-- Revisions:
--
--  Date        Developer   Change Description
--  ----------  ----------  --------------------------------------------------
-- =============================================================================
*/

BEGIN
	DECLARE @NoOfRlsFunctionsToDefine INT;	
	DECLARE @ErrorMessage VARCHAR(500)
	DECLARE @Counter INT = 1;	
	DECLARE @ColumnName VARCHAR(100)
	DECLARE @Script VARCHAR(MAX)
	DECLARE @functionNameWithColumn VARCHAR(200)
	DECLARE @IsView BIT
	
BEGIN TRY
	
	IF (@SchemaName IS NULL OR  LEN(@SchemaName) < 1) OR (@TableOrViewName IS NULL OR  LEN(@TableOrViewName) < 1)
	BEGIN		
		SET @ErrorMessage= 'One or more input parameters are not null or empty. Schema Name: ' + @SchemaName + '/ Table Name: ' + @TableOrViewName;
		THROW 51000, @ErrorMessage, 1;
	END

	IF NOT EXISTS (SELECT 1 FROM SYS.Schemas WHERE name = @SchemaName)
	BEGIN
		SET @ErrorMessage = @SchemaName + ' schema does not exist. Please provide valid schema name';
		THROW 51000, @ErrorMessage, 1;
	END

	IF NOT EXISTS 
	(
		SELECT 1 FROM SYS.Schemas s 
		INNER JOIN SYS.TABLES t 
			ON s.SCHEMA_ID = T.SCHEMA_ID AND s.name = @SchemaName AND t.name = @TableOrViewName
	) AND NOT EXISTS
	(
		SELECT 1 FROM SYS.Schemas s 
		INNER JOIN SYS.Views t 
			ON s.SCHEMA_ID = T.SCHEMA_ID AND s.name = @SchemaName AND t.name = @TableOrViewName
	)
	BEGIN
		SET @ErrorMessage = 'Table/View ' + @TableOrViewName + ' does not exist in ' + @SchemaName +' schema. Please provide valid table/view name';
		THROW 51000, @ErrorMessage, 1;
	END

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
	
	IF OBJECT_ID(N'tempdb..#Rls') IS NOT NULL
	BEGIN
		DROP TABLE #Rls
	END

	CREATE TABLE #Rls
	WITH
	(
		DISTRIBUTION = ROUND_ROBIN
	)
	AS
	SELECT ROW_NUMBER() OVER(ORDER BY SchemaName, TableName, RowFilterColumnName ASC) AS Row#
	, SchemaName
	, TableName
	, RowFilterColumnName AS ColumnName
	FROM [security].[RLSConfiguration]
	WHERE SchemaName = @SchemaName
	AND TableName = @TableOrViewName
	GROUP BY SchemaName, TableName, RowFilterColumnName

	SELECT @NoOfRlsFunctionsToDefine = COUNT(1) 
	FROM #Rls

	WHILE @Counter <= @NoOfRlsFunctionsToDefine
	BEGIN
		
		IF @Counter = 1
			SET @FunctionNames = ''

		SELECT @ColumnName	= ColumnName
		FROM #Rls
		WHERE Row# = @Counter

		IF @IsView = 0
		BEGIN
			EXEC [security].[CreateRlsFunction_SP]
			@BatchId = @BatchId
			, @SchemaName = @SchemaName
			, @TableName = @TableOrViewName
			, @ColumnName = @ColumnName
			, @DeploymentIndicator = @DeploymentIndicator
			, @DebugIndicator = @DebugIndicator
			, @Script = @Script OUTPUT
			, @functionNameWithColumn = @functionNameWithColumn OUTPUT
				
			SELECT @FunctionNames = @FunctionNames + ' ' +  @functionNameWithColumn
		END
		
		IF @IsView = 1
		BEGIN
			EXEC security.CreateRlsFunctionForViews_SP 
			@BatchId = @BatchId
			, @SchemaName = @SchemaName
			, @ViewName = @TableOrViewName
			, @ColumnName = @ColumnName
			, @DeploymentIndicator = @DeploymentIndicator 
			, @DebugIndicator = @DebugIndicator
			, @Script = @Script OUTPUT
			, @functionNameWithColumn = @functionNameWithColumn OUTPUT
			
			SELECT @FunctionNames = @FunctionNames + ' ' +  @functionNameWithColumn
		END
		SET @counter = @Counter+1
	END
END TRY
BEGIN CATCH
	THROW;
    END CATCH
END
