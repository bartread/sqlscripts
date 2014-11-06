/*

	T-SQL script to convert all large object columns in a SQL Server database:
	
	NTEXT -> NVARCHAR(MAX)
	TEXT -> VARCHAR(MAX)
	IMAGE -> VARBINARY(MAX)

	Copyright © 2014 Bart Read
	http://www.bartread.com/

*/

--USE __YOUR_DATABASE_NAME__
USE TestsDataCoDataKnackered
GO

SET NOCOUNT ON;

-- Set this to 0 to actually run commands, 1 to only print them.
DECLARE @printCommandsOnly BIT = 1;

DECLARE @typesToMigrate TABLE (
	[TypeName] SYSNAME
);

-- Columns of these types will be migrated.
-- Comment out any column types you do not want to migrate.
INSERT INTO @typesToMigrate ( TypeName )
VALUES
	( 'ntext' ),	-- Migrates to NVARCHAR(MAX)
	( 'text' ),		-- Migrates to VARCHAR(MAX)
	( 'image' );	-- Migrates to VARBINARY(MAX)

-- Migrate columns NTEXT -> NVARCHAR(MAX)

DECLARE @object_id INT,
		@columnName SYSNAME,
		@isNullable BIT,
		@typeName SYSNAME,
		@columnCount INT = 0,
		@targetDataType SYSNAME;

DECLARE @command NVARCHAR(MAX);

DECLARE @lobColumnInfo TABLE (
	object_id INT,
	ColumnName SYSNAME,
	IsNullable BIT,
	TypeName SYSNAME
);

INSERT  INTO @lobColumnInfo
        ( object_id,
          ColumnName,
          IsNullable,
		  TypeName
        )
        SELECT  c.object_id ,
                c.name ,
                c.is_nullable,
				t.name
        FROM    sys.columns AS c
                INNER JOIN sys.objects AS o
				ON c.object_id = o.object_id
				INNER JOIN sys.types AS t
				ON c.system_type_id = t.system_type_id
        WHERE   o.type = 'U'
                AND t.name IN (SELECT TypeName FROM @typesToMigrate);

DECLARE col_cursor CURSOR FAST_FORWARD
FOR
    SELECT  object_id ,
            ColumnName ,
            IsNullable,
			TypeName
    FROM    @lobColumnInfo;

OPEN col_cursor;

FETCH NEXT FROM col_cursor
	INTO @object_id, @columnName, @isNullable, @typeName;

WHILE @@FETCH_STATUS = 0
BEGIN

	--	Change column data type

	SET @targetDataType =	CASE @typeName
								WHEN 'ntext' THEN 'NVARCHAR(MAX)'
								WHEN 'text' THEN 'VARCHAR(MAX)'
								WHEN 'image' THEN 'VARBINARY(MAX)'
							END;

	SET @command = 'ALTER TABLE {SCHEMA}.{TABLE}
ALTER COLUMN {COLUMN} {DATATYPE} {BLANKORNOT}NULL;';
	SET @command =
		REPLACE(
		REPLACE(
		REPLACE(
		REPLACE(
		REPLACE(@command,
			'{SCHEMA}', QUOTENAME(OBJECT_SCHEMA_NAME(@object_id))),
			'{TABLE}', QUOTENAME(OBJECT_NAME(@object_id))),
			'{COLUMN}', QUOTENAME(@columnName)),
			'{BLANKORNOT}', CASE WHEN @isNullable = 1 THEN '' ELSE 'NOT ' END),
			'{DATATYPE}', @targetDataType);
		
	PRINT @command;
	IF @printCommandsOnly = 0
	BEGIN
		EXECUTE sp_executesql @command;
	END

	--	Update values in column to pull back into row

	SET @command = 'UPDATE {SCHEMA}.{TABLE} SET {COLUMN} = {COLUMN};';
	SET @command =
		REPLACE(
		REPLACE(
		REPLACE(@command,
			'{COLUMN}', QUOTENAME(@columnName)),
			'{TABLE}', QUOTENAME(OBJECT_NAME(@object_id))),
			'{SCHEMA}', QUOTENAME(OBJECT_SCHEMA_NAME(@object_id)));

	PRINT @command;
	IF @printCommandsOnly = 0
	BEGIN
		EXECUTE sp_executesql @command;
	END

	SET @columnCount = @columnCount + 1;

	FETCH NEXT FROM col_cursor
		INTO @object_id, @columnName, @isNullable, @typeName;
END

CLOSE col_cursor;
DEALLOCATE col_cursor;

-- Now refresh the view metadata for all the views in the database
-- (We may not need to do them all but it won't hurt.)

IF @columnCount > 0
BEGIN
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
		SET @command = 'EXECUTE sp_refreshview ''{SCHEMA}.{VIEW}'';';
		SET @command =
			REPLACE(
			REPLACE(@command,
				'{VIEW}', QUOTENAME(OBJECT_NAME(@object_id))),
				'{SCHEMA}', QUOTENAME(OBJECT_SCHEMA_NAME(@object_id)));
		
		PRINT @command;

		IF @printCommandsOnly = 0
		BEGIN
			EXECUTE sp_executesql @command;
		END

		FETCH NEXT FROM view_cursor INTO @object_id;
	END

	CLOSE view_cursor;
	DEALLOCATE view_cursor;
END
GO
