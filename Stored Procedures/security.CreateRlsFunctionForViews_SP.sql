-- For Row Level Security, each row filter will need a new function
-- For Column level security, create a view
CREATE PROC [security].[CreateRlsFunctionForViews_SP]
		@BatchId BIGINT
		, @SchemaName VARCHAR(100)
		, @ViewName VARCHAR(100)
		, @ColumnName VARCHAR(100)
		, @DeploymentIndicator BIT
		, @DebugIndicator BIT
		, @Script VARCHAR(MAX) OUTPUT
		, @functionNameWithColumn VARCHAR(300) OUTPUT
AS
/*
-- =============================================================================
-- Procedure Name       - CreateRlsFunctionForViews_SP
-- Author               - Pradeep Srikakolapu, Microsoft
-- Date Created         - 4/10/2021
-- Description          - Generate and create RLS function script for views
--
-- Input parameters:
-- @BatchId							- Batch Id generated for this deployment
-- @SchemaName						- Name of the schema
-- @ViewName						- Name of the table
-- @ColumnName						- Input Schema Document Url
-- @DeploymentIndicator				- Indicator to deploy RLS and CLS scripts or not
-- @DebugIndicator					- Indicator to debug the code or not
-- @Script							- DDL script of a function
-- @functionNameWithColumn			- Name of the function with output
--
-- Sample call:
-- DECLARE @Script VARCHAR(MAX), @functionNameWithColumn VARCHAR(200)
-- EXEC security.CreateRlsFunctionForViews_SP 
-- @BatchId = 1
-- , @SchemaName = 'pradeep'
-- , @ViewName = 'cdw'
-- , @ColumnName = 'kp_rgn_cd'
-- , @DeploymentIndicator = 0 
-- , @DebugIndicator = 1
-- , @Script = @Script OUTPUT
-- , @functionNameWithColumn = @functionNameWithColumn OUTPUT
-- SELECT @Script, @functionNameWithColumn
--
-- =============================================================================
-- Revisions:
--
--  Date        Developer   Change Description
--  ----------  ----------  --------------------------------------------------
-- =============================================================================
*/
BEGIN

	DECLARE @filterValueType VARCHAR(50)
	DECLARE @createFunctionClause VARCHAR(1000)
	DECLARE @selectClause VARCHAR(20)
	DECLARE @whereClause VARCHAR(MAX)
	DECLARE @functionName VARCHAR(100)
	DECLARE @ErrorMessage VARCHAR(500)
	DECLARE @dropFunctionStatement NVARCHAR(MAX)
	DECLARE @ViewSchemaName VARCHAR(100)
BEGIN TRY

	-- check if all mandatory parameters are not empty. If null or empty, throw an error.
	SET @ErrorMessage= 'One or more input parameters are not null or empty. Schema Name: ' + @SchemaName + '/ View Name: ' + @ViewName + '/ Column Name: ' + @ColumnName
	IF (@SchemaName IS NULL OR  LEN(@SchemaName) < 1) OR (@ViewName IS NULL OR  LEN(@ViewName) < 1) OR (@ColumnName IS NULL OR  LEN(@ColumnName) < 1) 
		THROW 51000, @ErrorMessage, 1;

	IF NOT EXISTS (SELECT 1 FROM SYS.Schemas WHERE name = @SchemaName)
	BEGIN
		SET @ErrorMessage = @SchemaName + ' schema does not exist. Please provide valid schema name';
		THROW 51000, @ErrorMessage, 1;
	END

	IF NOT EXISTS 
	(
		SELECT 1 FROM SYS.Schemas s 
		INNER JOIN SYS.Views v 
			ON s.SCHEMA_ID = v.SCHEMA_ID AND s.name = @SchemaName AND v.name = @ViewName
	)
	BEGIN
		SET @ErrorMessage = 'View ' + @ViewName + ' does not exist in ' + @SchemaName +' schema. Please provide valid view name';
		THROW 51000, @ErrorMessage, 1;
	END

	IF NOT EXISTS 
	(
		SELECT 1 FROM SYS.Schemas s 
		INNER JOIN SYS.Views v 
			ON s.SCHEMA_ID = v.SCHEMA_ID AND s.name = @SchemaName AND v.name = @ViewName
		INNER JOIN SYS.COLUMNS AS c
			ON v.object_id = c.object_id AND c.name = @ColumnName
	)
	BEGIN
		SET @ErrorMessage = 'Column ' + @ColumnName + ' does not exist in ' + @ViewName +' view. Please provide valid column name';
		THROW 51000, @ErrorMessage, 1;
	END

	-- Dynamic SQL statement to drop RLS function if exists.
	SET @dropFunctionStatement = 'IF OBJECT_ID(<fncNameWithQuotes>) IS NOT NULL DROP FUNCTION  <fncName>'
	
	-- Adding Standardization to RLS function naming convention.
	-- @functionName used in drop statement
	SET @functionName = '<Schema>.fn_FilterRows_<ViewName>_by_<ColumnName>'
	-- @functionNameWithColumn information is to cross apply view with function.
	SET @functionNameWithColumn = '<Schema>.fn_FilterRows_<ViewName>_by_<ColumnName>(<ColumnName>)'
	
	-- Create function statement. Substrings enclosed in <> will be replaced by actual values
	SET @createFunctionClause = 'CREATE FUNCTION <Schema>.fn_FilterRows_<ViewName>_by_<ColumnName> (@filter AS <DataType>)' + CHAR(13) + 'RETURNS TABLE' + CHAR(13) + 'WITH SCHEMABINDING' + CHAR(13) + 'AS' + CHAR(13) + 'RETURN' + CHAR(13)
	-- Generic select clause for RLS function
	SET @selectClause = 'SELECT 1 as result' + CHAR(13)

	-- RLS function expects a parameter with data type
	-- Following query constructs for a column(@ColumnName parameter) used as parameter in a RLS function
	SELECT @filterValueType =
		CASE 
			WHEN t.name LIKE '%decimal%' THEN t.name + '(' + CAST(col.precision AS VARCHAR(10)) + ',' + CAST(col.scale AS VARCHAR(10)) + ')'
			WHEN t.name LIKE '%numeric%' THEN t.name + '(' + CAST(col.precision AS VARCHAR(10)) + ',' + CAST(col.scale AS VARCHAR(10)) + ')'
			WHEN t.name LIKE '%char%' THEN t.name + '(' + CAST(col.max_length AS VARCHAR(10)) + ')'
			WHEN t.name LIKE '%int%' THEN t.name
		END 
	FROM SYS.Views AS tab
		INNER JOIN SYS.SCHEMAS AS sch
				ON tab.schema_id = sch.schema_id AND sch.name = @SchemaName AND tab.name = @ViewName
		INNER JOIN SYS.COLUMNS AS col
			ON tab.object_id = col.object_id AND col.name = @ColumnName
		LEFT JOIN SYS.TYPES AS t
			ON col.user_type_id = t.user_type_id

	-- Replacing _t with _v from table schema.
	SET @ViewSchemaName = LEFT(@SchemaName, len(@SchemaName) -2) + '_V'

	-- Replacing schema name, table name, column name and data type of the column 
	-- in createFunctionClause, functionName and functionNameWithColumn variables
	SELECT @createFunctionClause = REPLACE(@createFunctionClause, '<Schema>' , @ViewSchemaName)
	SELECT @createFunctionClause = REPLACE(@createFunctionClause, '<ViewName>' , @ViewName)
	SELECT @createFunctionClause = REPLACE(@createFunctionClause, '<ColumnName>' , @ColumnName)
	SELECT @createFunctionClause = REPLACE(@createFunctionClause, '<DataType>' , @filterValueType)

	SELECT @functionNameWithColumn = REPLACE(@functionNameWithColumn, '<Schema>' , @ViewSchemaName)
	SELECT @functionNameWithColumn = REPLACE(@functionNameWithColumn, '<ViewName>' , @ViewName)
	SELECT @functionNameWithColumn = REPLACE(@functionNameWithColumn, '<ColumnName>' , @ColumnName)

	SELECT @functionName = REPLACE(@functionName, '<Schema>' , @ViewSchemaName)
	SELECT @functionName = REPLACE(@functionName, '<ViewName>' , @ViewName)
	SELECT @functionName = REPLACE(@functionName, '<ColumnName>' , @ColumnName)

	-- Replacing function name in dropFunctionStatement
	SELECT @dropFunctionStatement = REPLACE(@dropFunctionStatement, '<fncNameWithQuotes>', '''' + @functionName + '''')
	SELECT @dropFunctionStatement = REPLACE(@dropFunctionStatement, '<fncName>', @functionName)

	-- Following query constructs for a column(@ColumnName parameter) used as parameter in a RLS function
	SELECT @whereClause = 'WHERE ' + CHAR(13) + STRING_AGG(RLS_Security_Filter, +char(13) + 'OR' + char(13)) FROM 
	(
		SELECT CASE 
				WHEN f.FilterValue IS NULL AND t.name LIKE '%char%' THEN '(IS_MEMBER('''+ADGroupOrRoleName+''') = 1)'
				WHEN f.FilterValue IS NULL AND t.name LIKE '%decimal%' THEN '(IS_MEMBER('''+ADGroupOrRoleName+''') = 1)'
				WHEN f.FilterValue IS NULL AND t.name LIKE '%numeric%' THEN '(IS_MEMBER('''+ADGroupOrRoleName+''') = 1)'
				WHEN f.FilterValue IS NULL AND t.name LIKE '%int%' THEN '(IS_MEMBER('''+ADGroupOrRoleName+''') = 1)'
				WHEN f.FilterValue IS NOT NULL AND t.name LIKE '%char%' THEN '(IS_MEMBER('''+ADGroupOrRoleName+''') = 1 and @filter = '''+f.FilterValue+''')'
				WHEN f.FilterValue IS NOT NULL AND t.name LIKE '%decimal%' THEN '(IS_MEMBER('''+ADGroupOrRoleName+''') = 1 and @filter = '+f.FilterValue+')'
				WHEN f.FilterValue IS NOT NULL AND t.name LIKE '%numeric%' THEN '(IS_MEMBER('''+ADGroupOrRoleName+''') = 1 and @filter = '+f.FilterValue+')'
				WHEN f.FilterValue IS NOT NULL AND t.name LIKE '%int%' THEN '(IS_MEMBER('''+ADGroupOrRoleName+''') = 1 and @filter = '+f.FilterValue+')'
		END AS RLS_Security_Filter 
		from [security].RLSConfiguration s
			INNER JOIN [Security].[FilterConfiguration] f
				ON s.FilterType = f.FilterType AND LOWER(F.SecurityType) = 'row'
			INNER JOIN SYS.Views AS tab
				on s.TableName = tab.name AND tab.name = @ViewName
			INNER JOIN SYS.SCHEMAS AS sch
				on tab.schema_id = sch.schema_id AND sch.name = @SchemaName
			INNER JOIN SYS.COLUMNS AS col
				on tab.object_id = col.object_id AND col.name = @ColumnName
			LEFT JOIN SYS.TYPES AS t
				on col.user_type_id = t.user_type_id
		WHERE s.RowFilterColumnName = @ColumnName
		AND s.IsEnabled = 1
	) P

	SET @Script = @createFunctionClause + @selectClause + @whereClause

	-- Logging RLS function script
	DECLARE @Activity VARCHAR(500)
	SET @Activity = 'Generated Rls function for [' + @SchemaName + '].[' + @ViewName + '].[' + @ColumnName + ']'
	EXEC [security].[InsertLog_SP] 
	@BatchId = @BatchId
	, @ActivityName = @Activity
	, @Text = @Script
	, @DebugIndicator = @DebugIndicator
	
	-- Deploy RLS function if Deployment Indicator is 1
	IF @DeploymentIndicator = 1
	BEGIN

		EXEC (@dropFunctionStatement)	
		EXEC (@Script)
	END
	
	INSERT INTO [security].[GeneratedObjectScripts] (BatchId, SchemaName, TableName, ScriptType, Script)
	VALUES (@BatchId, @SchemaName, @ViewName, 'View', @Script)
	
END TRY
BEGIN CATCH
	THROW;
    END CATCH
END
GO
