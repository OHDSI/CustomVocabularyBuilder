-- error: malformed ancestor rows, or a valid 'Is a' edge with no ancestor row
SELECT 'bad row' AS issue, ancestor_concept_id AS a, descendant_concept_id AS d FROM @delta.concept_ancestor_delta x
WHERE project_id = @project AND (min_levels_of_separation < 0 OR min_levels_of_separation > max_levels_of_separation
  OR NOT EXISTS (SELECT 1 FROM @views.concept c WHERE c.concept_id = x.ancestor_concept_id)
  OR NOT EXISTS (SELECT 1 FROM @views.concept c WHERE c.concept_id = x.descendant_concept_id))
UNION ALL
SELECT 'missing for Is a', r.concept_id_2, r.concept_id_1 FROM @delta.concept_relationship_delta r
WHERE r.project_id = @project AND r.relationship_id = 'Is a' AND r.invalid_reason IS NULL
  AND NOT EXISTS (SELECT 1 FROM @delta.concept_ancestor_delta x WHERE x.ancestor_concept_id = r.concept_id_2
    AND x.descendant_concept_id = r.concept_id_1)
