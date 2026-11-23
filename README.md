# CustomVocabularyBuilder
Builds OMOP-shaped custom vocabularies from SSSOM-style mapping sheets. Previously TuftsCTSI/CVB.

Core vocabulary tables (e.g. Athena) are read-only. Each project's additions live in shared `<schema>.*_delta` tables keyed by `project_id`, and each project gets views named `<project>_<table>` (e.g. `mimic4_concept`) in the same schema that union the core tables with its own delta.

## Reserved ID ranges
Projects reserve a block in the two-billion concept_id space (max 2.147b). A block is `[start, end)`; the `projects/<id>/project.yml` values must match this table.

| Project    | Block start (bil) | Block end (bil) | Mapping sheet |
|------------|-------------------|-----------------|---------------|
| OHDSI GIS  | 2.05150           | 2.05250         | [sheet 1](https://docs.google.com/spreadsheets/d/1_v1lShEJLtAhBBZEIv8fPTVKjyBOJ-NA_cibyAXMZG8/export?format=csv&gid=1914144239), [sheet 2](https://docs.google.com/spreadsheets/d/1_v1lShEJLtAhBBZEIv8fPTVKjyBOJ-NA_cibyAXMZG8/export?format=csv&gid=379331907), [sheet 3](https://docs.google.com/spreadsheets/d/1_v1lShEJLtAhBBZEIv8fPTVKjyBOJ-NA_cibyAXMZG8/export?format=csv&gid=9161635) (not yet supported by `build`) |
| MIMIC4     | 2.06150           | 2.06350         | [sheet](https://docs.google.com/spreadsheets/d/1LgNSwxx7uDjc6hAJb4m6o_6WvVmuBgH5QYzAqeS3aD0/edit?gid=1932813645) |
| PSYCHIATRY | 2.07150           | 2.07250         | [sheet](https://docs.google.com/spreadsheets/d/1hWFDQ620buxGAZPXDPRHXbs-tz5m3zqEGWBgyCEPYtM/export?format=csv&gid=0) |
| WAVEFORM   | 2.08150           | 2.08250         | to be confirmed |

## Requirements
R with `DatabaseConnector`, `SqlRender` and `yaml`, and a JDK (needed by `rJava`). The PostgreSQL JDBC driver is downloaded on first use into `~/.cvb/jdbc` (override with `DATABASECONNECTOR_JAR_FOLDER`). The delta schema defaults to the core schema; set `CVB_SCHEMA` to change it (it may equal `CVB_CORE`; no schemas are created, so it must already exist) (and `CVB_CORE` for the core vocabulary schema). Set `PGSSLMODE=require` for a remote host that needs TLS.

## Usage
Connection uses the standard `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` variables; `CVB_CORE` names the core vocabulary schema (default `vocabulary`).

```
bin/cvb init                             # create the delta schema, register projects
bin/cvb import-legacy <project> [dir]    # one-time load of an existing *_delta CSV set
bin/cvb build <project> [--dry-run] [--file mapping.csv]
bin/cvb validate <project>               # exits non-zero if any error-level check fails
bin/cvb export <project>                 # writes release/<project>/*.csv
```

## GitHub Action (review, then apply)
`.github/workflows/build.yml` runs from **Actions > Build vocabulary > Run workflow**. With `apply` unchecked it only does a dry run (nothing is written) and uploads `review-<project>`: CSVs of new, changed and deprecated concepts and added and removed relationships. After the review, run it again with `apply` checked. That job waits for approval on the `apply` environment, then builds, validates, exports and publishes a release.

One-time setup in the GitHub repo (Settings > Secrets and variables > Actions):
- **Secrets:** `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`.
- **Variables:** `CVB_CORE` (the schema that holds the core vocabulary tables). Optional: `CVB_SCHEMA` (defaults to `CVB_CORE`) and `PGSSLMODE` (e.g. `require`).
- **Environment:** Settings > Environments > New environment named `apply`, with yourself under Required reviewers.
- **Workflow permissions:** Settings > Actions > General > Workflow permissions > Read and write.
- The database host must accept connections from GitHub-hosted runners.

## How a build works (`sql/build.sql`)
- Each sheet row is keyed by `(source_vocabulary_id, upper(source_code))`; an existing concept is matched by the sheet's `source_concept_id` first, then by code. Codes over 50 characters are shortened to 39 characters plus a hash suffix.
- Relationships come from the sheet's `relationship_id`; if blank, they fall back to the `predicate_id` (exact/close → `Maps to`, broad → `Is a`, narrow → `Subsumes`, related → a domain-specific relationship).
- A concept is non-standard when any of its rows is a `Maps to`/`Maps to value`, otherwise standard (with self `Maps to`/`Mapped from`). The flag is set once, when the concept is created.
- Re-running is idempotent. Concepts and relationships that disappear from the sheet are deprecated, never deleted; a build that would deprecate more than 10% aborts.
- Ancestors are the closure of custom `Is a` edges through the core `concept_ancestor`.
- `source_to_concept_map`, synonyms (split on `||`) and `mapping_metadata` are derived from the same rows.

`sql/checks/` holds the validation suite; each file states its severity on the first line.
