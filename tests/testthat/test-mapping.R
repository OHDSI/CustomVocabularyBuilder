source("../../R/cvb.R")

test_that("read_mapping normalises headers and fills missing columns", {
  f <- tempfile(fileext = ".csv")
  writeLines(c("source_code, source_domain_id,reviewer_name", "A,Drug,Jo"), f)
  d <- read_mapping(f)
  expect_named(d, canon)
  expect_equal(d$source_domain, "Drug")
  expect_equal(d$reviewer_label, "Jo")
  expect_true(is.na(d$predicate_id))
})

test_that("render substitutes core schema and project", {
  Sys.setenv(CVB_CORE = "core")
  expect_equal(render("@core.concept"), "core.concept")
})
