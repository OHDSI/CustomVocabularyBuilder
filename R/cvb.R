library(DatabaseConnector)

core_schema <- function() Sys.getenv("CVB_CORE", "vocabulary")
delta_schema <- function() Sys.getenv("CVB_SCHEMA", core_schema())

connect_db <- function() {
  jars <- Sys.getenv("DATABASECONNECTOR_JAR_FOLDER", file.path(path.expand("~"), ".cvb", "jdbc"))
  dir.create(jars, recursive = TRUE, showWarnings = FALSE)
  if (!length(list.files(jars, "postgres"))) downloadJdbcDrivers("postgresql", jars)
  ssl <- Sys.getenv("PGSSLMODE")
  connect(createConnectionDetails(
    dbms = "postgresql", pathToDriver = jars,
    server = paste0(Sys.getenv("PGHOST", "localhost"), "/", Sys.getenv("PGDATABASE", "postgres")),
    port = as.integer(Sys.getenv("PGPORT", "5432")), user = Sys.getenv("PGUSER", "postgres"),
    password = Sys.getenv("PGPASSWORD"), extraSettings = if (nzchar(ssl)) paste0("sslmode=", ssl)))
}

render <- function(sql, project = NULL) {
  if (is.null(project)) return(SqlRender::render(sql, core = core_schema(), delta = delta_schema()))
  stopifnot(grepl("^[a-z0-9_]+$", project))
  SqlRender::render(gsub("@views.", paste0("@delta.", project, "_"), sql, fixed = TRUE),
                    core = core_schema(), delta = delta_schema(), project = paste0("'", project, "'"))
}

run_script <- function(con, sql) executeSql(con, sql, progressBar = FALSE, reportOverallTime = FALSE)
jx <- function(con, sql) for (st in SqlRender::splitSql(sql)) {
  s <- rJava::.jcall(con@jConnection, "Ljava/sql/Statement;", "createStatement")
  tryCatch(rJava::.jcall(s, "Z", "execute", st), finally = rJava::.jcall(s, "V", "close"))
}
jq <- function(con, sql) {
  s <- rJava::.jcall(con@jConnection, "Ljava/sql/Statement;", "createStatement")
  rs <- rJava::.jcall(s, "Ljava/sql/ResultSet;", "executeQuery", sql)
  on.exit(rJava::.jcall(s, "V", "close"))
  n <- rJava::.jcall(rJava::.jcall(rs, "Ljava/sql/ResultSetMetaData;", "getMetaData"), "I", "getColumnCount")
  md <- rJava::.jcall(rs, "Ljava/sql/ResultSetMetaData;", "getMetaData")
  out <- list()
  while (rJava::.jcall(rs, "Z", "next"))
    out[[length(out) + 1]] <- vapply(seq_len(n), function(i) { v <- rJava::.jcall(rs, "S", "getString", i); if (is.null(v)) NA_character_ else v }, "")
  m <- matrix(as.character(unlist(out)), ncol = n, byrow = TRUE)
  setNames(as.data.frame(m, stringsAsFactors = FALSE), vapply(seq_len(n), function(i) rJava::.jcall(md, "S", "getColumnLabel", i), ""))
}
in_txn <- function(con, f, commit = TRUE) {
  jc <- con@jConnection
  rJava::.jcall(jc, "V", "setAutoCommit", FALSE)
  on.exit(rJava::.jcall(jc, "V", "setAutoCommit", TRUE))
  tryCatch({ r <- f(); rJava::.jcall(jc, "V", if (commit) "commit" else "rollback"); r },
           error = function(e) { rJava::.jcall(jc, "V", "rollback"); stop(e) })
}

read_sql <- function(path) paste(readLines(path, warn = FALSE), collapse = "\n")
query <- function(con, sql, project = NULL) querySql(con, render(sql, project), snakeCaseToCamelCase = FALSE)
temp_table <- function(con, name, data)
  insertTable(con, tableName = name, data = data, tempTable = TRUE, dropTableIfExists = TRUE, createTable = TRUE,
              progressBar = FALSE, camelCaseToSnakeCase = FALSE)

projects <- function() {
  f <- Sys.glob("projects/*/project.yml")
  setNames(lapply(f, yaml::read_yaml), basename(dirname(f)))
}

init <- function(con) {
  run_script(con, render(read_sql("sql/schema.sql")))
  p <- projects()
  temp_table(con, "reg", data.frame(project_id = names(p), id_start = sapply(p, `[[`, "id_start"),
                                    id_end = sapply(p, `[[`, "id_end")))
  run_script(con, render("INSERT INTO @delta.project SELECT project_id, id_start, id_end FROM reg
                   ON CONFLICT (project_id) DO UPDATE SET id_start = EXCLUDED.id_start, id_end = EXCLUDED.id_end;"))
}

legacy_files <- c(concept_delta = "concept_delta.csv", concept_relationship_delta = "concept_relationship_delta.csv",
  concept_ancestor_delta = "concept_ancestor_delta.csv", concept_synonym_delta = "concept_synonym_delta.csv",
  vocabulary_delta = "vocabulary_delta.csv", domain_delta = "domain_delta.csv",
  concept_class_delta = "concept_class_delta.csv", relationship_delta = "relationship_delta.csv",
  source_to_concept_map_delta = "source_to_concept_map.csv", mapping_metadata_delta = "mapping_metadata.csv")

import_legacy <- function(con, id, dir = projects()[[id]]$legacy_dir) {
  p <- projects()[[id]]
  data <- lapply(legacy_files, function(f) read.csv(file.path(dir, f), colClasses = "character", na.strings = "", check.names = FALSE))
  k <- as.integer(data$vocabulary_delta$vocabulary_concept_id)
  data$vocabulary_delta <- data$vocabulary_delta[k >= p$id_start & k < p$id_end, ]
  load <- read_sql("sql/load.sql")
  stmts <- lapply(names(data), function(t) {
    if (!nrow(data[[t]])) return(NULL)
    temp_table(con, paste0("stage_", t), data[[t]])
    query(con, gsub("@stage", paste0("stage_", t), gsub("@tbl", t, load, fixed = TRUE), fixed = TRUE), id)$stmt
  })
  in_txn(con, function() for (i in seq_along(data)) {
    t <- names(data)[i]
    jx(con, render(sprintf("DELETE FROM @delta.%s WHERE project_id = @project", t), id))
    if (!is.null(stmts[[i]])) jx(con, stmts[[i]])
    message(sprintf("%-30s read %6d", t, nrow(data[[t]])))
  })
}

refresh_views <- function(con, id) {
  run_script(con, paste0(query(con, read_sql("sql/views.sql"), id)$stmt, ";", collapse = "\n"))
}

validate <- function(con, id) {
  refresh_views(con, id)
  res <- lapply(sort(Sys.glob("sql/checks/*.sql")), function(f) {
    sql <- read_sql(f)
    d <- query(con, sql, id)
    list(row = data.frame(check = sub("\\.sql$", "", basename(f)),
                          severity = sub("^-- (\\w+):.*", "\\1", sql),
                          violations = nrow(d),
                          description = sub("^-- \\w+: ([^\n]*).*", "\\1", sql)),
         rows = d)
  })
  out <- do.call(rbind, lapply(res, `[[`, "row"))
  for (r in res) if (nrow(r$rows) > 0) {
    cat("\n", r$row$check, " (", r$row$severity, "): ", r$row$description, "\n", sep = "")
    print(utils::head(r$rows, 5), row.names = FALSE)
  }
  cat("\n"); print(out[, c("check", "severity", "violations")], row.names = FALSE)
  out
}

export <- function(con, id, out = file.path("release", id)) {
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  for (t in names(legacy_files)) {
    d <- query(con, sprintf("SELECT * FROM @delta.%s WHERE project_id = @project ORDER BY 2, 3", t), id)
    utils::write.csv(d[, names(d) != "project_id", drop = FALSE], file.path(out, paste0(t, ".csv")),
                     row.names = FALSE, na = "")
  }
  invisible(out)
}

canon <- c("source_code", "source_code_set", "source_domain", "source_vocabulary_id", "source_concept_class_id",
  "source_concept_id", "source_description", "source_description_synonym", "relationship_id", "predicate_id", "target_concept_id",
  "confidence", "author_label", "reviewer_label", "mapping_justification", "mapping_tool", "mapping_tool_version")
alias <- c(source_domain_id = "source_domain", reviewer_name = "reviewer_label", author_name = "author_label",
           source_concept_code = "source_code")

read_mapping <- function(src) {
  d <- read.csv(src, colClasses = "character", na.strings = character(0), check.names = FALSE, encoding = "UTF-8")
  n <- tolower(trimws(names(d)))
  n <- ifelse(n %in% names(alias), alias[n], n)
  d <- d[, !duplicated(n), drop = FALSE]
  names(d) <- n[!duplicated(n)]
  d[setdiff(canon, names(d))] <- NA_character_
  d[canon]
}

build <- function(con, id, src = projects()[[id]]$sheet, dry_run = FALSE, max_deprecate = 0.1) {
  p <- projects()[[id]]
  d <- read_mapping(src)
  out <- file.path("release", id)
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(d, file.path(out, "mapping_source.csv"), row.names = FALSE, na = "")
  d$ord <- seq_len(nrow(d))
  refresh_views(con, id)
  cfg <- c(vocabulary = p$vocabulary$id, vocabulary_name = p$vocabulary$name,
           provider = if (is.null(p$sheet)) src else sub("/export.*", "", p$sheet), max_deprecate = max_deprecate,
           force_vocabulary = isTRUE(p$force_vocabulary))
  temp_table(con, "cfg", data.frame(ckey = names(cfg), value = as.character(cfg)))
  cl <- if (is.null(p$classes)) c(none = "") else unlist(p$classes)
  temp_table(con, "class_map", data.frame(code_set = names(cl), class_id = unname(cl)))
  temp_table(con, "src_raw", d)
  in_txn(con, function() {
    jx(con, render("SELECT pg_advisory_xact_lock(hashtext(@project))", id))
    jx(con, render(read_sql("sql/build.sql"), id))
    stop_if <- jq(con, "SELECT reason FROM abort")$reason
    if (length(stop_if)) if (dry_run) warning("would abort: ", stop_if[[1]], call. = FALSE) else stop(stop_if[[1]])
    print(jq(con, "SELECT step, n FROM summary ORDER BY step"), row.names = FALSE)
    print(utils::head(jq(con, "SELECT reason, ord, code FROM src_reject ORDER BY reason, ord"), 10), row.names = FALSE)
    rv <- file.path(out, "review"); dir.create(rv, showWarnings = FALSE)
    for (f in sort(Sys.glob("sql/review/*.sql")))
      utils::write.csv(jq(con, render(read_sql(f), id)), file.path(rv, sub("sql$", "csv", basename(f))), row.names = FALSE, na = "")
    if (dry_run) message("dry run: rolling back")
  }, commit = !dry_run)
}
