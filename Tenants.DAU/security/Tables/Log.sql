/*
* Author: Pradeep SVS, Microsoft
* Date: 5/5/2021
* Description: This table holds the execution logs for each deployment/batch.	
*/
CREATE TABLE [security].[Log]
(
	BatchId BIGINT NOT NULL,
	LogId BIGINT IDENTITY NOT NULL, 
	ActivityName VARCHAR(500) NOT NULL, -- Name of the activity
	Text NVARCHAR(MAX) NULL, -- Script or action taken by the automation process
	InsertedDate DATETIME NOT NULL,
	InsertedBy VARCHAR(100) NOT NULL	
)
WITH
(
	-- Data is frequently inserted and mostly queried using batchid
	DISTRIBUTION = ROUND_ROBIN,
	CLUSTERED INDEX (BatchId)
)
GO