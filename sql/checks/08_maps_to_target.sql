-- error: valid 'Maps to' pointing at a concept that is not standard and valid
SELECT r.concept_id_1, r.concept_id_2, t.standard_concept, t.invalid_reason
FROM @delta.concept_relationship_delta r JOIN @views.concept t ON t.concept_id = r.concept_id_2
WHERE r.project_id = @project AND r.relationship_id = 'Maps to' AND r.invalid_reason IS NULL
  AND (t.standard_concept IS DISTINCT FROM 'S' OR t.invalid_reason IS NOT NULL)
