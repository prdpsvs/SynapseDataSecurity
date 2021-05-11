CREATE PROC [security].[AssignTenantADGroupsToDbRoles_SP]
		@DebugIndicator BIT
AS
/*
-- =============================================================================
-- Procedure Name       - AssignTenantADGroupsToDbRoles_SP
-- Author               - Pradeep Srikakolapu, Microsoft
-- Date Created         - 5/5/2021
-- Description          - Assigns Tenant AD groups to SE Database roles
--
-- Input parameters:
-- @DebugIndicator		- Indicator to debug the code
--
-- Sample call:
-- EXEC [security].[AssignTenantADGroupsToDbRoles_SP]
-- @DebugIndicator = 1
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
	DECLARE @NoOfRolesToAssign INT, @Counter INT = 1
	DECLARE @RoleAssignmentId BIGINT
	DECLARE @DatabaseRoleName VARCHAR(100), @TenantADGroupName VARCHAR(100), @ActivityName VARCHAR(500), @Action VARCHAR(100)
	DECLARE @RoleAssignmentScript NVARCHAR(MAX)
	DECLARE @CurrentDatetime DATETIME
	DECLARE @Error VARCHAR(MAX)
	
	SET @RoleAssignmentScript = 'EXEC sp_<Action>rolemember ''<RoleName>'', ''<ADGroupName>'''

	IF OBJECT_ID(N'tempdb..#RoleAssignments') IS NOT NULL
	BEGIN
		DROP TABLE #RoleAssignments
	END

	CREATE TABLE #RoleAssignments
	WITH
	(
		DISTRIBUTION = ROUND_ROBIN
	)
	AS
	SELECT ROW_NUMBER() OVER(ORDER BY RoleAssignmentId ASC) AS Row#
	, DbRole
	, TenantADGroupName
	, Action
	, RoleAssignmentId
	FROM [security].[RoleAssignmentsConfiguration]
	WHERE IsProcessed IS NULL

	SELECT @NoOfRolesToAssign = COUNT(1) 
	FROM #RoleAssignments

	WHILE @Counter <= @NoOfRolesToAssign
	BEGIN
		BEGIN TRY
			SELECT @DatabaseRoleName = DbRole
			, @TenantADGroupName = TenantADGroupName
			, @RoleAssignmentId = RoleAssignmentId
			, @Action = Action
			FROM #RoleAssignments
			WHERE Row# = @Counter

			SELECT @RoleAssignmentScript = REPLACE(@RoleAssignmentScript, '<RoleName>' , @DatabaseRoleName)
			SELECT @RoleAssignmentScript = REPLACE(@RoleAssignmentScript, '<ADGroupName>' , @TenantADGroupName)
			SELECT @RoleAssignmentScript = REPLACE(@RoleAssignmentScript, '<Action>' , LOWER(@Action))
	
			SET @ActivityName = 'Role Assignment - Id for ' + @DatabaseRoleName + '/' + @TenantADGroupName
		
			EXEC [security].[PrintLogRecord_SP] @BatchId = -999
			, @ActivityName = @ActivityName
			, @Text = @RoleAssignmentScript
			, @DebugIndicator = @DebugIndicator

			EXEC (@RoleAssignmentScript)

			SET @CurrentDatetime = GETDATE()
			UPDATE [security].[RoleAssignmentsConfiguration]
			SET IsProcessed = 1
			, RoleAssignmentDate = @CurrentDatetime
			, ProcessedStatusAndRemarks = 'Processed'
			WHERE RoleAssignmentId = @RoleAssignmentId
		
		END TRY
		BEGIN CATCH
			
			SELECT @Error = CAST(ERROR_SEVERITY() AS VARCHAR) + '/' + CAST(ERROR_STATE() AS VARCHAR) + '/' + ERROR_PROCEDURE() + '/' + ERROR_MESSAGE()
	
			SET @CurrentDatetime = GETDATE()
			UPDATE [security].[RoleAssignmentsConfiguration]
			SET IsProcessed = 0
			, RoleAssignmentDate = @CurrentDatetime
			, ProcessedStatusAndRemarks = @Error
			WHERE RoleAssignmentId = @RoleAssignmentId
		
		END CATCH
		SET @counter = @Counter+1
	END
	DROP TABLE #RoleAssignments
END TRY
BEGIN CATCH
    SELECT @Error = CAST(ERROR_SEVERITY() AS VARCHAR) + '/' + CAST(ERROR_STATE() AS VARCHAR) + '/' + ERROR_PROCEDURE() + '/' + ERROR_MESSAGE()
	PRINT @Error;
	THROW;
END CATCH
END
