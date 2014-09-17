USE YOUR_DATABASE_NAME
GO

-- Migrate columns NTEXT -> NVARCHAR(MAX)

DECLARE @alterColumns NVARCHAR(MAX) = '';
SELECT  @alterColumns = @alterColumns
	+'ALTER TABLE '
	+ QUOTENAME(OBJECT_SCHEMA_NAME(c.object_id)) + '.' + QUOTENAME(OBJECT_NAME(c.object_id))
	+ ' ALTER COLUMN '
	+ QUOTENAME(c.Name)
	+' NVARCHAR(MAX) '
	+ CASE WHEN c.is_nullable = 1 THEN 'NOT' ELSE '' END + ' NULL;'
	+ CHAR(13) + 'GO' + CHAR(13)
	+ 'UPDATE '
	+ QUOTENAME(OBJECT_SCHEMA_NAME(c.object_id)) + '.' + QUOTENAME(OBJECT_NAME(c.object_id))
	+ ' SET '
	+ QUOTENAME(c.Name)
	+ ' = '
	+ QUOTENAME(c.Name)
	+ ';' + CHAR(13) + 'GO' + CHAR(13) + CHAR(13)
FROM    sys.columns AS c
INNER JOIN sys.objects AS o
ON c.object_id = o.object_id
WHERE   o.type = 'U' AND c.system_type_id = 99; --NTEXT

PRINT @alterColumns;

--EXECUTE sp_executesql @alterColumns;
GO

-- Update VIEW metadata

DECLARE @updateViews NVARCHAR(MAX) = '';
SELECT @updateViews = @updateViews
	+ 'EXECUTE sp_refreshview '
	+ QUOTENAME(OBJECT_SCHEMA_NAME(o.object_id)) + '.' + QUOTENAME(OBJECT_NAME(o.object_id))
	+ ';' + CHAR(13)
FROM sys.objects AS o
WHERE o.type = 'V'

PRINT @updateViews;

--EXECUTE sp_executesql @updateViews;
GO
