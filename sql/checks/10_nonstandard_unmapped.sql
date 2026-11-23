-- warning: valid non-standard custom concept with no valid 'Maps to'
SELECT c.concept_id, c.concept_code, c.concept_name FROM @delta.concept_delta c
WHERE c.project_id = @project AND c.standard_concept IS NULL AND c.invalid_reason IS NULL
  AND NOT EXISTS (SELECT 1 FROM @delta.concept_relationship_delta r WHERE r.concept_id_1 = c.concept_id
    AND r.relationship_id = 'Maps to' AND r.invalid_reason IS NULL)
