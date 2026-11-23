-- error: synonyms for a missing concept or language, or blank
SELECT s.concept_id, s.concept_synonym_name, s.language_concept_id FROM @delta.concept_synonym_delta s
WHERE s.project_id = @project
  AND (trim(s.concept_synonym_name) = ''
    OR NOT EXISTS (SELECT 1 FROM @views.concept c WHERE c.concept_id = s.concept_id)
    OR NOT EXISTS (SELECT 1 FROM @views.concept c WHERE c.concept_id = s.language_concept_id))
