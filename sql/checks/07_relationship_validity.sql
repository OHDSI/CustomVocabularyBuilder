-- error: invalid dates or validity/invalid_reason mismatches on relationships
SELECT concept_id_1, concept_id_2, relationship_id, valid_start_date, valid_end_date, invalid_reason
FROM @delta.concept_relationship_delta WHERE project_id = @project
  AND (valid_start_date > valid_end_date OR invalid_reason NOT IN ('D', 'U')
    OR (invalid_reason IS NULL AND valid_end_date < current_date)
    OR (invalid_reason IS NOT NULL AND valid_end_date > current_date))
