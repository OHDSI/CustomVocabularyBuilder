-- error: invalid dates, flags or validity/invalid_reason mismatches on concepts
SELECT concept_id, standard_concept, valid_start_date, valid_end_date, invalid_reason
FROM @delta.concept_delta WHERE project_id = @project
  AND (valid_start_date > valid_end_date
    OR standard_concept NOT IN ('S', 'C')
    OR invalid_reason NOT IN ('D', 'U')
    OR (invalid_reason IS NULL AND valid_end_date < current_date)
    OR (invalid_reason IS NOT NULL AND valid_end_date > current_date)
    OR concept_name <> trim(concept_name) OR concept_name = '' OR concept_code = '')
