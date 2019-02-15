CREATE OR ALTER PROC [dbo].[uspCreateDatabaseSnapshot] 
@SourceDatabase sysname = 'all',
@SnashotSuffix sysname = 'Snapshot',
@DropIfExists BIT = 0
AS
-- to-do:
-- Search pattern
-- Improve output
-- Add header

-- loop through  user databases
DECLARE ct CURSOR FOR 
SELECT d.name FROM sys.databases d
WHERE 1 = 1

-- if All specified then process all user database otherwise only if name matches to @SourceDatabase
AND (d.name = @SourceDatabase OR @SourceDatabase = 'All') 

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
FETCH NEXT FROM ct INTO @SourceDatabase

WHILE @@FETCH_STATUS = 0
BEGIN
    
DECLARE @DatabaseSnapshot sysname = @SourceDatabase + '_' + @SnashotSuffix;
DECLARE @sql NVARCHAR(MAX) = '';



-- if snapshot already exists and it is allowed to drop it:	
IF @DropIfExists = 1 AND EXISTS (
	SELECT * FROM sys.databases snp
	JOIN sys.databases db ON snp.source_database_id = db.database_id
	WHERE snp.name = @DatabaseSnapshot AND db.name = @SourceDatabase
)
BEGIN
   
    SET @sql = N'DROP DATABASE '+QUOTENAME(@DatabaseSnapshot);

	PRINT 
'Executing SQL: ----------------------------------------------
'  + @sql + '	
-------------------------------------------------------------
	'

    EXEC sp_executesql @sql;
END;

-- if snapshot already exists and it is not allowed to drop it, just printing a message
ELSE IF EXISTS (
	SELECT * FROM sys.databases snp
	JOIN sys.databases db ON snp.source_database_id = db.database_id
	WHERE snp.name = @DatabaseSnapshot AND db.name = @SourceDatabase
)
BEGIN
    PRINT 'Snapshot ' + QUOTENAME(@DatabaseSnapshot) + ' already created on database ' + QUOTENAME(@SourceDatabase )
	
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
                  SELECT database_id FROM sys.databases WHERE name = @SourceDatabase
              )
              AND type = 0 -- ROWS
    )
    SELECT @sql = @sql + N'(NAME = ' + QUOTENAME(name) + N', FILENAME =''' + physical_name + N'.'+@SnashotSuffix+'''),
 '
    FROM cte;

    SET @sql = SUBSTRING(@sql, 1, LEN(@sql) - 3);

    SET @sql = N'CREATE DATABASE ' + QUOTENAME(@DatabaseSnapshot) + N' ON
 ' + @sql + N'
 AS SNAPSHOT OF ' + QUOTENAME(@SourceDatabase) + N';';
    
	PRINT 
'Executing SQL: ----------------------------------------------
'  + @sql + '	
-------------------------------------------------------------
	'

	
	EXEC sp_executesql @sql;




	EndOfCycle:
	FETCH NEXT FROM ct INTO @SourceDatabase
END


CLOSE ct
DEALLOCATE ct
	

	GO
    
