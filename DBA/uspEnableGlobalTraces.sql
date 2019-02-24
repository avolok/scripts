-- Stored procedure in  Master 
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON

USE MASTER


GO

IF OBJECT_ID('[dbo].[uspEnableGlobalTraces]') IS NULL
  EXEC ('CREATE PROCEDURE [dbo].[uspEnableGlobalTraces] AS RETURN 0;');
GO

GO 
ALTER PROCEDURE [dbo].[uspEnableGlobalTraces]
AS

SET NOCOUNT ON

----------------------------------------------------------------------------------------------------
  --// Source:  https://avolok.github.io                                                          //--  
  --// GitHub:  https://github.com/avolok/scripts                                                 //--
  --// Version: 2018-12-05                                                                        //--
----------------------------------------------------------------------------------------------------


DECLARE @ProductBuild int  --= ( SELECT SERVERPROPERTY('ProductBuild'))
DECLARE @ProductMajorVersion INT --int = (SELECT SERVERPROPERTY('ProductMajorVersion'))

SET @ProductBuild  = TRY_CAST(( SELECT SERVERPROPERTY('ProductBuild')) AS INT)
SET @ProductMajorVersion = TRY_CAST((SELECT SERVERPROPERTY('ProductMajorVersion')) AS INT)


--Replace error message 8152 with 2628 (String or binary data would be truncated. The statement has been terminated.). 
--Description for 2628 mesage has useful information - which column had the truncation and which row.
--(for SQL Server 2019, >= 2017 CU12)
IF (@ProductMajorVersion  = 14 AND @ProductBuild >= 3045) OR (@ProductMajorVersion > 14)
BEGIN
	PRINT 'Enabling trace: 460. (Replace error message 8152 with 2628)'
	DBCC TRACEON(460, -1)
END 


--Addresses contention that can exist on a particular type of page in a database, the SGAM page. 
--This trace flag typically provides benefit for customers that make heavy use of the tempdb system database. 
--In SQL Server 2016, you change this behavior using the MIXED_PAGE_ALLOCATION database option, and there is no need for TF 1118.
BEGIN
	PRINT '' -- new line
	PRINT 'Enabling trace: 1118. (Addresses contention that can exist on a particular type of page in a database, the SGAM page)'
	DBCC TRACEON(1118, -1)
END 

-- Trace flag 3023 is used to enable the CHECKSUM option, by default, for all backups taken on an instance. 
-- WITH this option enabled, page checksums are validated during a backup, and a checksum for the entire backup is generated. 
-- Starting in SQL Server 2014, this option can be set instance-wide through sp_configure ('backup checksum default').
BEGIN
	PRINT '' -- new line
	PRINT 'Enabling trace: 3023. (Enables the CHECKSUM option by default, for all backups taken on an instance)'
	DBCC TRACEON(3023, -1)
END 


-- Trace flag 3226 prevents the writing of successful backup messages to the SQL Server ERRORLOG. 
-- Information about successful backups is still written to msdb and can be queried using T-SQL. 
-- For servers with multiple databases and regular transaction log backups, enabling this option means the ERRORLOG is no longer bloated 
-- WITH BACKUP DATABASE and Database backed up messages. 

BEGIN
	PRINT '' -- new line
	PRINT 'Enabling trace: 3226. (Prevents the writing of successful backup messages to the SQL Server ERRORLOG)'
	DBCC TRACEON(3226, -1)
END 


-- Trace flag 3427 Another change in SQL Server 2016 behavior that could impact tempdb-heavy workloads has to do with Common Criteria Compliance (CCC), 
-- also known as C2 auditing. We introduced functionality to allow for transaction-level auditing in CCC which can cause some additional overhead, 
-- particularly in workloads that do heavy inserts and updates in temp tables. Unfortunately, this overhead is incurred whether you have CCC enabled or not. 
-- In SQL Server 2016 you can enable trace flag 3427 to bypass this overhead starting with SP1 CU2. 
-- Starting in SQL Server 2017 CU4, we automatically bypass this code if CCC is disabled. 

IF (@ProductMajorVersion  = 14 AND @ProductBuild < 3022) OR (@ProductMajorVersion = 13)
BEGIN
	PRINT '' -- new line
	PRINT 'Enabling trace: 3427. (Behavior that could impact tempdb-heavy workloads has to do with Common Criteria Compliance (CCC))'
	DBCC TRACEON(3427, -1)
END 

-- Trace flag 3449 (and you are on SQL Server 2012 SP3 CU3 or later or SQL Server 2014 SP1 CU7 or later), 
-- will get much better performance by avoiding a FlushCache call in a number of different common scenarios, 
-- such as backup database, backup transaction log, create database, add a file to a database, restore a transaction log, 
-- recover a database, shrink a database file, and a SQL Server “graceful” shutdown.
IF (@ProductMajorVersion  >= 11 )
BEGIN
	PRINT '' -- new line
	PRINT 'Enabling trace: 3449. (Better performance by avoiding a FlushCache call in a number of different common scenarios)'
	DBCC TRACEON(3449, -1)
END 

-- Trace Flag: 4199. Enables query optimizer hotfixes. 
BEGIN
	PRINT '' -- new line
	PRINT 'Enabling trace: 4199. (Enables query optimizer hotfixes)'
	DBCC TRACEON(4199, -1)
END 



GO


-- Turn on autostart option on for the procedure

exec sp_procoption @ProcName = 'dbo.uspEnableGlobalTraces', 
@OptionName = 'STARTUP', 
@OptionValue = 'on'


-- Check if autostart activated
SELECT 'List stored procedures with activated autostart:' AS [Check:]
UNION ALL
SELECT '  - ' + ROUTINE_NAME
FROM MASTER.INFORMATION_SCHEMA.ROUTINES
WHERE OBJECTPROPERTY(OBJECT_ID(ROUTINE_NAME),'ExecIsStartup') = 1