CREATE TABLE IF NOT EXISTS @core.source_to_concept_map (
  source_code varchar(50) NOT NULL, source_concept_id integer NOT NULL, source_vocabulary_id varchar(20) NOT NULL,
  source_code_description varchar(255), target_concept_id integer NOT NULL, target_vocabulary_id varchar(20) NOT NULL,
  valid_start_date date NOT NULL, valid_end_date date NOT NULL, invalid_reason varchar(1));

CREATE TABLE IF NOT EXISTS @delta.project (
  project_id text PRIMARY KEY,
  id_start   integer NOT NULL,
  id_end     integer NOT NULL,
  CHECK (id_start < id_end)
);

CREATE TABLE IF NOT EXISTS @delta.concept_delta (
  project_id text NOT NULL REFERENCES @delta.project ON DELETE CASCADE, LIKE @core.concept,
  PRIMARY KEY (concept_id));
CREATE TABLE IF NOT EXISTS @delta.concept_relationship_delta (
  project_id text NOT NULL REFERENCES @delta.project ON DELETE CASCADE, LIKE @core.concept_relationship,
  PRIMARY KEY (concept_id_1, concept_id_2, relationship_id));
CREATE TABLE IF NOT EXISTS @delta.concept_ancestor_delta (
  project_id text NOT NULL REFERENCES @delta.project ON DELETE CASCADE, LIKE @core.concept_ancestor,
  PRIMARY KEY (ancestor_concept_id, descendant_concept_id));
CREATE TABLE IF NOT EXISTS @delta.concept_synonym_delta (
  project_id text NOT NULL REFERENCES @delta.project ON DELETE CASCADE, LIKE @core.concept_synonym,
  PRIMARY KEY (concept_id, concept_synonym_name, language_concept_id));
CREATE TABLE IF NOT EXISTS @delta.vocabulary_delta (
  project_id text NOT NULL REFERENCES @delta.project ON DELETE CASCADE, LIKE @core.vocabulary,
  PRIMARY KEY (project_id, vocabulary_id));
CREATE TABLE IF NOT EXISTS @delta.domain_delta (
  project_id text NOT NULL REFERENCES @delta.project ON DELETE CASCADE, LIKE @core.domain,
  PRIMARY KEY (project_id, domain_id));
CREATE TABLE IF NOT EXISTS @delta.concept_class_delta (
  project_id text NOT NULL REFERENCES @delta.project ON DELETE CASCADE, LIKE @core.concept_class,
  PRIMARY KEY (project_id, concept_class_id));
CREATE TABLE IF NOT EXISTS @delta.relationship_delta (
  project_id text NOT NULL REFERENCES @delta.project ON DELETE CASCADE, LIKE @core.relationship,
  PRIMARY KEY (project_id, relationship_id));
CREATE TABLE IF NOT EXISTS @delta.source_to_concept_map_delta (
  project_id text NOT NULL REFERENCES @delta.project ON DELETE CASCADE, LIKE @core.source_to_concept_map,
  PRIMARY KEY (project_id, source_vocabulary_id, target_concept_id, source_code, valid_end_date));

CREATE TABLE IF NOT EXISTS @delta.mapping_metadata_delta (
  project_id            text NOT NULL REFERENCES @delta.project ON DELETE CASCADE,
  mapping_concept_id    integer NOT NULL,
  mapping_concept_code  text NOT NULL,
  confidence            double precision,
  predicate_id          text,
  mapping_justification text,
  mapping_provider      text,
  author_id             integer,
  author_label          text,
  reviewer_id           integer,
  reviewer_label        text,
  mapping_tool          text,
  mapping_tool_version  text,
  PRIMARY KEY (project_id, mapping_concept_id));
