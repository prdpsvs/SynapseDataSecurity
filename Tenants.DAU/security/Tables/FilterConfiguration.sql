/*
* Author: Pradeep SVS, Microsoft
* Date: 5/5/2021
* Description: This table holds the configuration of column associated with AD Groups to secure row or a column.
*/
CREATE TABLE [security].[FilterConfiguration]
(
	SecurityType VARCHAR(20) NOT NULL, -- Allowed values are Row/Column 
	FilterType VARCHAR(100) NOT NULL,
	ADGroupOrRoleName VARCHAR(100) NOT NULL, -- Database role applied on a row or column to protect data
	FilterValue VARCHAR(100) NULL -- value used with RLSConfiguration/CLSConfiguration table for nesting
)
WITH
(
	-- This table holds less than 10K rows and easy to rebuild.
	-- Also this table is built only at the time of deployment
	DISTRIBUTION = REPLICATE,
	-- Creating clustered index to manage the joins, group by and where clauses
	CLUSTERED INDEX (SecurityType, FilterType)
)
GO