SELECT format('INSERT INTO @delta.%I (project_id, %s) SELECT %L, %s FROM @stage s ON CONFLICT DO NOTHING',
              '@tbl', string_agg(quote_ident(t.column_name), ',' ORDER BY t.ordinal_position), @project,
              string_agg(format('s.%I::%s', t.column_name, t.data_type), ',' ORDER BY t.ordinal_position)) AS stmt
FROM information_schema.columns t
JOIN information_schema.columns s ON s.column_name = t.column_name AND s.table_name = '@stage' AND s.table_schema LIKE 'pg\_temp%'
WHERE t.table_schema = '@delta' AND t.table_name = '@tbl' AND t.column_name <> 'project_id'
