-- error: relationship without its reverse row, or with validity differing from it
SELECT r.concept_id_1, r.concept_id_2, r.relationship_id, x.reverse_relationship_id
FROM @delta.concept_relationship_delta r
JOIN @views.relationship x USING (relationship_id)
LEFT JOIN @delta.concept_relationship_delta v ON v.concept_id_1 = r.concept_id_2 AND v.concept_id_2 = r.concept_id_1
 AND v.relationship_id = x.reverse_relationship_id
WHERE r.project_id = @project
  AND (v.concept_id_1 IS NULL OR v.invalid_reason IS DISTINCT FROM r.invalid_reason OR v.valid_end_date <> r.valid_end_date)
