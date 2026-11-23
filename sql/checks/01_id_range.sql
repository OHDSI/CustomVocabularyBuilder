-- error: custom ids outside the project's reserved range, or colliding with another project or the core vocabulary
SELECT 'concept' AS tbl, d.concept_id AS id FROM @delta.concept_delta d JOIN @delta.project r USING (project_id)
 WHERE d.project_id = @project AND d.concept_id NOT BETWEEN r.id_start AND r.id_end - 1
UNION ALL SELECT 'vocabulary', d.vocabulary_concept_id FROM @delta.vocabulary_delta d JOIN @delta.project r USING (project_id)
 WHERE d.project_id = @project AND d.vocabulary_concept_id NOT BETWEEN r.id_start AND r.id_end - 1
UNION ALL SELECT 'domain', d.domain_concept_id FROM @delta.domain_delta d JOIN @delta.project r USING (project_id)
 WHERE d.project_id = @project AND d.domain_concept_id NOT BETWEEN r.id_start AND r.id_end - 1 AND d.domain_concept_id <> 0
UNION ALL SELECT 'relationship', d.relationship_concept_id FROM @delta.relationship_delta d JOIN @delta.project r USING (project_id)
 WHERE d.project_id = @project AND d.relationship_concept_id NOT BETWEEN r.id_start AND r.id_end - 1
UNION ALL SELECT 'core collision', d.concept_id FROM @delta.concept_delta d JOIN @core.concept c USING (concept_id)
 WHERE d.project_id = @project
UNION ALL SELECT 'overlapping project ' || b.project_id, a.id_start FROM @delta.project a JOIN @delta.project b
   ON a.project_id < b.project_id AND int4range(a.id_start, a.id_end) && int4range(b.id_start, b.id_end)
 WHERE @project IN (a.project_id, b.project_id)
