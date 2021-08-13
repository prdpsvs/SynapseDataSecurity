/*
* Author: Pradeep SVS, Microsoft
* Date: 5/5/2021
* Description: This table holds column level security configuration to be applied
  on underlying tables or views in _t schema
*/
CREATE TABLE [security].[CLSConfiguration]
(
	ClsId BIGINT IDENTITY NOT NULL,
	SchemaName VARCHAR(100) NOT NULL, -- Name of the Schema
	TableName VARCHAR(100) NOT NULL, -- Name of the table or view
	ColumnName VARCHAR(100) NOT NULL, -- Name of the column for which the CLS should be applied on
	FilterColumnName VARCHAR(100) NULL, -- Column that is used to filter data
	FilterType VARCHAR(100) NOT NUll, -- Association of column to AD groups/Database role
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
	CLUSTERED INDEX (SchemaName ASC, TableName ASC, ColumnName ASC, FilterType ASC)
)
GO
