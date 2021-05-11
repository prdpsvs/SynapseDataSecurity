# kp-azure-a20tnt-synapse
This repository will house A20 tenant specific synapse resources. Please reach out to [Vamsee Lakkaraju](mailto:vamsee.lakkaraju@kp.org) or [Adbul H. Havaldar](mailto:abdul.h.havaldar@kp.org) for any issues related to version control and broken links in this documentation.

# Tenants Managed Data Access & Use folder 
Tenants Managed Data Access & Use folder contains 
1. code to deploy data access automated views and functions to apply Row & Column Level Security.
2. code to deploy select/view definition grants on views and schemas after views are created automatically
3. code to assign AD Group roles to database roles

## Deploy Tenants Managed Data Access & Use Solution On Tenants Synapse Instance

### Manual Deployment
1. Create a schema security on Tenant database
```T-SQL
    CREATE SCHEMA security;
```
2. Deploy all tables in [master branch](https://github.kp.org/CSG/kp-azure-a20tnt-synapse/tree/master/Tenants%20Managed%20Data%20Access%20%26%20Use/Tables) in any order.

3. Deploy all Stored Procedures in [master branch](https://github.kp.org/CSG/kp-azure-a20tnt-synapse/tree/master/Tenants%20Managed%20Data%20Access%20%26%20Use/Stored%20Procedures) in any order.

### Automated Deployment
> TBD

## Capabilities Of Tenants Managed Data Access & Use Solution
1. Tenants can choose to automatically deploy views or generate view scripts to manually deploy based on tenant deployment maturity model. This solution deploys/generates view without RLS and CLS applied if no RLS and CLS configurations are provided on a table.

    * When tenants execute the deployment scripts, tenants can configure different parameters to execute the automated solution. Please read the comments for each parameter.

     ``` T-SQL
     DECLARE @BatchId BIGINT
    EXEC [security].[OrchestrateRlsAndCls_SP]
            -- Provide this parameter when executing 
            -- the SP for the first time end to end
            @DeploymentStartDatetimeInUTC = ''
            /* 
                Provide the list of tables (fully qualified table name<schema.table>) separated by a delimiter ';'. 
                If @TableList parameter is provided, views are refreshed/created only for tables include in
                @TableList
            */
            , @TableList = ''
            /*
                If tenants choose to deploy the views, set the value to 1
                If tenants choose to generate the view, set the value to 0
                The scripts are persisted in security.GeneratedObjectScripts table
            */
            , @DeploymentIndicator = 1
            /* 
                
            */
            , @DebugIndicator = 1
            /*
                If tenants choose to generate the report for auditing or
                monitoring set the @GenerateReportIndicator to 1 else 0
            */
            , @GenerateReportIndicator = 1
             /*
                If tenants choose to deploy grants on view or schema using this
                solution set the @DeployGrantsIndicator = 1 else 0
            */
            , @DeployGrantsIndicator = 1
            , @DeploymentBatchID = @BatchId OUTPUT

    /*
        For every deployment, a batch Id is generated (yyyymmddhhmmss format) to track the deployment. 
        Security.log table contains all the steps and errors during execution and queried on.
    */
    SELECT * FROM security.log WHERE BatchId = @BatchId ORDER BY INSERTEDDATE
    SELECT * FROM [security].[GeneratedObjectScripts] WHERE BatchId = @BatchId
    ``` 

2. To configure RLS, use **security.RLSConfiguration, security.FilterConfiguration** tables.
    
    | RlsId | SchemaName | TableName | RowFilterColumnName | FilterType | IsEnabled | InsertedBy | InsertedDate | UpdatedBy | UpdatedDate |
    |-----|-----|-----|----|-----|----|-----|------|------------|----------|
    |1|WRKGRPDT_T|ODS_MBR|RGN_CD|dau.meberpatienphi|1|I171705@kp.org|5/7/2021|I171705@kp.org|5/7/2021|

    * In above example, provide the column name on which RLS should be applied for a table in a schema. 

    * Once RLS configuration for a column is added to **security.RLSConfiguration** table, then provide the AD Groups or database roles who can see data based on Row level filters. The table **security.FilterConfiguration** holds the AD group or database role associated to filter row level data. **NOTE: USE DATABASE ROLES ONLY for ADGroupOrRoleName column**

    | SecurityType | FilterType | ADGroupOrRoleName | FilterValue |
    |-----|-----|-----|----|
    |Row|dau.meberpatienphi|RADA_MPPHI_CN|CN|
    |Row|dau.meberpatienphi|RADA_MPPHI_HI|HI|
    |Row|dau.meberpatienphi|RADA_MPPHI_HA|HA|

    * If the above configuration is applied, then WRKGRPDP_V.ODS_MBR view is deployed on database. Users can access data by using below query.
    ``` T-SQL
    SELECT * FROM WRKGRPDP_V.ODS_MBR
    ``` 
    If a user is added to AD group **RADA_MPPHI_CN**, user gets access to region CN. All other users who are not added to **RADA_MPPHI_CN** can not access CN region data. Similarly, users in _HI and _HA groups would get access to respective locations.

3. To configure CLS, use **security.CLSConfiguration, security.FilterConfiguration** tables.
    
    | ClsId | SchemaName | TableName | ColumnName | FilterColumnName | FilterType | IsEnabled | InsertedBy | InsertedDate | UpdatedBy | UpdatedDate |
    |-----|-----|-----|----|-----|----|-----|------|----|-------|----------|
    |1|WRKGRPDT_T|ODS_MBR|BIRTH_DT|RGN_CD|dau.meberpatienphi|1|I171705@kp.org|5/7/2021|I171705@kp.org|5/7/2021|

    * In above example, provide the column name (FilterColumnName) on which CLS should be applied for a table in a schema. This will allow to secure data in a column based on another column. In above example, BIRTH_DT can be secured based on RGN_CD column data

    * Once CLS configuration for a column is added to **security.CLSConfiguration** table, then provide the AD Groups or database roles who can see data based on another column data. The table **security.FilterConfiguration** holds the AD group or database role associated to filter column level data. **NOTE: USE DATABASE ROLES ONLY for ADGroupOrRoleName column**

    | SecurityType | FilterType | ADGroupOrRoleName | FilterValue |
    |-----|-----|-----|----|
    |Column|dau.meberpatienphi|RADA_MPPHI_CN|CN|

    * If the above configuration is applied, then WRKGRPDP_V.ODS_MBR view is deployed on database. Users can access data by using below query.
    ``` T-SQL
    SELECT * FROM WRKGRPDP_V.ODS_MBR
    ``` 
    If a user is added to AD group **RADA_MPPHI_CN**, user gets access to region CN. All other users who are not added to **RADA_MPPHI_CN** can not access CN region data. 

4. The automated solution provide capabilities to skip the view creation by addiing schema and table name to **security.ViewsNotRequired** table. If the value of TableName column for a schema is *, then the views are not created for all tables in a schema. If both table and schema name are provided, then view is not create for second configuration in the table.

    | SchemaName | TableName |
    |--------|----------|
    |WRKGRPDT_T|*|
    |PUB_T|ODS_MBR|
 
5. The automated solution provide configuration to apply grants on view or schema
    * This solution can apply SELECT or VIEW DEFINITION grants on a view or schema.
    * Connect GRANT is automatically applied when a user/AD Group is added to the database.
    * The grants configurations are managed in a table **security.AccessToSecuredViewsConfiguration**.

    | AccessId | SchemaName | TableName | GrantType | Grant | ADGroupOrRoleName |
    |--------|----------|---------|---------|------------------|----------|
    |1|WRKGRPDT_T|ODS_MBR|GRANT|SELECT|RADA_MPPHI_DEV|
    |2|PUB_T|NULL|GRANT|SELECT|RADA_MPSSN_DEV|

    * The configuration table contains the name of table and schema but the grants are applied on views that are generated in _V schema.
    * If the table name is null, then the grants are applied on a schema.
    * The grants are applied only if the views are deployed by the solution.

6. The automated solution allows to apply grants for RLS and CLS to database roles or AD Groups. As per DAU, the RLS and CLS should applied on database roles and hence tenants need to way to assign AD Group(s) to a role(s).

    * Role Assigned is managed in **security.RoleAssignmentsConfiguration** table.    
    | RoleAssignmentId | DbRole | TenantAdGroupName | Action | Tenant | Notes | InsertedDate | IsProcessed | ProcessedStatusAndRemarks | RoleAssignmentDate |
    |-----|------|-----|-----|-----|-----|------|-------|-------|--------|
    |1|ADF_RADA_MPSSN_Dev_Role|priv_group_adf_rada_mpphi_dev|add|SELECT|Test Assignment|5/7/2021|NULL|NULL|NULL|
    * RoledAssignmentDate and InsertedDate are in UTC.
    * Two actions are supported **ADD** OR **DROP**. Add will assign AD group to a database role. DROP will remove AD group from a database role.

## Considerations To Apply RLS & CLS
1. Tenants does not have access to data/tables. Tenant users always access data via Views. Exception:  If tenants choose to not create views on a table, only then tenant users will have access to table(s).
2. Column Level Security is managed using CASE statements in a view and Row Level security is applied using filter predicate functions cross applied on a view.
3. Column or Row Level Security does not change tenant’s queries structure or query patterns. The view and the underlying table columns, column(s) name and metadata of columns are same. Example: If the requirement is to protect a column (lets say MemberSSN) on a table with 6 columns, users will have access to all columns and MemberSSN column data is masked.  
4. Table and view are same. Tables are hosted in _T schema and views are hosted in _V schema. Please note that views can be created for a table or view hosted in _T schema only.
5. RLS is applied on a table by creating a filter predicate funtion which evaluates if tenant user has access to the row. RLS is usually applied by creating security policy on a table/column and apply filter predicate. In Azure SQL Data Warehouse (Gen2 - Synapse), a table can have one security filter. Security policies will interfer with nested RLS requirements. Due to these limitations, the solution does not offer RLS with security policies, there by tenant DBA's must audit the RLS functions using DDL audit capabilities.
6. Filter predicates are applied using a function on SELECT/INSERT/UPDATE/DELETE operations on a table. A filter predicate is created for per column/table combination. Filter predicates should be audited using DDL tracking auditing.
7. CLS is not applied using CLS (hide columns - this changes the query structure), CLE (encrypt column data - this changes the way data is queried), AE (not supported) or DDM (not secure when default or custom functions are used) in-built features. CLS is applied using case expressions with ISMEMEBER capability. 
8. Nested CLS capability is not supported by Azure SQL Data Warehouse (Gen2 - Synapse).





