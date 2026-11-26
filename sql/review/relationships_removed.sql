SELECT o.concept_id_1, c1.concept_code AS code_1, o.relationship_id, o.concept_id_2
FROM old_rel o LEFT JOIN @views.concept c1 ON c1.concept_id = o.concept_id_1
WHERE true
  AND NOT EXISTS (SELECT 1 FROM @delta.concept_relationship_delta n WHERE n.project_id = @project AND n.invalid_reason IS NULL
    AND n.concept_id_1 = o.concept_id_1 AND n.concept_id_2 = o.concept_id_2 AND n.relationship_id = o.relationship_id)
ORDER BY 1, 3, 4
