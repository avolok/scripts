SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('[dbo].[uspCreateSnapshot]') IS NULL
  EXEC ('CREATE PROCEDURE [dbo].[uspCreateSnapshot] AS RETURN 0;');
GO

ALTER PROC [dbo].[uspCreateSnapshot] 
-- Select the database or the list by applying pattern search via LIKE, if value set to ALL, then all user databases will be processed
@SourceDBSearchPattern sysname = 'all',
-- Snapshot name suffix, the full snapshot name will have a value: [databasename_suffixname]
@SnashotSuffix sysname = 'Snapshot',
-- Remove existing snapshot on the same source database with the same snapshot name
@DropIfExists BIT = 0,
-- Prints output as SQL Script and skip execution of creation of the snapshot
@Debug BIT = 0
AS
SET NOCOUNT ON

----------------------------------------------------------------------------------------------------
  --// Source:  https://avolok.github.io                                                          //--  
  --// GitHub:  https://github.com/avolok/scripts                                                 //--
  --// Version: 2019-02-19                                                                        //--
  ----------------------------------------------------------------------------------------------------



DECLARE @_SourceDB sysname;

-- loop through  user databases
DECLARE ct CURSOR FOR 
SELECT d.name FROM sys.databases d
WHERE 1 = 1

-- if All specified then process all user database otherwise only if name matches to @SourceDatabase
AND ((d.name LIKE @SourceDBSearchPattern AND @SourceDBSearchPattern != 'All') OR @SourceDBSearchPattern = 'All')

-- system databases are excluded
AND d.database_id > 4 

-- other snapshots are excluded
AND d.source_database_id IS NULL 

-- Databases with filestream and in-memory filegroups are excluded
AND NOT EXISTS ( 	
	SELECT * from sys.master_files mf
	WHERE mf.type = 2 AND mf.database_id = d.database_id
)


OPEN ct
FETCH NEXT FROM ct INTO @_SourceDB

WHILE @@FETCH_STATUS = 0
BEGIN

PRINT '-- Processing database: '  + QUOTENAME(@_SourceDB);
    
DECLARE @DatabaseSnapshot sysname = @_SourceDB + '_' + @SnashotSuffix;
DECLARE @sql NVARCHAR(MAX) = '';



-- if snapshot already exists and it is allowed to drop it:	
IF @DropIfExists = 1 AND EXISTS (
	SELECT * FROM sys.databases snp
	JOIN sys.databases db ON snp.source_database_id = db.database_id
	WHERE snp.name = @DatabaseSnapshot AND db.name = @_SourceDB
)
BEGIN
   
    SET @sql = N'DROP DATABASE '+QUOTENAME(@DatabaseSnapshot);

IF @Debug = 1
	PRINT 
'
-- Executing SQL:
'  + @sql + '	

	'
	IF @Debug = 0 
	BEGIN
		EXEC sp_executesql @sql;
		PRINT '-- Existing snapshot ' + QUOTENAME(@DatabaseSnapshot) + ' removed from database ' + QUOTENAME(@_SourceDB )
	END    
END;

-- if snapshot already exists and it is not allowed to drop it, just printing a message
ELSE IF EXISTS (
	SELECT * FROM sys.databases snp
	JOIN sys.databases db ON snp.source_database_id = db.database_id
	WHERE snp.name = @DatabaseSnapshot AND db.name = @_SourceDB
)
BEGIN
    PRINT '-- Snapshot ' + QUOTENAME(@DatabaseSnapshot) + ' already created on database ' + QUOTENAME(@_SourceDB ) + ', nothing more to do
	'
	
	--Redirect to end of the cycle
	GOTO EndOfCycle; 
END



    -- Building a command to create a new snapshot
    SET @sql = N'';
    WITH cte
    AS (SELECT name,
               physical_name,
               ROW_NUMBER() OVER (ORDER BY create_lsn) rn
        FROM sys.master_files
        WHERE database_id IN
              (
                  SELECT database_id FROM sys.databases WHERE name = @_SourceDB
              )
              AND type = 0 -- ROWS
    )
    SELECT @sql = @sql + N'(NAME = ' + QUOTENAME(name) + N', FILENAME =''' + physical_name + N'.'+@SnashotSuffix+'''),
 '
    FROM cte;

    SET @sql = SUBSTRING(@sql, 1, LEN(@sql) - 3);

    SET @sql = N'CREATE DATABASE ' + QUOTENAME(@DatabaseSnapshot) + N' ON
 ' + @sql + N'
 AS SNAPSHOT OF ' + QUOTENAME(@_SourceDB) + N';';


IF @Debug = 1    
	PRINT 
'
-- Executing SQL:
'  + @sql + '	

	'

	IF @Debug = 0 
	BEGIN
		EXEC sp_executesql @sql;
		PRINT '-- Snapshot ' + QUOTENAME(@DatabaseSnapshot) + ' has been created on database ' + QUOTENAME(@_SourceDB ) + '
		'
	END


	EndOfCycle:
	FETCH NEXT FROM ct INTO @_SourceDB
END


CLOSE ct
DEALLOCATE ct
	
GO