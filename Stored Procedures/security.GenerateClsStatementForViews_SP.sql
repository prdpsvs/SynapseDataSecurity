CREATE PROC [security].[GenerateClsStatementForViews_SP]
		@BatchId BIGINT
		, @SchemaName VARCHAR(100)
		, @ViewName VARCHAR(100)
		, @AppliedOnColumnName VARCHAR(100)
		, @DebugIndicator BIT
		, @Script VARCHAR(MAX) OUTPUT
AS
/*
-- =============================================================================
-- Procedure Name       - GenerateClsStatementForViews_SP
-- Author               - Pradeep Srikakolapu, Microsoft
-- Date Created         - 4/12/2021
-- Description          - Generate CLS script for a column
-- 
-- Input parameters:
-- @BatchId							- Batch Id generated for this deployment
-- @SchemaName						- Name of the schema
-- @ViewName						- Name of the view
-- @AppliedOnColumnName				- Name of the column for which CLS is applied
-- @DebugIndicator					- Indicator to debug the code or not
-- @Script							- CLS script of a column
--
-- Sample call:
-- DECLARE @Script VARCHAR(MAX)
-- EXEC security.GenerateClsStatementForViews_SP 
-- @BatchId = 1
-- , @SchemaName = 'pradeep'
-- , @ViewName = 'cdw'
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
		SET @errorMessage= 'One or more input parameters are not null or empty. Schema Name: ' + @SchemaName + '/ View Name: ' + @ViewName + '/ Column Name: ' + @AppliedOnColumnName
		IF (@SchemaName IS NULL OR  LEN(@SchemaName) < 1) OR (@ViewName IS NULL OR  LEN(@ViewName) < 1) OR (@AppliedOnColumnName IS NULL OR  LEN(@AppliedOnColumnName) < 1) 
			THROW 51000, @errorMessage, 1;

		IF NOT EXISTS (SELECT 1 FROM SYS.Schemas WHERE name = @SchemaName)
		BEGIN
			SET @errorMessage = @SchemaName + ' schema does not exist. Please provide valid schema name';
			THROW 51000, @errorMessage, 1;
		END

		IF NOT EXISTS 
		(
			SELECT 1 FROM SYS.Schemas s 
			INNER JOIN SYS.Views t 
				ON s.SCHEMA_ID = T.SCHEMA_ID AND s.name = @SchemaName AND t.name = @ViewName
		)
		BEGIN
			SET @errorMessage = 'View ' + @ViewName + ' does not exist in ' + @SchemaName +' schema. Please provide valid view name';
			THROW 51000, @errorMessage, 1;
		END

		IF NOT EXISTS 
		(
			SELECT 1 FROM SYS.Schemas s 
			INNER JOIN SYS.Views t 
				ON s.SCHEMA_ID = T.SCHEMA_ID AND s.name = @SchemaName AND t.name = @ViewName
			INNER JOIN SYS.COLUMNS AS c
				ON t.object_id = c.object_id AND c.name = @AppliedOnColumnName
		)
		BEGIN
			SET @errorMessage = 'Column ' + @AppliedOnColumnName + ' does not exist in ' + @ViewName +' view. Please provide valid column name';
			THROW 51000, @errorMessage, 1;
		END
		SELECT @Script = STRING_AGG(CLS_Security_Filter, CHAR(13))
		FROM
		(
			SELECT CASE 
					WHEN t.name LIKE '%char%' AND s.FilterColumnName IS NOT NULL THEN 'WHEN  IS_MEMBER('''+F.ADGroupOrRoleName+''') =1 and ' + s.FilterColumnName + ' =''' +F.FilterValue + ''' THEN ' + @AppliedOnColumnName
					WHEN t.name LIKE '%char%' AND s.FilterColumnName IS NULL THEN 'WHEN  IS_MEMBER('''+F.ADGroupOrRoleName+''') =1 THEN ' + @AppliedOnColumnName
					WHEN (t.name LIKE '%decimal%' OR t.name LIKE '%numeric%' OR t.name LIKE '%int%') AND s.FilterColumnName IS NOT NULL THEN 'WHEN  IS_MEMBER('''+F.ADGroupOrRoleName+''') =1 and ' + s.FilterColumnName + ' =' +F.FilterValue + ' THEN ' + @AppliedOnColumnName
					WHEN (t.name LIKE '%decimal%' OR t.name LIKE '%numeric%' OR t.name LIKE '%int%') AND s.FilterColumnName IS NULL THEN 'WHEN  IS_MEMBER('''+F.ADGroupOrRoleName+''') =1 THEN ' + @AppliedOnColumnName
					WHEN t.name LIKE '%date%' AND s.FilterColumnName IS NULL THEN 'WHEN  IS_MEMBER('''+F.ADGroupOrRoleName+''') =1 THEN ' + @AppliedOnColumnName
					WHEN t.name LIKE '%date%' AND s.FilterColumnName IS NOT NULL THEN 'WHEN  IS_MEMBER('''+F.ADGroupOrRoleName+''') =1 and ' + s.FilterColumnName + ' =' +F.FilterValue + ' THEN ' + @AppliedOnColumnName				
				ELSE NULL  END AS CLS_Security_Filter 
			FROM [security].[CLSConfiguration] s
				INNER JOIN [security].[FilterConfiguration] F
					ON s.FilterType = F.FilterType AND LOWER(F.SecurityType) = 'column'
				INNER JOIN SYS.Views AS tab
					ON s.TableName = tab.name AND tab.NAME = @ViewName
				INNER JOIN SYS.SCHEMAS AS sch
					ON tab.schema_id = sch.schema_id AND sch.NAME = @SchemaName
				INNER JOIN SYS.COLUMNS AS col
					ON tab.object_id = col.object_id AND col.NAME = @AppliedOnColumnName
				INNER JOIN SYS.TYPES AS t
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
		SET @Activity = 'Generated CLS statement for [' + @SchemaName + '].[' + @ViewName + '].[' + @AppliedOnColumnName + ']'
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