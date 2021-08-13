/*
* Author: Pradeep SVS, Microsoft
* Date: 5/5/2021
* Description: This table holds the configuration to add AG groups to a database role.
  The Database roles are created upfront by DBA's.
  A separate automation process executes the role assignments as soon as 
  role configurations are added to this table.
*/
CREATE TABLE [security].[RoleAssignmentsConfiguration]
(
	RoleAssignmentId BIGINT IDENTITY NOT NULL,
	DbRole VARCHAR(100) NOT NULL,
	TenantADGroupName VARCHAR(100) NOT NULL,
	Action VARCHAR(100) NOT NULL,
	TenantName VARCHAR(100) NULL,
	Notes VARCHAR(MAX) NULL,
	InsertedDate DATETIME NOT NULL,
	IsProcessed BIT NULL,
	ProcessedStatusAndRemarks VARCHAR(MAX) NULL,
	RoleAssignmentDate DATETIME NULL
)
WITH
(
	-- The role assignments are added/updated frequently, there by
	-- the distribution is round robin
	DISTRIBUTION = ROUND_ROBIN,
	CLUSTERED INDEX (TenantName, TenantADGroupName, DbRole)
)
GO