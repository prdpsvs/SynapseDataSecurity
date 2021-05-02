CREATE TABLE [security].[FilterConfiguration]
(
	SecurityType VARCHAR(20) NOT NULL,
	FilterType VARCHAR(100) NOT NULL,
	ADGroupOrRoleName VARCHAR(100) NOT NULL,
	FilterValue VARCHAR(100) NULL
)
WITH
(
	DISTRIBUTION = REPLICATE,
	CLUSTERED INDEX (SecurityType, FilterType)
)