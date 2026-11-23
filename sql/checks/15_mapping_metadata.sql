-- warning: mapping metadata missing required SSSOM fields or with confidence outside [0, 1]
SELECT mapping_concept_id, mapping_concept_code, confidence, predicate_id, mapping_justification
FROM @delta.mapping_metadata_delta WHERE project_id = @project
  AND (confidence NOT BETWEEN 0 AND 1 OR predicate_id IS NULL OR mapping_justification IS NULL)
