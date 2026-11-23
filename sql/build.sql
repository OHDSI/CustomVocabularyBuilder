DROP TABLE IF EXISTS pg_temp.src, pg_temp.tgt, pg_temp.src_ok, pg_temp.src_reject, pg_temp.cn, pg_temp.ex, pg_temp.keys, pg_temp.want_s2c, pg_temp.want_rel, pg_temp.want_anc, pg_temp.want_syn, pg_temp.pc, pg_temp.custom, pg_temp.up, pg_temp.up_core, pg_temp.core_anc, pg_temp.summary, pg_temp.abort, pg_temp.id_base, pg_temp.old_concept, pg_temp.old_rel;
CREATE TEMP TABLE summary (step text, n bigint);
CREATE TEMP TABLE abort (reason text);
CREATE TEMP TABLE old_concept AS SELECT concept_id, concept_code, concept_name, domain_id, concept_class_id, invalid_reason
  FROM @delta.concept_delta WHERE project_id = @project;
CREATE TEMP TABLE old_rel AS SELECT concept_id_1, concept_id_2, relationship_id
  FROM @delta.concept_relationship_delta WHERE project_id = @project AND invalid_reason IS NULL;

-- vocabulary bootstrap
CREATE TEMP TABLE new_vocab AS
SELECT r.id_end - 1 AS concept_id FROM @delta.project r
WHERE r.project_id = @project AND NOT EXISTS (SELECT 1 FROM @delta.vocabulary_delta
  WHERE project_id = @project AND vocabulary_id = (SELECT value FROM cfg WHERE ckey = 'vocabulary'));
INSERT INTO @delta.concept_delta
SELECT @project, concept_id, (SELECT value FROM cfg WHERE ckey = 'vocabulary_name'), 'Metadata', 'Vocabulary', 'Vocabulary', 'S',
       'OMOP generated', current_date, '2099-12-31', NULL FROM new_vocab;
INSERT INTO @delta.vocabulary_delta
SELECT @project, (SELECT value FROM cfg WHERE ckey = 'vocabulary'), (SELECT value FROM cfg WHERE ckey = 'vocabulary_name'), 'OMOP generated',
       current_date::text, concept_id FROM new_vocab;
DROP TABLE new_vocab;

-- staged source rows
ANALYZE src_raw;
CREATE TEMP TABLE tgt AS
SELECT concept_id, domain_id, concept_code, vocabulary_id FROM @views.concept
WHERE concept_id IN (SELECT trim(target_concept_id)::integer FROM src_raw WHERE trim(target_concept_id) ~ '^[1-9][0-9]*$');
ANALYZE tgt;
CREATE TEMP TABLE src AS
WITH raw AS (
  SELECT ord,
    CASE WHEN length(trim(source_code)) <= 50 THEN nullif(trim(source_code), '')
         ELSE left(trim(source_code), 39) || '_' || substr(md5(upper(trim(source_code))), 1, 10) END AS code,
    length(trim(source_code)) > 50 AS shortened,
    CASE WHEN trim(source_concept_id) ~ '^[1-9][0-9]*$' THEN trim(source_concept_id)::integer END AS sheet_id,
    CASE WHEN (SELECT value FROM cfg WHERE ckey = 'force_vocabulary') = 'TRUE'
         THEN (SELECT value FROM cfg WHERE ckey = 'vocabulary')
         ELSE coalesce(nullif(trim(source_vocabulary_id), ''), (SELECT value FROM cfg WHERE ckey = 'vocabulary')) END AS vocabulary_id,
    nullif(trim(source_code_set), '') AS code_set,
    nullif(trim(source_domain), '') AS domain_id,
    nullif(trim(source_concept_class_id), '') AS class_id,
    nullif(trim(source_description), '') AS name,
    nullif(nullif(trim(source_description_synonym), ''), '?') AS synonym,
    nullif(trim(relationship_id), '') AS rel,
    lower(nullif(trim(predicate_id), '')) AS predicate,
    CASE WHEN trim(target_concept_id) ~ '^[1-9][0-9]*$' THEN trim(target_concept_id)::integer END AS target_id,
    CASE WHEN trim(confidence) ~ '^[0-9.]+$' THEN trim(confidence)::float END AS confidence,
    nullif(trim(author_label), '') AS author, nullif(trim(reviewer_label), '') AS reviewer,
    nullif(trim(mapping_justification), '') AS justification,
    nullif(trim(mapping_tool), '') AS tool, nullif(trim(mapping_tool_version), '') AS tool_version
  FROM src_raw)
SELECT raw.*, upper(code) AS ckey, t.domain_id AS target_domain, t.concept_code AS target_code,
  t.vocabulary_id AS target_vocabulary,
  CASE WHEN target_id IS NULL THEN NULL ELSE coalesce(rel, CASE predicate
    WHEN 'skos:exactmatch' THEN 'Maps to' WHEN 'skos:closematch' THEN 'Maps to'
    WHEN 'skos:broadmatch' THEN 'Is a' WHEN 'skos:narrowmatch' THEN 'Subsumes'
    WHEN 'skos:relatedmatch' THEN CASE t.domain_id WHEN 'Procedure' THEN 'Has asso proc'
      WHEN 'Condition' THEN 'Has asso finding' WHEN 'Measurement' THEN 'Has measurement'
      WHEN 'Observation' THEN 'Has relat context' WHEN 'Visit' THEN 'Has asso visit' END END) END AS rel_eff,
  (t.concept_id IS NOT NULL) AS target_found
FROM raw LEFT JOIN tgt t ON t.concept_id = raw.target_id;

CREATE TEMP TABLE src_reject AS
SELECT ord, code, CASE
    WHEN code IS NULL THEN 'blank code'
    WHEN name IS NULL THEN 'blank description'
    WHEN target_id IS NOT NULL AND NOT target_found THEN 'target concept not found'
    WHEN target_id IS NOT NULL AND rel_eff IS NULL THEN 'no relationship_id and no usable predicate'
    WHEN target_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM @views.relationship r WHERE r.relationship_id = src.rel_eff)
      THEN 'unknown relationship_id' END AS reason
FROM src;
DELETE FROM src_reject WHERE reason IS NULL;
INSERT INTO summary SELECT 'rejected: ' || reason, count(*) FROM src_reject GROUP BY reason;
INSERT INTO summary SELECT 'warning: codes over 50 characters shortened with hash suffix', count(*) FROM src WHERE shortened;

CREATE TEMP TABLE src_ok AS
SELECT DISTINCT ON (vocabulary_id, ckey, rel_eff, target_id) * FROM src
WHERE ord NOT IN (SELECT ord FROM src_reject) ORDER BY vocabulary_id, ckey, rel_eff, target_id, ord;

ANALYZE src_ok;

-- concepts
CREATE TEMP TABLE ex AS
SELECT DISTINCT ON (vocabulary_id, upper(trim(concept_code))) vocabulary_id, upper(trim(concept_code)) AS ckey,
       concept_id, standard_concept FROM @delta.concept_delta WHERE project_id = @project
ORDER BY vocabulary_id, upper(trim(concept_code)), concept_id;
ANALYZE ex;
CREATE TEMP TABLE cn AS
SELECT DISTINCT ON (s.vocabulary_id, s.ckey) s.vocabulary_id, s.ckey, s.code, left(s.name, 255) AS name,
  coalesce(s.domain_id, first_value(s.target_domain) OVER w) AS domain_id,
  coalesce(s.class_id, (SELECT m.class_id FROM class_map m WHERE m.code_set = s.code_set), 'Suppl Concept') AS class_id,
  max(s.synonym) OVER (PARTITION BY s.vocabulary_id, s.ckey) AS synonym,
  bool_or(s.rel_eff IN ('Maps to', 'Maps to value')) OVER (PARTITION BY s.vocabulary_id, s.ckey) AS maps,
  min(s.sheet_id) OVER (PARTITION BY s.vocabulary_id, s.ckey) AS sheet_id,
  e.concept_id, e.standard_concept AS old_flag
FROM src_ok s
LEFT JOIN ex e ON e.vocabulary_id = s.vocabulary_id AND e.ckey = s.ckey
WINDOW w AS (PARTITION BY s.vocabulary_id, s.ckey ORDER BY (s.target_domain IS NULL), s.ord)
ORDER BY s.vocabulary_id, s.ckey, s.ord;

UPDATE cn SET concept_id = d.concept_id, old_flag = d.standard_concept FROM @delta.concept_delta d
WHERE d.project_id = @project AND d.concept_id = cn.sheet_id AND d.vocabulary_id = cn.vocabulary_id;
CREATE TEMP TABLE keys AS SELECT DISTINCT vocabulary_id, ckey FROM src WHERE code IS NOT NULL;
ANALYZE cn;
ANALYZE keys;

CREATE TEMP TABLE id_base AS
SELECT coalesce(max(d.concept_id), r.id_start - 1) AS hi, r.id_end AS lim FROM @delta.project r
LEFT JOIN @delta.concept_delta d ON d.project_id = r.project_id AND d.domain_id <> 'Metadata'
 AND d.concept_id BETWEEN r.id_start AND r.id_end - 1
WHERE r.project_id = @project GROUP BY r.id_start, r.id_end;
UPDATE cn SET concept_id = (SELECT hi FROM id_base) + x.rn
FROM (SELECT vocabulary_id, ckey, row_number() OVER (ORDER BY vocabulary_id, ckey) AS rn FROM cn WHERE concept_id IS NULL) x
WHERE cn.vocabulary_id = x.vocabulary_id AND cn.ckey = x.ckey AND cn.concept_id IS NULL;
INSERT INTO abort SELECT 'id block exhausted' FROM id_base WHERE (SELECT max(concept_id) FROM cn) >= lim - 100;
ALTER TABLE cn ADD COLUMN is_new boolean;
UPDATE cn SET is_new = (old_flag IS NULL AND NOT EXISTS (SELECT 1 FROM @delta.concept_delta d WHERE d.concept_id = cn.concept_id));
ALTER TABLE cn ADD COLUMN std boolean;
UPDATE cn SET std = CASE WHEN is_new THEN NOT maps ELSE coalesce(old_flag = 'S', false) END;

WITH x AS (INSERT INTO @delta.concept_delta
  SELECT @project, concept_id, name, domain_id, vocabulary_id, class_id, CASE WHEN std THEN 'S' END, code,
         current_date, '2099-12-31', NULL FROM cn WHERE is_new RETURNING 1)
INSERT INTO summary SELECT 'concepts inserted', count(*) FROM x;

WITH x AS (UPDATE @delta.concept_delta d SET concept_name = cn.name, invalid_reason = NULL, valid_end_date = '2099-12-31'
  FROM cn WHERE d.concept_id = cn.concept_id AND NOT cn.is_new
   AND (d.concept_name IS DISTINCT FROM cn.name OR d.invalid_reason IS NOT NULL) RETURNING 1)
INSERT INTO summary SELECT 'concepts updated or reactivated', count(*) FROM x;

WITH x AS (UPDATE @delta.concept_delta d SET invalid_reason = 'D', valid_end_date = greatest(valid_start_date, current_date - 1)
  WHERE d.project_id = @project AND d.invalid_reason IS NULL AND d.domain_id <> 'Metadata'
    AND d.concept_id NOT IN (SELECT concept_id FROM cn WHERE concept_id IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM keys k WHERE k.vocabulary_id = d.vocabulary_id AND k.ckey = upper(trim(d.concept_code)))
  RETURNING 1)
INSERT INTO summary SELECT 'concepts deprecated', count(*) FROM x;

-- relationships
CREATE TEMP TABLE want_rel AS
WITH e AS (SELECT cn.concept_id AS c, s.target_id AS t, s.rel_eff AS rel FROM src_ok s
  JOIN cn USING (vocabulary_id, ckey) WHERE s.rel_eff IS NOT NULL)
SELECT c AS id1, t AS id2, rel AS rid FROM e
UNION SELECT e.t, e.c, r.reverse_relationship_id FROM e JOIN @views.relationship r ON r.relationship_id = e.rel
UNION SELECT concept_id, concept_id, 'Maps to' FROM cn WHERE std
UNION SELECT concept_id, concept_id, 'Mapped from' FROM cn WHERE std;

ANALYZE want_rel;
WITH x AS (INSERT INTO @delta.concept_relationship_delta
  SELECT @project, id1, id2, rid, current_date, '2099-12-31', NULL FROM want_rel w
  WHERE NOT EXISTS (SELECT 1 FROM @delta.concept_relationship_delta r
    WHERE r.concept_id_1 = w.id1 AND r.concept_id_2 = w.id2 AND r.relationship_id = w.rid) RETURNING 1)
INSERT INTO summary SELECT 'relationships inserted', count(*) FROM x;

WITH x AS (UPDATE @delta.concept_relationship_delta r SET invalid_reason = NULL, valid_end_date = '2099-12-31'
  FROM want_rel w WHERE r.concept_id_1 = w.id1 AND r.concept_id_2 = w.id2 AND r.relationship_id = w.rid
    AND r.invalid_reason IS NOT NULL RETURNING 1)
INSERT INTO summary SELECT 'relationships reactivated', count(*) FROM x;

WITH x AS (UPDATE @delta.concept_relationship_delta r SET invalid_reason = 'D', valid_end_date = greatest(valid_start_date, current_date - 1)
  WHERE r.project_id = @project AND r.invalid_reason IS NULL
    AND NOT EXISTS (SELECT 1 FROM want_rel w WHERE w.id1 = r.concept_id_1 AND w.id2 = r.concept_id_2 AND w.rid = r.relationship_id)
    AND NOT EXISTS (SELECT 1 FROM @delta.concept_delta m WHERE m.project_id = @project AND m.domain_id = 'Metadata'
                      AND m.concept_id IN (r.concept_id_1, r.concept_id_2))
  RETURNING 1)
INSERT INTO summary SELECT 'relationships deprecated', count(*) FROM x;

-- source_to_concept_map
CREATE TEMP TABLE want_s2c AS
SELECT left(c.concept_code, 50) AS source_code, c.concept_id AS source_concept_id, c.vocabulary_id AS source_vocabulary_id,
       left(c.concept_name, 255) AS descr, r.concept_id_2 AS target_concept_id, t.vocabulary_id AS target_vocabulary_id
FROM @delta.concept_relationship_delta r
JOIN @delta.concept_delta c ON c.concept_id = r.concept_id_1
JOIN @views.concept t ON t.concept_id = r.concept_id_2
WHERE r.project_id = @project AND r.relationship_id IN ('Maps to', 'Maps to value') AND r.invalid_reason IS NULL;

ANALYZE want_s2c;
WITH x AS (INSERT INTO @delta.source_to_concept_map_delta
  SELECT @project, source_code, source_concept_id, source_vocabulary_id, descr, target_concept_id, target_vocabulary_id,
         current_date, '2099-12-31', NULL FROM want_s2c w
  WHERE NOT EXISTS (SELECT 1 FROM @delta.source_to_concept_map_delta m WHERE m.project_id = @project
    AND m.source_concept_id = w.source_concept_id AND m.target_concept_id = w.target_concept_id AND m.invalid_reason IS NULL)
  RETURNING 1)
INSERT INTO summary SELECT 'source_to_concept_map inserted', count(*) FROM x;

WITH x AS (UPDATE @delta.source_to_concept_map_delta m SET invalid_reason = 'D', valid_end_date = greatest(valid_start_date, current_date - 1)
  WHERE m.project_id = @project AND m.invalid_reason IS NULL
    AND NOT EXISTS (SELECT 1 FROM want_s2c w WHERE w.source_concept_id = m.source_concept_id
      AND w.target_concept_id = m.target_concept_id) RETURNING 1)
INSERT INTO summary SELECT 'source_to_concept_map deprecated', count(*) FROM x;

-- synonyms
CREATE TEMP TABLE want_syn AS
SELECT DISTINCT cn.concept_id, trim(x) AS synonym FROM src_ok s JOIN cn USING (vocabulary_id, ckey),
  LATERAL regexp_split_to_table(s.synonym, '\s*\|\|\s*') AS x
WHERE s.synonym IS NOT NULL AND trim(x) NOT IN ('', '?');
WITH x AS (INSERT INTO @delta.concept_synonym_delta SELECT @project, concept_id, synonym, 4180186 FROM want_syn
  ON CONFLICT DO NOTHING RETURNING 1)
INSERT INTO summary SELECT 'synonyms inserted', count(*) FROM x;
WITH x AS (DELETE FROM @delta.concept_synonym_delta s
  WHERE s.project_id = @project AND s.language_concept_id = 4180186 AND s.concept_id IN (SELECT concept_id FROM cn)
    AND NOT EXISTS (SELECT 1 FROM want_syn w WHERE w.concept_id = s.concept_id AND w.synonym = s.concept_synonym_name)
  RETURNING 1)
INSERT INTO summary SELECT 'synonyms deleted', count(*) FROM x;

-- ancestors: custom standard concepts, their Is a paths (through core via concept_ancestor), and direct custom parents of core concepts
CREATE TEMP TABLE pc AS
SELECT concept_id_1 AS child, concept_id_2 AS parent FROM @delta.concept_relationship_delta
WHERE project_id = @project AND relationship_id = 'Is a' AND invalid_reason IS NULL;
CREATE TEMP TABLE custom AS SELECT concept_id FROM @delta.concept_delta WHERE project_id = @project;
CREATE TEMP TABLE up AS
WITH RECURSIVE up (c, x, mn, mx) AS (
  SELECT concept_id, concept_id, 0, 0 FROM @delta.concept_delta
   WHERE project_id = @project AND invalid_reason IS NULL AND domain_id <> 'Metadata'
    AND (standard_concept = 'S' OR concept_id IN (SELECT child FROM pc))
  UNION ALL SELECT up.c, pc.parent, up.mn + 1, up.mx + 1 FROM up JOIN pc ON pc.child = up.x WHERE up.mx < 30)
SELECT * FROM up;
CREATE TEMP TABLE up_core AS SELECT DISTINCT x FROM up WHERE x NOT IN (SELECT concept_id FROM custom);
CREATE TEMP TABLE core_anc AS SELECT ca.* FROM @core.concept_ancestor ca JOIN up_core ON ca.descendant_concept_id = up_core.x
  WHERE ca.ancestor_concept_id <> ca.descendant_concept_id;
CREATE TEMP TABLE want_anc AS
WITH allrows AS (
  SELECT x AS a, c AS d, mn, mx FROM up
  UNION ALL SELECT ca.ancestor_concept_id, up.c, up.mn + ca.min_levels_of_separation, up.mx + ca.max_levels_of_separation
    FROM up JOIN core_anc ca ON ca.descendant_concept_id = up.x
  UNION ALL SELECT up.x, pc.child, up.mn + 1, up.mx + 1 FROM up JOIN pc ON pc.parent = up.c
   WHERE pc.child NOT IN (SELECT concept_id FROM custom))
SELECT a AS ancestor_concept_id, d AS descendant_concept_id, min(mn) AS mn, max(mx) AS mx FROM allrows GROUP BY a, d;
ANALYZE want_anc;
WITH x AS (INSERT INTO @delta.concept_ancestor_delta
  SELECT @project, ancestor_concept_id, descendant_concept_id, mn, mx FROM want_anc w
  ON CONFLICT (ancestor_concept_id, descendant_concept_id) DO UPDATE
    SET min_levels_of_separation = EXCLUDED.min_levels_of_separation, max_levels_of_separation = EXCLUDED.max_levels_of_separation
  WHERE (@delta.concept_ancestor_delta.min_levels_of_separation, @delta.concept_ancestor_delta.max_levels_of_separation)
        IS DISTINCT FROM (EXCLUDED.min_levels_of_separation, EXCLUDED.max_levels_of_separation) RETURNING 1)
INSERT INTO summary SELECT 'ancestors inserted or updated', count(*) FROM x;
WITH x AS (DELETE FROM @delta.concept_ancestor_delta a WHERE a.project_id = @project AND NOT EXISTS (SELECT 1 FROM want_anc w
  WHERE w.ancestor_concept_id = a.ancestor_concept_id AND w.descendant_concept_id = a.descendant_concept_id) RETURNING 1)
INSERT INTO summary SELECT 'ancestors deleted', count(*) FROM x;

-- mapping metadata
WITH m AS (SELECT s.author, s.reviewer, s.confidence, s.predicate, s.justification, s.tool, s.tool_version,
    concat(s.code, '|| - ||', s.vocabulary_id, '|| - ||', s.target_code, '|| - ||', s.target_vocabulary) AS mcode
  FROM src_ok s WHERE s.target_id IS NOT NULL),
  x AS (INSERT INTO @delta.mapping_metadata_delta
  SELECT @project, (SELECT coalesce(max(mapping_concept_id), 0) FROM @delta.mapping_metadata_delta WHERE project_id = @project)
         + row_number() OVER (ORDER BY mcode), mcode, confidence, predicate,
         coalesce(justification, 'semapv:ManualMappingCuration'), (SELECT value FROM cfg WHERE ckey = 'provider'), NULL, author, NULL,
         reviewer, coalesce(tool, 'Google Sheet Workflow'), tool_version
  FROM (SELECT DISTINCT ON (mcode) * FROM m ORDER BY mcode) m
  WHERE NOT EXISTS (SELECT 1 FROM @delta.mapping_metadata_delta d WHERE d.project_id = @project AND d.mapping_concept_code = m.mcode)
  RETURNING 1)
INSERT INTO summary SELECT 'mapping_metadata inserted', count(*) FROM x;

UPDATE @delta.vocabulary_delta SET vocabulary_version = current_date::text
WHERE project_id = @project AND vocabulary_id = (SELECT value FROM cfg WHERE ckey = 'vocabulary');

-- guard against a bad or empty source wiping out the delta
INSERT INTO abort
SELECT 'build would deprecate ' || c.n || ' concepts and ' || r.n || ' relationships (limit ' || l.v || ' of existing)'
FROM (SELECT coalesce(sum(n), 0) AS n FROM summary WHERE step = 'concepts deprecated') c,
     (SELECT coalesce(sum(n), 0) AS n FROM summary WHERE step = 'relationships deprecated') r,
     (SELECT value::numeric AS v FROM cfg WHERE ckey = 'max_deprecate') l
WHERE c.n > l.v * (SELECT greatest(count(*), 1) FROM @delta.concept_delta WHERE project_id = @project)
   OR r.n > l.v * (SELECT greatest(count(*), 1) FROM @delta.concept_relationship_delta WHERE project_id = @project);
