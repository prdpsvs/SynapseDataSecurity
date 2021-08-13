/*
* Author: Pradeep SVS, Microsoft
* Date: 5/5/2021
* Description: This table holds the Row level security configuration for a column in a
  table/view with AD group associations	
*/
CREATE TABLE [security].[RLSConfiguration]
(
	RlsId BIGINT IDENTITY NOT NULL,
	SchemaName VARCHAR(100) NOT NULL, -- Name of the schema
	TableName VARCHAR(100) NOT NULL, -- Name of the table or view
	RowFilterColumnName VARCHAR(100) NOT NULL, -- Name of the column on which RLS should be applied
	FilterType VARCHAR(100) NOT NUll, -- Database Role or AD Group association
	IsEnabled BIT NOT NULL,
	InsertedBy VARCHAR(100) NOT NULL,
	InsertedDate DATETIME NOT NULL,
	UpdatedBy VARCHAR(100) NOT NULL,
	UpdatedDate DATETIME NOT NULL
)
WITH
(
	-- This table holds less than 10K rows and easy to rebuild.
	-- Also this table is built only at the time of deployment
	DISTRIBUTION = REPLICATE,
	-- Creating clustered index to manage the joins, group by and where clauses
	CLUSTERED INDEX (SchemaName ASC, TableName ASC, RowFilterColumnName ASC)
)
GO