-- error: concepts referencing a missing domain, vocabulary or concept class
SELECT c.concept_id, c.domain_id, c.vocabulary_id, c.concept_class_id
FROM @delta.concept_delta c
WHERE c.project_id = @project
  AND (NOT EXISTS (SELECT 1 FROM @views.domain x WHERE x.domain_id = c.domain_id)
    OR NOT EXISTS (SELECT 1 FROM @views.vocabulary x WHERE x.vocabulary_id = c.vocabulary_id)
    OR NOT EXISTS (SELECT 1 FROM @views.concept_class x WHERE x.concept_class_id = c.concept_class_id))
