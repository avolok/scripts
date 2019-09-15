SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('[dbo].[uspRefreshDB]') IS NULL
  EXEC ('CREATE PROCEDURE [dbo].[uspRefreshDB] AS RETURN 0;');
GO


ALTER   PROC [dbo].[uspRefreshDB]
-- Database to restore
@dbName sysname,
-- Directory where full backups stored
@FullBackupDir NVARCHAR(500) = '\\BackupNAS\sql_backups\Regular\Full\',
-- Directory where diff backups stored
@DiffBackupDir NVARCHAR(500) = '\\BackupNAS\sql_backups\Regular\Diff\'

AS 

----------------------------------------------------------------------------------------------------
  --// Source:  https://avolok.github.io                                                          //--  
  --// GitHub:  https://github.com/avolok/scripts                                                 //--
  --// Version: 2019-09-15                                                                        //--
----------------------------------------------------------------------------------------------------

SET NOCOUNT ON 

-- 1 - Variable declaration 

DECLARE @cmd NVARCHAR(4000) 
DECLARE @fileList TABLE (backupFile NVARCHAR(255)) 
DECLARE @lastFullBackup NVARCHAR(500) 
DECLARE @lastDiffBackup NVARCHAR(500) 
DECLARE @backupFile NVARCHAR(500) 
DECLARE @commandDecored NVARCHAR(500)

DECLARE @commandList TABLE
(
	CommandID INT IDENTITY PRIMARY KEY
,	CommandText NVARCHAR(max)
,	CommandStatus INT 
)

-- 2 - Check if the feature XP_CMDSHELL is enabled
IF NOT (
SELECT CONVERT(INT, ISNULL(value, value_in_use)) AS config_value
FROM  sys.configurations
WHERE  name = 'xp_cmdshell' ) = 1 
BEGIN
    RAISERROR ('The feature [xp_cmdshell] is not enabled. It is required to run an automated restore. Terminating...', 16,1)
	RETURN;
END



-- 3 - get list of files 
-- full
--SET @DiffBackupDir = '\\backupshare\sql_backups\Regular\Full\NLC1DWHSQLCLS1\' 

SET @cmd = 'DIR /b "' + @FullBackupDir + '"'

INSERT INTO @fileList(backupFile) 
EXEC master.sys.xp_cmdshell @cmd 


-- 4 - Find latest full backup 
SELECT @lastFullBackup = MAX(backupFile)  
FROM @fileList  
WHERE backupFile LIKE '%.BAK'  AND backupFile LIKE '%[_]'+ @dbName + '[_]full%' 



IF (@lastFullBackup IS NULL )
BEGIN    
	PRINT CONCAT('No backup found for database: [', @dbName, ']. Terminating...')
	RETURN
END
ELSE
BEGIN
    PRINT CONCAT('Restoring database: ', QUOTENAME(@dbName), '. 
Full backup to be restored: ', @lastFullBackup, '
')
END



IF DB_ID(@dbName) IS NOT NULL AND   DATABASEPROPERTYEX(@dbName, 'Status') = 'ONLINE'
BEGIN
	SET @cmd = CONCAT('ALTER DATABASE   ', QUOTENAME(@dbName), ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE' ) 
    INSERT INTO @commandList (CommandText  )  VALUES  ( @cmd )
END





SET @cmd = 'RESTORE DATABASE [' + @dbName + '] FROM DISK = '''  
       + @FullBackupDir + @lastFullBackup + ''' WITH NORECOVERY, REPLACE, STATS=20' 


INSERT INTO @commandList (CommandText  )  VALUES  ( @cmd )



-- 4 - Find latest diff backup 

-- clean the filelist
delete @fileList


SET @cmd = 'DIR /b "' + @DiffBackupDir + '"'

INSERT INTO @fileList(backupFile) 
EXEC master.sys.xp_cmdshell @cmd 

SELECT @lastDiffBackup = MAX(backupFile)  
FROM @fileList  
WHERE backupFile LIKE '%.BAK'  
   AND backupFile LIKE '%[_]'+ @dbName + '[_]Diff%' 
   

-- check to make sure there is a diff backup 
IF @lastDiffBackup IS NOT NULL 
BEGIN 
   SET @cmd = 'RESTORE DATABASE [' + @dbName + '] FROM DISK = '''  
       + @DiffBackupDir + @lastDiffBackup + ''' WITH NORECOVERY, STATS=20' 

   INSERT INTO @commandList (CommandText  )  VALUES  ( @cmd )

   SET @lastFullBackup = @lastDiffBackup 

    PRINT CONCAT('Diff backup to be restored: ', @lastDiffBackup, '




')


END 




-- 6 - put database in online state 
SET @cmd = 'RESTORE DATABASE [' + @dbName + '] WITH RECOVERY' 

INSERT INTO @commandList (CommandText  )  VALUES  ( @cmd )

-- 7 - execute the script, command by command


DECLARE ct CURSOR FOR SELECT CommandText, CONCAT('Command ', CommandID, ': ', CommandText, '

') FROM @commandList ORDER BY CommandID

OPEN ct

FETCH NEXT FROM ct INTO @cmd, @commandDecored

WHILE @@FETCH_STATUS = 0
BEGIN
    --- printing immidiatelly
	RAISERROR ( @commandDecored , 10, 1) WITH NOWAIT
	

	EXEC (@cmd)

	RAISERROR ( '--------------------------------------
	' , 10, 1) WITH NOWAIT

	FETCH NEXT FROM ct INTO @cmd, @commandDecored
END

CLOSE ct
DEALLOCATE ct
