-- error: duplicate (vocabulary_id, concept_code) after trimming and case folding
SELECT vocabulary_id, upper(trim(concept_code)) AS code, count(*) AS n, array_agg(concept_id) AS ids
FROM @delta.concept_delta WHERE project_id = @project
GROUP BY 1, 2 HAVING count(*) > 1
