CREATE PROC [security].[CreateRlsFunction_SP]
		@BatchId BIGINT
		, @SchemaName VARCHAR(100)
		, @TableName VARCHAR(100)
		, @ColumnName VARCHAR(100)
		, @DeploymentIndicator BIT
		, @DebugIndicator BIT
		, @Script VARCHAR(MAX) OUTPUT
		, @functionNameWithColumn VARCHAR(300) OUTPUT
AS
/*
-- =============================================================================
-- Procedure Name       - CreateRlsFunction_SP
-- Author               - Pradeep Srikakolapu, Microsoft
-- Date Created         - 4/10/2021
-- Description          - Generate and create RLS function script 
--
-- Input parameters:
-- @BatchId							- Batch Id generated for this deployment
-- @SchemaName						- Name of the schema
-- @TableName						- Name of the table
-- @ColumnName						- Input Schema Document Url
-- @DeploymentIndicator				- Indicator to deploy RLS and CLS scripts or not
-- @DebugIndicator					- Indicator to debug the code or not
-- @Script							- DDL script of a function
-- @functionNameWithColumn			- Name of the function with output
--
-- Sample call:
-- DECLARE @Script VARCHAR(MAX), @functionNameWithColumn VARCHAR(200)
-- EXEC security.CreateRlsFunction_SP 
-- @BatchId = 1
-- , @SchemaName = 'pradeep'
-- , @TableName = 'cdw'
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
	SET @ErrorMessage= 'One or more input parameters are not null or empty. Schema Name: ' + @SchemaName + '/ Table Name: ' + @TableName + '/ Column Name: ' + @ColumnName
	IF (@SchemaName IS NULL OR  LEN(@SchemaName) < 1) OR (@TableName IS NULL OR  LEN(@TableName) < 1) OR (@ColumnName IS NULL OR  LEN(@ColumnName) < 1) 
		THROW 51000, @ErrorMessage, 1;

	IF NOT EXISTS (SELECT 1 FROM SYS.Schemas WHERE name = @SchemaName)
	BEGIN
		SET @ErrorMessage = @SchemaName + ' schema does not exist. Please provide valid schema name';
		THROW 51000, @ErrorMessage, 1;
	END

	IF NOT EXISTS 
	(
		SELECT 1 FROM SYS.Schemas s 
		INNER JOIN SYS.TABLES t 
			ON s.SCHEMA_ID = T.SCHEMA_ID AND s.name = @SchemaName AND t.name = @TableName
	)
	BEGIN
		SET @ErrorMessage = 'Table ' + @TableName + ' does not exist in ' + @SchemaName +' schema. Please provide valid table name';
		THROW 51000, @ErrorMessage, 1;
	END

	IF NOT EXISTS 
	(
		SELECT 1 FROM SYS.Schemas s 
		INNER JOIN SYS.TABLES t 
			ON s.SCHEMA_ID = T.SCHEMA_ID AND s.name = @SchemaName AND t.name = @TableName
		INNER JOIN SYS.COLUMNS AS c
			ON t.object_id = c.object_id AND c.name = @ColumnName
	)
	BEGIN
		SET @ErrorMessage = 'Column ' + @ColumnName + ' does not exist in ' + @TableName +' table. Please provide valid column name';
		THROW 51000, @ErrorMessage, 1;
	END

	-- Dynamic SQL statement to drop RLS function if exists.
	SET @dropFunctionStatement = 'IF OBJECT_ID(<fncNameWithQuotes>) IS NOT NULL DROP FUNCTION  <fncName>'
	
	-- Adding Standardization to RLS function naming convention.
	-- @functionName used in drop statement
	SET @functionName = '<Schema>.fn_FilterRows_<TableName>_by_<ColumnName>'
	-- @functionNameWithColumn information is to cross apply view with function.
	SET @functionNameWithColumn = '<Schema>.fn_FilterRows_<TableName>_by_<ColumnName>(<ColumnName>)'
	
	-- Create function statement. Substrings enclosed in <> will be replaced by actual values
	SET @createFunctionClause = 'CREATE FUNCTION <Schema>.fn_FilterRows_<TableName>_by_<ColumnName> (@filter AS <DataType>)' + CHAR(13) + 'RETURNS TABLE' + CHAR(13) + 'WITH SCHEMABINDING' + CHAR(13) + 'AS' + CHAR(13) + 'RETURN' + CHAR(13)
	-- Generic select clause for RLS function
	SET @selectClause = 'SELECT 1 as result' + CHAR(13)

	-- RLS function expects a parameter with data type
	-- Following query constructs for a column(@ColumnName parameter) used as parameter in a RLS function
	SELECT @filterValueType =
	CASE 
		WHEN Data_Type LIKE '%decimal%' THEN Data_Type + '(' + CAST(Numeric_Precision AS VARCHAR(10)) + ',' + CAST(Numeric_Scale AS VARCHAR(10)) + ')'
		WHEN Data_Type LIKE '%numeric%' THEN Data_Type + '(' + CAST(Numeric_Precision AS VARCHAR(10)) + ',' + CAST(Numeric_Scale AS VARCHAR(10)) + ')'
		WHEN Data_Type LIKE '%char%' THEN Data_Type + '(' + CAST(Character_Maximum_Length AS VARCHAR(10)) + ')'
		WHEN Data_Type LIKE '%int%' THEN Data_Type
	END
	FROM INFORMATION_SCHEMA.COLUMNS
	WHERE Table_schema = @SchemaName
	AND Table_Name = @TableName
	AND Column_Name = @ColumnName

	-- Replacing _t with _v from table schema.
	SET @ViewSchemaName = LEFT(@SchemaName, len(@SchemaName) -2) + '_v'

	-- Replacing schema name, table name, column name and data type of the column 
	-- in createFunctionClause, functionName and functionNameWithColumn variables
	SELECT @createFunctionClause = REPLACE(@createFunctionClause, '<Schema>' , @ViewSchemaName)
	SELECT @createFunctionClause = REPLACE(@createFunctionClause, '<TableName>' , @TableName)
	SELECT @createFunctionClause = REPLACE(@createFunctionClause, '<ColumnName>' , @ColumnName)
	SELECT @createFunctionClause = REPLACE(@createFunctionClause, '<DataType>' , @filterValueType)

	SELECT @functionNameWithColumn = REPLACE(@functionNameWithColumn, '<Schema>' , @ViewSchemaName)
	SELECT @functionNameWithColumn = REPLACE(@functionNameWithColumn, '<TableName>' , @TableName)
	SELECT @functionNameWithColumn = REPLACE(@functionNameWithColumn, '<ColumnName>' , @ColumnName)

	SELECT @functionName = REPLACE(@functionName, '<Schema>' , @ViewSchemaName)
	SELECT @functionName = REPLACE(@functionName, '<TableName>' , @TableName)
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
		FROM 
		(	
			SELECT SchemaName, TableName, RowFilterColumnName, FilterType, IsEnabled FROM
			(
				SELECT ROW_NUMBER ( )   
					OVER (PARTITION BY SchemaName, TableName, RowFilterColumnName, FilterType 
					Order By SchemaName, TableName, RowFilterColumnName, FilterType) AS RowNumber
					, SchemaName
					, TableName
					, RowFilterColumnName
					, FilterType
					, IsEnabled
				FROM Security.RlsConfiguration 
			) DistinctRlsConfiguration 
			WHERE RowNumber = 1
		) s
		INNER JOIN [Security].[FilterConfiguration] f
			ON s.FilterType = f.FilterType AND LOWER(F.SecurityType) = 'row'
		INNER JOIN SYS.TABLES AS tab
			on s.TableName = tab.name AND tab.name = @TableName AND s.TableName = @TableName
		INNER JOIN SYS.SCHEMAS AS sch
			on tab.schema_id = sch.schema_id AND sch.name = @SchemaName AND s.SchemaName = @SchemaName
		INNER JOIN SYS.COLUMNS AS col
			on tab.object_id = col.object_id AND col.name = @ColumnName AND s.RowFilterColumnName = @ColumnName
		LEFT JOIN SYS.TYPES AS t
			on col.user_type_id = t.user_type_id
		WHERE s.IsEnabled = 1
	) P

	SET @Script = @createFunctionClause + @selectClause + @whereClause

	-- Logging RLS function script
	DECLARE @Activity VARCHAR(500)
	IF @Script IS NULL
	BEGIN
		SET @Activity = 'Unable to generate script because one or more reasons.....'
		EXEC [security].[InsertLog_SP] 
		@BatchId = @BatchId
		, @ActivityName = @Activity
		, @Text = 'FilterType value in security.RLSConfiguration and security.FilterConfiguration is not matching or check the RowFilterColumnName in security.RLSConfiguration or FilterValue in secruity.FilterConfiguration table'
		, @DebugIndicator = @DebugIndicator;

		SET @Script = 'Script value is null; @whereClause - ' +  @whereClause;
		THROW 50001, @Script, 1;
	END

	
	SET @Activity = 'Generated Rls function for [' + @SchemaName + '].[' + @TableName + '].[' + @ColumnName + ']'
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
	VALUES (@BatchId, @SchemaName, @TableName, 'Function', @Script)
	
END TRY
BEGIN CATCH
	THROW;
    END CATCH
END
GO
