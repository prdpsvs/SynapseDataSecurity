CREATE PROC [security].[PrintLogRecord_SP]
		@BatchId BIGINT
		, @ActivityName VARCHAR(500)
		, @Text NVARCHAR(MAX)
		, @DebugIndicator BIT
AS
/*
-- =============================================================================
-- Procedure Name       - PrintLogRecord_SP
-- Author               - Pradeep Srikakolapu, Microsoft
-- Date Created         - 4/9/2021
-- Description          - Prints log record to results tab 
--
-- Input parameters:
-- @BatchId				- BatchId
-- @ActivityName		- Indicator to print or not
-- @Text				- Text to print
-- @DebugIndicator		- Indicator to debug the code
--
-- Sample call:
-- EXEC [security].[PrintLogRecord_SP] @BatchId = 1, @ActivityName = 'Hello'
-- @Text = N'', @DebugIndicator = 1
-- =============================================================================
-- Revisions:
--
--  Date        Developer   Change Description
--  ----------  ----------  --------------------------------------------------
-- =============================================================================
*/

IF @DebugIndicator = 1
BEGIN
	
	DECLARE @Counter INT
	SET @Counter = 0
	DECLARE @TotalPrints INT
	SET @TotalPrints = (LEN(@Text)/4000) + 1

	PRINT @ActivityName
	WHILE @Counter < @TotalPrints
	BEGIN
		PRINT (SUBSTRING(@Text, @Counter * 4000, (@Counter + 1) * 4000))
		SET @Counter = @Counter + 1
	END
	PRINT '==================================================================================='
END