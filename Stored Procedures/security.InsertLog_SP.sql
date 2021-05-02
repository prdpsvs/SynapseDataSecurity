CREATE PROC [security].[InsertLog_SP]
		@BatchId BIGINT
		, @ActivityName VARCHAR(500)
		, @Text NVARCHAR(MAX)
		, @DebugIndicator BIT
AS
/*
-- =============================================================================
-- Procedure Name       - InsertLog_SP
-- Author               - Pradeep Srikakolapu, Microsoft
-- Date Created         - 4/9/2021
-- Description          - Inserts a log entry 
--
-- Input parameters:
-- @BatchId				- BatchId
-- @ActivityName		- Indicator to print or not
-- @Text				- Text to print
-- @DebugIndicator		- Indicator to debug the code
--
-- Sample call:
-- EXEC [security].[InsertLog_SP] @BatchId = 1, @ActivityName = 'Hello'
-- @Text = N'', @DebugIndicator = 1
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

	DECLARE @Datetime DATETIME, @InsertedBy VARCHAR(100)
	SELECT @Datetime = GETDATE(), @InsertedBy = CURRENT_USER
	INSERT INTO [security].[Log] (BatchId, ActivityName, [Text], InsertedDate, InsertedBy)
	VALUES (@BatchId, @ActivityName, @Text, @Datetime, @InsertedBy)

	EXEC [security].[PrintLogRecord_SP] 
		@BatchId = @BatchId
		, @ActivityName = @ActivityName
		, @Text = @Text
		, @DebugIndicator = @DebugIndicator

END TRY
BEGIN CATCH
    PRINT 'Error in inserting log to security.log table' ;
	THROW;
END CATCH
END
