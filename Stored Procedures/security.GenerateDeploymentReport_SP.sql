CREATE PROC [security].[GenerateDeploymentReport_SP]
		@DeploymentBatchID BIGINT OUTPUT
AS
/*
-- =============================================================================
-- Procedure Name       - GenerateDeploymentReport_SP
-- Author               - Pradeep Srikakolapu, Microsoft
-- Date Created         - 4/13/2021
-- Description          - Generates Deployment Report
--
-- Input parameters:
-- @DeploymentBatchID				- BatchId to generate the report
--
-- Sample call:
-- DECLARE @BatchId BIGINT
-- EXEC [security].[GenerateDeploymentReport_SP]
-- @DeploymentBatchID = 1
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

	DECLARE @Counter INT = 1
	DECLARE @TotalRecords BIGINT
	DECLARE @ActivityName VARCHAR(500), @Text NVARCHAR(MAX)

	IF OBJECT_ID(N'tempdb..#DeploymentLog') IS NOT NULL
	BEGIN
		-- Drop temp table
		DROP TABLE #DeploymentLog;
	END

	CREATE TABLE #DeploymentLog
	WITH
	(
		DISTRIBUTION = ROUND_ROBIN,
		CLUSTERED INDEX (InsertedDate)
	)
	AS
	SELECT ROW_NUMBER() OVER(ORDER BY InsertedDate ASC) AS Row#
	, ActivityName
	, [Text]
	, BatchId
	, InsertedDate
	FROM [security].[log]
	WHERE BatchId = @DeploymentBatchID

	SELECT @TotalRecords = COUNT(1)
	FROM #DeploymentLog
	WHERE BatchId = @DeploymentBatchID

	WHILE @TotalRecords >= 1 AND @Counter <= @TotalRecords
	BEGIN
		
		SELECT @ActivityName = ActivityName
		, @Text = [Text]
		FROM #DeploymentLog
		WHERE Row# = @Counter

		EXEC [security].[PrintLogRecord_SP] 
		@BatchId = @DeploymentBatchID
		, @ActivityName = @ActivityName
		, @Text = @Text
		, @DebugIndicator = 1

		SET @Counter = @Counter + 1;
	END

	-- Drop temp table
	DROP TABLE #DeploymentLog;
END TRY
BEGIN CATCH

    DECLARE @Error VARCHAR(MAX)
	SELECT @Error = CAST(ERROR_SEVERITY() AS VARCHAR) + '/' + CAST(ERROR_STATE() AS VARCHAR) + '/' + ERROR_PROCEDURE() + '/' + ERROR_MESSAGE()
	
	PRINT ' Error In generating report'
	PRINT @Error

END CATCH
END
GO
