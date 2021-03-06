CREATE PROC [security].[GenerateClsStatement_SP]
		@BatchId BIGINT
		, @SchemaName VARCHAR(100)
		, @TableName VARCHAR(100)
		, @AppliedOnColumnName VARCHAR(100)
		, @DebugIndicator BIT
		, @Script VARCHAR(MAX) OUTPUT
AS
/*
-- =============================================================================
-- Procedure Name       - GenerateClsStatement_Sp
-- Author               - Pradeep Srikakolapu, Microsoft
-- Date Created         - 4/12/2021
-- Description          - Generate CLS script for a column
-- 
-- Input parameters:
-- @BatchId							- Batch Id generated for this deployment
-- @SchemaName						- Name of the schema
-- @TableName						- Name of the table
-- @AppliedOnColumnName				- Name of the column for which CLS is applied
-- @DebugIndicator					- Indicator to debug the code or not
-- @Script							- CLS script of a column
--
-- Sample call:
-- DECLARE @Script VARCHAR(MAX)
-- EXEC security.GenerateClsStatement_Sp 
-- @BatchId = 1
-- , @SchemaName = 'pradeep'
-- , @TableName = 'cdw'
-- , @AppliedOnColumnName = 'kp_rgn_cd'
-- , @DebugIndicator = 1
-- , @Script = @Script OUTPUT
-- SELECT @Script
--
-- =============================================================================
-- Revisions:
--
--  Date        Developer   Change Description
--  ----------  ----------  --------------------------------------------------
-- =============================================================================
*/
BEGIN

	DECLARE @CaseClause VARCHAR(MAX)
	DECLARE @caseError CHAR(1)
	DECLARE @errorMessage VARCHAR(500)

	BEGIN TRY

		-- check if all mandatory parameters are not empty. If null or empty, throw an error.
		SET @errorMessage= 'One or more input parameters are not null or empty. Schema Name: ' + @SchemaName + '/ Table Name: ' + @TableName + '/ Column Name: ' + @AppliedOnColumnName
		IF (@SchemaName IS NULL OR  LEN(@SchemaName) < 1) OR (@TableName IS NULL OR  LEN(@TableName) < 1) OR (@AppliedOnColumnName IS NULL OR  LEN(@AppliedOnColumnName) < 1) 
			THROW 51000, @errorMessage, 1;

		IF NOT EXISTS (SELECT 1 FROM SYS.Schemas WHERE name = @SchemaName)
		BEGIN
			SET @errorMessage = @SchemaName + ' schema does not exist. Please provide valid schema name';
			THROW 51000, @errorMessage, 1;
		END

		IF NOT EXISTS 
		(
			SELECT 1 FROM SYS.Schemas s 
			INNER JOIN SYS.TABLES t 
				ON s.SCHEMA_ID = T.SCHEMA_ID AND s.name = @SchemaName AND t.name = @TableName
		)
		BEGIN
			SET @errorMessage = 'Table ' + @TableName + ' does not exist in ' + @SchemaName +' schema. Please provide valid table name';
			THROW 51000, @errorMessage, 1;
		END

		IF NOT EXISTS 
		(
			SELECT 1 FROM SYS.Schemas s 
			INNER JOIN SYS.TABLES t 
				ON s.SCHEMA_ID = T.SCHEMA_ID AND s.name = @SchemaName AND t.name = @TableName
			INNER JOIN SYS.COLUMNS AS c
				ON t.object_id = c.object_id AND c.name = @AppliedOnColumnName
		)
		BEGIN
			SET @errorMessage = 'Column ' + @AppliedOnColumnName + ' does not exist in ' + @TableName +' table. Please provide valid column name';
			THROW 51000, @errorMessage, 1;
		END
		SELECT @Script = STRING_AGG(CLS_Security_Filter, CHAR(13))
		FROM
		(
			SELECT CASE
					WHEN s.FilterColumnName IS NULL THEN 'WHEN  IS_MEMBER('''+F.ADGroupOrRoleName+''') =1 THEN ' + '[' + @AppliedOnColumnName + ']'
					WHEN t.name LIKE '%char%' AND s.FilterColumnName IS NOT NULL THEN 'WHEN  IS_MEMBER('''+F.ADGroupOrRoleName+''') =1 and ' + '[' + s.FilterColumnName + ']' + ' =''' +F.FilterValue + ''' THEN ' + '[' + @AppliedOnColumnName + ']'
					WHEN (t.name LIKE '%decimal%' OR t.name LIKE '%numeric%' OR t.name LIKE '%int%') AND s.FilterColumnName IS NOT NULL THEN 'WHEN  IS_MEMBER('''+F.ADGroupOrRoleName+''') =1 and ' + '[' + s.FilterColumnName + ']' + ' =' +F.FilterValue + ' THEN ' + '[' + @AppliedOnColumnName + ']'
					WHEN t.name LIKE '%date%' AND s.FilterColumnName IS NOT NULL THEN 'WHEN  IS_MEMBER('''+F.ADGroupOrRoleName+''') =1 and ' + '[' + s.FilterColumnName + ']' + ' =' +F.FilterValue + ' THEN ' + '[' + @AppliedOnColumnName + ']'				
				ELSE NULL  END AS CLS_Security_Filter 
			FROM [security].[CLSConfiguration] s
				INNER JOIN [security].[FilterConfiguration] F
					ON s.FilterType = F.FilterType AND LOWER(F.SecurityType) = 'column'
				INNER JOIN SYS.TABLES AS tab
					ON s.TableName = tab.name AND tab.NAME = @TableName
				INNER JOIN SYS.SCHEMAS AS sch
					ON tab.schema_id = sch.schema_id AND sch.NAME = @SchemaName
				LEFT JOIN SYS.COLUMNS AS col
					ON tab.object_id = col.object_id AND col.NAME = s.FilterColumnName
				LEFT JOIN SYS.TYPES AS t
					ON col.user_type_id = t.user_type_id
			WHERE s.IsEnabled = 1
			AND s.ColumnName = @AppliedOnColumnName

		) Agg

		IF @caseError = '?'
		BEGIN
			SET @errorMessage = 'None of the CASE clauses matched to generate CLS statement for ' + @AppliedOnColumnName;
			PRINT 'Meeeee';
			THROW 51000, @errorMessage, 1;
		END

		DECLARE @Activity VARCHAR(500)
		SET @Activity = 'Generated CLS statement for [' + @SchemaName + '].[' + @TableName + '].[' + @AppliedOnColumnName + ']'
		EXEC [security].[InsertLog_SP] 
		@BatchId = @BatchId
		, @ActivityName = @Activity
		, @Text = @Script
		, @DebugIndicator = @DebugIndicator

	END TRY
	BEGIN CATCH		
		THROW;
    END CATCH
END
GO