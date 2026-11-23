-- warning: valid source_to_concept_map row not backed by a valid 'Maps to' relationship
SELECT m.source_code, m.source_concept_id, m.target_concept_id FROM @delta.source_to_concept_map_delta m
WHERE m.project_id = @project AND m.invalid_reason IS NULL
  AND NOT EXISTS (SELECT 1 FROM @delta.concept_relationship_delta r WHERE r.concept_id_1 = m.source_concept_id
    AND r.concept_id_2 = m.target_concept_id AND r.relationship_id IN ('Maps to', 'Maps to value') AND r.invalid_reason IS NULL)
