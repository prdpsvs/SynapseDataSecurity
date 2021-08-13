/*
* Author: Pradeep SVS, Microsoft
* Date: 5/5/2021
* Description: This table holds the fully qualified table name (<schema>.<tablename>) or
  schema name to skip view creation process
*/
CREATE TABLE [security].[ViewsNotRequired]
(
	Id BIGINT IDENTITY NOT NULL,
	SchemaName VARCHAR(100) NOT NULL, -- Name of the schema
	TableName VARCHAR(100) NOT NULL -- Name of the table. If value is *, the views are not created for all tables in a schema.
)
WITH
(
	-- This table holds less than 10K rows and easy to rebuild.
	-- Also this table is built only at the time of deployment
	DISTRIBUTION = REPLICATE,
	-- Creating clustered index to manage the joins, group by and where clauses
	CLUSTERED INDEX (SchemaName ASC, TableName ASC)
)
GO