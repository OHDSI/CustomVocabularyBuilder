SELECT o.concept_id, o.concept_code, o.concept_name AS old_name, cn.name AS sheet_name,
  o.domain_id AS old_domain, cn.domain_id AS sheet_domain, o.concept_class_id AS old_class, cn.class_id AS sheet_class,
  (o.concept_name IS DISTINCT FROM cn.name) AS name_applied, (o.invalid_reason IS NOT NULL) AS reactivated
FROM old_concept o JOIN cn ON cn.concept_id = o.concept_id
WHERE o.concept_name IS DISTINCT FROM cn.name OR o.domain_id IS DISTINCT FROM cn.domain_id
   OR o.concept_class_id IS DISTINCT FROM cn.class_id OR o.invalid_reason IS NOT NULL
ORDER BY o.concept_id
