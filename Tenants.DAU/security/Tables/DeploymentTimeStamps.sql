/*
* Author: Pradeep SVS, Microsoft
* Date: 5/5/2021
* Description: This table holds the deployment timestamp for each deployment.
 The latest deployment uses DeploymentTimeStampInUTC to capture
 the DDL changes since last deployment timestamp.

*/
CREATE TABLE [security].[DeploymentTimeStamps]
(
	DeploymentTimeStampInUTC DATETIME -- Captured in UTC in alignment with system tables (sys.tables/views/schemas)
)
WITH
(HEAP)
GO
