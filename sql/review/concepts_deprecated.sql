SELECT o.concept_id, o.concept_code, o.concept_name, o.domain_id, o.concept_class_id
FROM old_concept o JOIN @delta.concept_delta d ON d.concept_id = o.concept_id
WHERE o.invalid_reason IS NULL AND d.invalid_reason IS NOT NULL ORDER BY o.concept_id
