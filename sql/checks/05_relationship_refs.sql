-- error: relationships whose concepts or relationship_id do not exist
SELECT r.concept_id_1, r.concept_id_2, r.relationship_id
FROM @delta.concept_relationship_delta r
WHERE r.project_id = @project
  AND (NOT EXISTS (SELECT 1 FROM @views.concept c WHERE c.concept_id = r.concept_id_1)
    OR NOT EXISTS (SELECT 1 FROM @views.concept c WHERE c.concept_id = r.concept_id_2)
    OR NOT EXISTS (SELECT 1 FROM @views.relationship x WHERE x.relationship_id = r.relationship_id))
