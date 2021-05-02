CREATE PROC [security].[OrchestrateRlsAndCls_SP]
		@DeploymentStartDatetimeInUTC DATETIME
		, @TableList VARCHAR(MAX)
		, @DeploymentIndicator BIT
		, @DebugIndicator BIT
		, @GenerateReportIndicator BIT
		, @DeployGrantsIndicator BIT
		, @DeploymentBatchID BIGINT OUTPUT
AS
/*
-- =============================================================================
-- Procedure Name       - OrchestrateRlsAndCls_SP
-- Author               - Pradeep Srikakolapu, Microsoft
-- Date Created         - 4/9/2021
-- Description          - Orchestrates RLS and CLS
--
-- Input parameters:
-- @DeploymentStartDatetimeInUTC	- Start datetime of the deployment in UTC
-- @TableList						- Supply List of tables with schema seperated by ';' delimiter
--									  to apply RLS and CLS. Example: 'schema.table1;schema.table2'
--									  if the value is empty, RLS and CLS will be applied on tables
--									  in security.RlsConfiguration and security.ClsConfiguration
--									  tables.
-- @GenerateReportIndicator         - Supply indicator to generate report
-- @DeploymentIndicator				- Indicator to deploy RLS and CLS scripts or not
-- @DebugIndicator					- Indicator to debug the code or not

--
-- Sample call:
-- DECLARE @BatchId BIGINT
-- EXEC [security].[OrchestrateRlsAndCls_SP]
--		@DeploymentStartDatetimeInUTC = ''
--		, @TableList = 'schema.table1;schema.table2'
--		, @DeploymentIndicator = 1
--		, @DebugIndicator = 1
--		, @GenerateReportIndicator = 1
--		, @DeployGrantsIndicator = 1
--		, @DeploymentBatchID = @BatchId OUTPUT
--	SELECT @BatchId
--
-- =============================================================================
-- Revisions:
--
--  Date        Developer   Change Description
--  ----------  ----------  --------------------------------------------------
-- =============================================================================
*/
BEGIN
BEGIN TRY

	DECLARE @Date DATETIME
	SET @Date = GETUTCDATE()
	-- Generating Batch Id for each deployment
	SELECT @DeploymentBatchID =
		DATEPART(second, @Date) +
        DATEPART(minute, @Date) * 100 +
        DATEPART(hour, @Date) * 10000 +
        DATEPART(day, @Date) * 1000000 +
        DATEPART(month, @Date) * 100000000 +
        DATEPART(year, @Date) * 10000000000

	EXEC [security].[InsertLog_SP] 
		@BatchId = @DeploymentBatchID
		, @ActivityName = 'Generated Batch Id........'
		, @Text = @DeploymentBatchID
		, @DebugIndicator = @DebugIndicator

	-- Drop of the temp table if exists
	IF OBJECT_ID(N'tempdb..#tableList') IS NOT NULL
	BEGIN
		DROP TABLE #tableList
	END

	-- Check if table list is empty or not. If not empty,
	-- refresh the RLS and CLS only for tables listed in @TableList variable
	IF @TableList IS NOT NULL AND LEN(@TableList) > 0
	BEGIN
	
		-- Create temp table which contains list of tables to apply RLS and CLS
		CREATE TABLE #tableList
		WITH ( DISTRIBUTION = ROUND_ROBIN )
		AS
		SELECT ROW_NUMBER() OVER (ORDER BY SchemaName ASC, TableName ASC) As Row#
		, SchemaName
		, TableName
		, NULL AS IsProcessed
		FROM
		(
			SELECT CAST(SUBSTRING(TRIM(VALUE), 1, CHARINDEX('.',TRIM(VALUE))- 1) AS VARCHAR(100)) AS SchemaName
			, CAST(SUBSTRING(TRIM(VALUE), (CHARINDEX('.',TRIM(VALUE))+1), LEN(TRIM(VALUE))) AS VARCHAR(100)) AS TableName
			FROM STRING_SPLIT(@TableList, ';')
		) TableList
		
	END
	ELSE
	BEGIN

		-- create a table list to refresh RLS and CLS for tables since @DeploymentStartDatetimeInUTC
		-- but for tables in [security].[ViewsNotRequired] table.
		CREATE TABLE #tableList
		WITH ( DISTRIBUTION = ROUND_ROBIN )
		AS
		SELECT ROW_NUMBER() OVER (ORDER BY SchemaName ASC, TableName ASC) As Row#
		, SchemaName
		, TableName
		, NULL AS IsProcessed
		FROM
		(
			SELECT CAST(S.NAME AS VARCHAR(100)) AS SchemaName, CAST(T.NAME AS VARCHAR(100)) AS TableName FROM
			SYS.TABLES T
			INNER JOIN SYS.SCHEMAS S ON T.SCHEMA_ID = S.SCHEMA_ID
			WHERE T.create_date >= @DeploymentStartDatetimeInUTC 
			OR (T.create_date <= @DeploymentStartDatetimeInUTC AND @DeploymentStartDatetimeInUTC < T.modify_date)
				EXCEPT 
			SELECT DISTINCT SchemaName, TableName FROM 
			(
				SELECT V.SchemaName AS SchemaName, T.NAME AS TableName FROM
				[security].[ViewsNotRequired] V
				INNER JOIN SYS.SCHEMAS S ON S.NAME = V.SchemaName
				INNER JOIN SYS.TABLES T ON S.SCHEMA_ID = T.SCHEMA_ID
				WHERE V.TableName = '*'
					UNION ALL
				SELECT SchemaName, TableName FROM
				[security].[ViewsNotRequired]
				WHERE TableName <> '*'
			) DistinctTableList
			
		) TableList
		
		SELECT @TableList  = STRING_AGG(SchemaName + '.' + TableName, ';')
		FROM #tableList

	END

	-- Inserting log entry
	EXEC [security].[InsertLog_SP] 
	@BatchId = @DeploymentBatchID
	, @ActivityName = 'Created temp table to hold table and schema name and apply RLS and CLS........'
	, @Text = @TableList
	, @DebugIndicator = @DebugIndicator

	DECLARE @NoOfTables INT
	SELECT @NoOfTables = COUNT(1) 
	FROM #tableList

	-- Insert a log entry if no DDL changes were made since @DeploymentStartDatetimeInUTC
	IF @NoOfTables = 0
	BEGIN
		EXEC [security].[InsertLog_SP] 
		@BatchId = @DeploymentBatchID
		, @ActivityName = 'No of tables found........'
		, @Text = @NoOfTables
		, @DebugIndicator = @DebugIndicator
	END
	ELSE
	-- Iterate through tables to apply CLS and RLS 
	BEGIN
		DECLARE @Counter INT = 1
		DECLARE @TableName VARCHAR(100)
		DECLARE @SchemaName VARCHAR(100)
		WHILE @Counter <= @NoOfTables
		BEGIN	
			SELECT @SchemaName = SchemaName
			, @TableName = TableName
			FROM #tableList
			WHERE Row# = @Counter

			-- Creates a new view or refresh view definition with RLS and CLS
			-- If the deployment indicator is 1, then the views are deployed

			IF RIGHT(LOWER(@SchemaName), 2) <> '_t'
			BEGIN
				UPDATE #tableList
				SET IsProcessed = 0
				WHERE Row# = @Counter
				
				DECLARE @Text VARCHAR(1000)
				SET @Text = @SchemaName + '.' + @TableName

				EXEC [security].[InsertLog_SP] 
				@BatchId = @DeploymentBatchID
				, @ActivityName = 'The schema is not ending with _t/_T'
				, @Text = @Text
				, @DebugIndicator = @DebugIndicator;
			END
			ELSE
			BEGIN
				EXEC [security].[CreateOrAlterView_SP]
				@BatchId = @DeploymentBatchID
				, @SchemaName = @SchemaName
				, @TableOrViewName = @TableName
				, @DeploymentIndicator = @DeploymentIndicator
				, @DebugIndicator = @DebugIndicator
				, @DeployGrantsIndicator = @DeployGrantsIndicator

				DECLARE @TableNameWithSchema VARCHAR(200)
				SET @TableNameWithSchema = '['+ @SchemaName + '].[' + @TableName + ']'

				UPDATE #tableList
				SET IsProcessed = 1
				WHERE Row# = @Counter				
			END
			SET @Counter = @Counter +1
		END
	END
END TRY
BEGIN CATCH
    DECLARE @Error VARCHAR(MAX)
	SELECT @Error = CAST(ERROR_SEVERITY() AS VARCHAR) + '/' + CAST(ERROR_STATE() AS VARCHAR) + '/' + ERROR_PROCEDURE() + '/' + ERROR_MESSAGE()

	-- Inserting log entry for error
	EXEC [security].[InsertLog_SP] 
	@BatchId = @DeploymentBatchID
	, @ActivityName = 'ERROR_SEVERITY/ERROR_STATE/ERROR_PROCEDURE/ERROR_MESSAGE........'
	, @Text = @Error
	, @DebugIndicator = @DebugIndicator;

	-- Cleanup and log table entries for which RLS and CLS applied and not applied
	IF OBJECT_ID(N'tempdb..#tableList') IS NOT NULL
	BEGIN
		DECLARE @ToBeProcessed INT
		SELECT @ToBeProcessed = COUNT(1)
		FROM #tableList 
		WHERE IsProcessed IS NULL

		IF @ToBeProcessed > 0
		BEGIN

			SELECT @TableList  = STRING_AGG(SchemaName + '.' + TableName, ';')
			FROM #tableList
			WHERE IsProcessed IS NULL

			-- Inserting log entry to record tables that are not processed (RLS and CLS not applied)
			EXEC [security].[InsertLog_SP] 
			@BatchId = @DeploymentBatchID
			, @ActivityName = 'Unable to apply RLS and CLS to tables........'
			, @Text = @TableList
			, @DebugIndicator = @DebugIndicator;

			SELECT @TableList  = STRING_AGG(SchemaName + '.' + TableName, ';')
			FROM #tableList
			WHERE IsProcessed IS NOT NULL

			-- Inserting log entry to record tables that are processed (RLS and CLS applied)
			EXEC [security].[InsertLog_SP] 
			@BatchId = @DeploymentBatchID
			, @ActivityName = 'Applied RLS and CLS to tables........'
			, @Text = @TableList
			, @DebugIndicator = @DebugIndicator;

			-- Drop temp table
			DROP TABLE #tableList;
		END
	END;

    THROW;
END CATCH

	IF @GenerateReportIndicator = 1
	BEGIN
		EXEC [security].[GenerateDeploymentReport_SP]
		@DeploymentBatchID = @DeploymentBatchID
	END
END
GO
