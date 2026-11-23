-- error: vocabulary, domain, class or relationship rows pointing at a missing concept, or a relationship whose reverse is missing
SELECT 'vocabulary' AS tbl, vocabulary_id AS id FROM @delta.vocabulary_delta d WHERE project_id = @project
  AND NOT EXISTS (SELECT 1 FROM @views.concept c WHERE c.concept_id = d.vocabulary_concept_id)
UNION ALL SELECT 'domain', domain_id FROM @delta.domain_delta d WHERE project_id = @project
  AND NOT EXISTS (SELECT 1 FROM @views.concept c WHERE c.concept_id = d.domain_concept_id)
UNION ALL SELECT 'concept_class', concept_class_id FROM @delta.concept_class_delta d WHERE project_id = @project
  AND NOT EXISTS (SELECT 1 FROM @views.concept c WHERE c.concept_id = d.concept_class_concept_id)
UNION ALL SELECT 'relationship', relationship_id FROM @delta.relationship_delta d WHERE project_id = @project
  AND (NOT EXISTS (SELECT 1 FROM @views.concept c WHERE c.concept_id = d.relationship_concept_id)
    OR NOT EXISTS (SELECT 1 FROM @views.relationship r WHERE r.relationship_id = d.reverse_relationship_id
       AND r.reverse_relationship_id = d.relationship_id))
