SELECT CASE WHEN to_regclass(format('@delta.%I', t.table_name || '_delta')) IS NULL
  THEN format('CREATE OR REPLACE VIEW @delta.%I AS SELECT * FROM @core.%I', @project || '_' || t.table_name, t.table_name)
  ELSE format('CREATE OR REPLACE VIEW @delta.%I AS SELECT %s FROM @core.%I UNION ALL SELECT %s FROM @delta.%I WHERE project_id = %L',
              @project || '_' || t.table_name, c.cols, t.table_name, c.cols, t.table_name || '_delta', @project) END AS stmt
FROM information_schema.tables t
LEFT JOIN LATERAL (SELECT string_agg(quote_ident(column_name), ',' ORDER BY ordinal_position) AS cols
                   FROM information_schema.columns WHERE table_schema = '@core' AND table_name = t.table_name) c ON true
WHERE t.table_schema = '@core' AND t.table_type = 'BASE TABLE'
  AND t.table_name NOT LIKE '%\_delta' AND t.table_name <> 'project'
