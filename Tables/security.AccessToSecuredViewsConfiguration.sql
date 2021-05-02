CREATE TABLE [security].[AccessToSecuredViewsConfiguration]
(
	[AccessId] [bigint] IDENTITY(1,1) NOT NULL,
	[SchemaName] [varchar](100) NOT NULL,
	[TableName] [varchar](100) NULL, -- If NULL, the grant is at schema level, else table
	[GrantType] VARCHAR(100) NOT NULL, -- Grant/deny
	[Grant] VARCHAR(500) NOT NULL, -- SELECT, VEW DEFINITION
	[ADGroupOrRoleName] [varchar](100) NOT NULL
)
WITH
(
	DISTRIBUTION = REPLICATE,
	CLUSTERED INDEX
	(
		[SchemaName] ASC,
		[TableName] ASC
	)
)
GO

