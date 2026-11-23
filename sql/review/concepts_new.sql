SELECT d.concept_id, d.concept_code, d.concept_name, d.domain_id, d.concept_class_id, d.vocabulary_id
FROM @delta.concept_delta d WHERE d.project_id = @project AND d.concept_id NOT IN (SELECT concept_id FROM old_concept)
ORDER BY d.concept_id
