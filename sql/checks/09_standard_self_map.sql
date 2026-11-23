-- error: valid standard custom concept without a self 'Maps to'
SELECT c.concept_id, c.concept_code FROM @delta.concept_delta c
WHERE c.project_id = @project AND c.standard_concept = 'S' AND c.invalid_reason IS NULL AND c.domain_id <> 'Metadata'
  AND NOT EXISTS (SELECT 1 FROM @delta.concept_relationship_delta r WHERE r.concept_id_1 = c.concept_id
    AND r.concept_id_2 = c.concept_id AND r.relationship_id = 'Maps to' AND r.invalid_reason IS NULL)
