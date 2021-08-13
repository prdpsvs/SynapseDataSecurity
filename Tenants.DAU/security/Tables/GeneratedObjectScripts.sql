/*
* Author: Pradeep SVS, Microsoft
* Date: 5/5/2021
* Description: This table holds the scripts generated in a deployment or a batch.
*/
CREATE TABLE [security].[GeneratedObjectScripts]
(
	Id BIGINT IDENTITY NOT NULL,
	BatchId BIGINT NOT NULL, -- Batch Id (yyyymmddhhmmss)
	SchemaName VARCHAR(100) NOT NULL,
	TableName VARCHAR(100) NOT NULL, -- Name of the table or view for which the script is generated for
	ScriptType VARCHAR(100) NOT NULL, -- Function/view/grant scripts
	Script NVARCHAR(MAX) NOT NULL -- Script generated for RLS or CLS or Grants
)
WITH 
(
	-- Mostly queried using batch id or schema/table name
	DISTRIBUTION = ROUND_ROBIN,
	CLUSTERED INDEX (BatchId ASC, SchemaName ASC, TableName ASC)
)
GO