SELECT n.concept_id_1, c1.concept_code AS code_1, n.relationship_id, n.concept_id_2
FROM @delta.concept_relationship_delta n JOIN @delta.concept_delta c1 ON c1.concept_id = n.concept_id_1
WHERE n.project_id = @project AND n.invalid_reason IS NULL AND n.relationship_id NOT LIKE 'Mapped from' AND n.concept_id_1 <> n.concept_id_2
  AND NOT EXISTS (SELECT 1 FROM old_rel o WHERE o.concept_id_1 = n.concept_id_1 AND o.concept_id_2 = n.concept_id_2 AND o.relationship_id = n.relationship_id)
ORDER BY 1, 3, 4
