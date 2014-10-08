/*

	T-SQL script to convert all NTEXT columns in a the specified list of
	SQL Server databases to NVARCHAR(MAX).

	Copyright © 2014 Bart Read
	http://www.bartread.com/

*/

-- Set this to 0 to actually run commands, 1 to only print them.
DECLARE @printCommandsOnly BIT = 1;

/*
	List of databases.
*/
DECLARE @Databases NVARCHAR(MAX)
SET @Databases = '__YOUR_COMMA_DELIMITED_LIST_OF_DATABASES__'


SET NOCOUNT ON;

DECLARE @Match TABLE (
	[DatabaseName] SYSNAME
)

--	90% of the code in this function courtesy of Ola Hallengren.
SET @Databases = REPLACE(@Databases, ', ', ',');

DECLARE @ErrorMessage nvarchar(max);
DECLARE @Error INT;

DECLARE @tmpDatabases TABLE (ID int IDENTITY,
							DatabaseName nvarchar(max),
							DatabaseNameFS nvarchar(max),
							DatabaseType nvarchar(max),
							Selected bit,
							Completed bit,
							PRIMARY KEY(Selected, Completed, ID));

DECLARE @SelectedDatabases TABLE (DatabaseName nvarchar(max),
								DatabaseType nvarchar(max),
								Selected bit);

WITH Databases1 (StartPosition, EndPosition, DatabaseItem) AS
(
SELECT 1 AS StartPosition,
		ISNULL(NULLIF(CHARINDEX(',', @Databases, 1), 0), LEN(@Databases) + 1) AS EndPosition,
		SUBSTRING(@Databases, 1, ISNULL(NULLIF(CHARINDEX(',', @Databases, 1), 0), LEN(@Databases) + 1) - 1) AS DatabaseItem
WHERE @Databases IS NOT NULL
UNION ALL
SELECT CAST(EndPosition AS int) + 1 AS StartPosition,
		ISNULL(NULLIF(CHARINDEX(',', @Databases, EndPosition + 1), 0), LEN(@Databases) + 1) AS EndPosition,
		SUBSTRING(@Databases, EndPosition + 1, ISNULL(NULLIF(CHARINDEX(',', @Databases, EndPosition + 1), 0), LEN(@Databases) + 1) - EndPosition - 1) AS DatabaseItem
FROM Databases1
WHERE EndPosition < LEN(@Databases) + 1
),
Databases2 (DatabaseItem, Selected) AS
(
SELECT CASE WHEN DatabaseItem LIKE '-%' THEN RIGHT(DatabaseItem,LEN(DatabaseItem) - 1) ELSE DatabaseItem END AS DatabaseItem,
		CASE WHEN DatabaseItem LIKE '-%' THEN 0 ELSE 1 END AS Selected
FROM Databases1
),
Databases3 (DatabaseItem, DatabaseType, Selected) AS
(
SELECT CASE WHEN DatabaseItem IN('ALL_DATABASES','SYSTEM_DATABASES','USER_DATABASES') THEN '%' ELSE DatabaseItem END AS DatabaseItem,
		CASE WHEN DatabaseItem = 'SYSTEM_DATABASES' THEN 'S' WHEN DatabaseItem = 'USER_DATABASES' THEN 'U' ELSE NULL END AS DatabaseType,
		Selected
FROM Databases2
),
Databases4 (DatabaseName, DatabaseType, Selected) AS
(
SELECT CASE WHEN LEFT(DatabaseItem,1) = '[' AND RIGHT(DatabaseItem,1) = ']' THEN PARSENAME(DatabaseItem,1) ELSE DatabaseItem END AS DatabaseItem,
		DatabaseType,
		Selected
FROM Databases3
)
INSERT INTO @SelectedDatabases (DatabaseName, DatabaseType, Selected)
SELECT DatabaseName,
		DatabaseType,
		Selected
FROM Databases4
OPTION (MAXRECURSION 0);

INSERT INTO @tmpDatabases (DatabaseName, DatabaseType, Selected, Completed)
SELECT [name] AS DatabaseName,
		CASE WHEN name IN('master','msdb','model') THEN 'S' ELSE 'U' END AS DatabaseType,
		0 AS Selected,
		0 AS Completed
FROM sys.databases
WHERE [name] <> 'tempdb'
AND source_database_id IS NULL
ORDER BY [name] ASC;

UPDATE tmpDatabases
SET tmpDatabases.Selected = SelectedDatabases.Selected
FROM @tmpDatabases tmpDatabases
INNER JOIN @SelectedDatabases SelectedDatabases
ON tmpDatabases.DatabaseName LIKE REPLACE(SelectedDatabases.DatabaseName,'_','[_]')
AND (tmpDatabases.DatabaseType = SelectedDatabases.DatabaseType OR SelectedDatabases.DatabaseType IS NULL)
WHERE SelectedDatabases.Selected = 1;

UPDATE tmpDatabases
SET tmpDatabases.Selected = SelectedDatabases.Selected
FROM @tmpDatabases tmpDatabases
INNER JOIN @SelectedDatabases SelectedDatabases
ON tmpDatabases.DatabaseName LIKE REPLACE(SelectedDatabases.DatabaseName,'_','[_]')
AND (tmpDatabases.DatabaseType = SelectedDatabases.DatabaseType OR SelectedDatabases.DatabaseType IS NULL)
WHERE SelectedDatabases.Selected = 0;

INSERT INTO @Match ( DatabaseName )
	SELECT DatabaseName
	FROM @tmpDatabases
	WHERE Selected = 1
	AND DatabaseName <> ''
	AND DatabaseName IS NOT NULL;



-- Migrate columns NTEXT -> NVARCHAR(MAX)

USE __DATABASE_NAME__;

DECLARE @object_id INT,
		@columnName SYSNAME,
		@isNullable BIT;

DECLARE @command NVARCHAR(MAX);

DECLARE @ntextColumnInfo TABLE (
	object_id INT,
	ColumnName SYSNAME,
	IsNullable BIT
);

INSERT INTO @ntextColumnInfo ( object_id, ColumnName, IsNullable )
	SELECT  c.object_id, c.name, c.is_nullable
	FROM    sys.columns AS c
	INNER JOIN sys.objects AS o
	ON c.object_id = o.object_id
	WHERE   o.type = 'U' AND c.system_type_id = 99;

DECLARE col_cursor CURSOR FAST_FORWARD FOR
	SELECT object_id, ColumnName, IsNullable FROM @ntextColumnInfo;

OPEN col_cursor;
FETCH NEXT FROM col_cursor INTO @object_id, @columnName, @isNullable;

WHILE @@FETCH_STATUS = 0
BEGIN
	SELECT @command =
		'ALTER TABLE '
		+ QUOTENAME(OBJECT_SCHEMA_NAME(@object_id))
			+ '.' + QUOTENAME(OBJECT_NAME(@object_id))
		+ ' ALTER COLUMN '
		+ QUOTENAME(@columnName)
		+' NVARCHAR(MAX) '
		+ CASE
			WHEN @isNullable = 1 THEN ''
			ELSE 'NOT'
		  END
		+ ' NULL;';
		
	PRINT @command;
	IF @printCommandsOnly = 0
	BEGIN
		EXECUTE sp_executesql @command;
	END

	SELECT @command =
		'UPDATE '
		+ QUOTENAME(OBJECT_SCHEMA_NAME(@object_id))
			+ '.' + QUOTENAME(OBJECT_NAME(@object_id))
		+ ' SET '
		+ QUOTENAME(@columnName)
		+ ' = '
		+ QUOTENAME(@columnName)
		+ ';'

	PRINT @command;
	IF @printCommandsOnly = 0
	BEGIN
		EXECUTE sp_executesql @command;
	END

	FETCH NEXT FROM col_cursor INTO @object_id, @columnName, @isNullable;
END

CLOSE col_cursor;
DEALLOCATE col_cursor;

-- Now refresh the view metadata for all the views in the database
-- (We may not need to do them all but it won't hurt.)

DECLARE @viewObjectIds TABLE (
	object_id INT
);

INSERT INTO @viewObjectIds
	SELECT o.object_id
	FROM sys.objects AS o
	WHERE o.type = 'V';

DECLARE view_cursor CURSOR FAST_FORWARD FOR
	SELECT object_id FROM @viewObjectIds;

OPEN view_cursor;
FETCH NEXT FROM view_cursor INTO @object_id;

WHILE @@FETCH_STATUS = 0
BEGIN
	SELECT @command =
		'EXECUTE sp_refreshview '''
		+ QUOTENAME(OBJECT_SCHEMA_NAME(@object_id)) + '.' + QUOTENAME(OBJECT_NAME(@object_id))
		+ ''';';
		
	PRINT @command;

	IF @printCommandsOnly = 0
	BEGIN
		EXECUTE sp_executesql @command;
	END

	FETCH NEXT FROM view_cursor INTO @object_id;
END

CLOSE view_cursor;
DEALLOCATE view_cursor;
GO
