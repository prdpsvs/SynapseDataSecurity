/*
* Author: Pradeep SVS, Microsoft
* Date: 5/5/2021
* Description: This table holds the grant type and grants for the views or schema
  based on underlying schema/table or view.
*/
CREATE TABLE [security].[AccessToSecuredViewsConfiguration]
(
	[AccessId] [bigint] IDENTITY(1,1) NOT NULL,
	[SchemaName] [varchar](100) NOT NULL, -- Name of the schema
	[TableName] [varchar](100) NULL, -- If NULL, the grant is at schema level, else table
	[GrantType] VARCHAR(100) NOT NULL, -- Grant/deny
	[Grant] VARCHAR(500) NOT NULL, -- SELECT, VEW DEFINITION
	[ADGroupOrRoleName] [varchar](100) NOT NULL -- Name of the database role or AD Group
)
WITH
(
	-- This table holds less than 10K rows and easy to rebuild.
	-- Also this table is built only at the time of deployment
	DISTRIBUTION = REPLICATE,
	-- Creating clustered index to manage the joins, group by and where clauses
	CLUSTERED INDEX
	(
		[SchemaName] ASC,
		[TableName] ASC
	)
)
GO