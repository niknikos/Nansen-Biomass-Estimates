# data_io on synthetic surveys only (CLAUDE.md, rule 3). Real data are validated
# by a person on the laptop with the same validate_survey() (docs/m1-acceptance.md).

sv <- synth_survey(seed = 1)
sentinel <- "SENTINEL_7f3a9c"

xml_file <- function(survey = sv) {
  f <- withr::local_tempfile(fileext = ".xml", .local_envir = parent.frame())
  write_biotic(survey, f)
  f
}

status_of <- function(v, id, table = NULL) {
  rows <- v[v$check_id == id & (is.null(table) | v$table %in% table), ]
  if (any(rows$status == "fail")) "fail" else if (any(rows$status == "warn")) "warn" else "pass"
}

corrupt <- function(tbl, fun) {
  x <- sv$survey
  x[[tbl]] <- fun(x[[tbl]])
  x
}

test_that("survey_schema() describes four tables with NMDBiotic keys", {
  s <- survey_schema()
  expect_setequal(unique(s$table), c("mission", "station", "catch", "individual"))
  expect_equal(s$field[s$table == "individual" & (s$key | s$inherited_key)],
               c("missiontype", "startyear", "platform", "missionnumber", "serialnumber",
                 "catchsampleid", "specimenid"))
  expect_equal(s$unit[s$table == "individual" & s$field == "length"], "m")
})

test_that("a synthetic survey survives the XML round trip unchanged", {
  s <- read_biotic(xml_file())
  expect_s3_class(s, "nb_survey")
  for (tbl in c("mission", "station", "catch", "individual")) {
    expect_equal(as.data.frame(s[[tbl]]), as.data.frame(sv$survey[[tbl]]),
                 ignore_attr = TRUE, info = tbl)
  }
  expect_false(isTRUE(attr(s, "synthetic")))
  expect_match(attr(s, "nmdbiotic_namespace"), "nmdbiotic/v3.1")
})

test_that("synthetic surveys pass every schema check (acceptance check 1, synthetic side)", {
  for (v in list(validate_survey(sv$survey), validate_survey(read_biotic(xml_file())))) {
    expect_s3_class(v, "nb_validation")
    expect_false(any(v$status == "fail"))
    expect_equal(status_of(v, "IO-CAT-01"), "warn")
    expect_named(v, c("check_id", "table", "field", "status", "n_checked", "n_failed",
                      "description"))
  }
})

test_that("read_survey() and describe_biotic() work under a data root", {
  root <- withr::local_tempdir()
  write_biotic(sv, file.path(root, "synthetic.xml"))
  s <- read_survey("synthetic.xml", root = root)
  expect_equal(nrow(s$station), nrow(sv$survey$station))
  d <- describe_biotic("synthetic.xml", root = root)
  expect_s3_class(d, "nb_description")
  expect_named(d$fields, c("level", "field", "kind", "in_schema", "n_records", "n_present",
                           "n_filled"))
  expect_true(all(d$fields$in_schema))
  expect_equal(d$codes$code[d$codes$field == "stationtype"], "12")
  expect_false(dir.exists(file.path(root, "logs")))
})

test_that("corrupted surveys fail the expected checks", {
  v <- validate_survey(corrupt("station", function(d) dplyr::bind_rows(d, d[1, ])))
  expect_equal(status_of(v, "IO-KEY-02"), "fail")

  v <- validate_survey(corrupt("catch", function(d) {
    d$serialnumber[1] <- 1L
    d
  }))
  expect_equal(status_of(v, "IO-REF-02"), "fail")

  v <- validate_survey(corrupt("catch", function(d) {
    d$catchweight[2] <- -1
    d
  }))
  expect_equal(status_of(v, "IO-VAL-03", "catch"), "fail")

  v <- validate_survey(corrupt("station", function(d) dplyr::select(d, -"distance")))
  expect_equal(status_of(v, "IO-STR-02", "station"), "fail")

  v <- validate_survey(corrupt("station", function(d) {
    d$latitudestart[3] <- 95
    d
  }))
  expect_equal(status_of(v, "IO-VAL-01"), "fail")

  v <- validate_survey(corrupt("individual", function(d) {
    d$length <- d$length * 100
    d
  }))
  expect_equal(status_of(v, "IO-UNIT-01"), "warn")
  expect_equal(status_of(v, "IO-PLA-01"), "warn")

  v <- validate_survey(corrupt("catch", function(d) {
    d$lengthsamplecount[1] <- d$catchcount[1] + 5L
    d
  }))
  expect_equal(status_of(v, "IO-RAI-01"), "warn")
  expect_equal(status_of(v, "IO-RAI-03"), "warn")

  v <- validate_survey(corrupt("station", function(d) {
    d$stationstartdate[1] <- as.Date("1990-01-01")
    d
  }))
  expect_equal(status_of(v, "IO-VAL-07"), "fail")
})

test_that("values that cannot be converted are counted, not echoed", {
  f <- xml_file()
  x <- readLines(f)
  i <- grep("<distance>", x)[1]
  x[i] <- sub("<distance>[^<]*</distance>", paste0("<distance>", sentinel, "</distance>"), x[i])
  writeLines(x, f)
  s <- read_biotic(f)
  v <- validate_survey(s)
  row <- v[v$check_id == "IO-TYP-02" & v$field %in% "distance", ]
  expect_equal(row$status, "fail")
  expect_equal(row$n_failed, 1L)
  printed <- paste(utils::capture.output(print(v), print(s)), collapse = "\n")
  expect_false(grepl(sentinel, printed))
  expect_false(any(vapply(v, function(col) any(grepl(sentinel, col)), logical(1))))
})

test_that("unreadable files give a sanitised error and a local log", {
  root <- withr::local_tempdir()
  writeLines(c("<missions>", paste0("<broken ", sentinel, " value"), "</missions>"),
             file.path(root, "broken.xml"))
  cnd <- expect_error(read_survey("broken.xml", root = root), class = "nansenbiomass_error")
  expect_equal(cnd$nb_code, "IO-READ-01")
  expect_false(grepl(sentinel, conditionMessage(cnd)))
  expect_false(grepl("broken.xml", conditionMessage(cnd), fixed = TRUE))
  log_text <- readLines(list.files(file.path(root, "logs"), full.names = TRUE))
  expect_true(any(grepl("error", log_text)))
})

test_that("files that are not NMDBiotic v3 are refused by code", {
  root <- withr::local_tempdir()
  writeLines(c("<?xml version=\"1.0\"?>", "<missions xmlns=\"http://example.org/other\"/>"),
             file.path(root, "other.xml"))
  cnd <- expect_error(read_survey("other.xml", root = root), class = "nansenbiomass_error")
  expect_equal(cnd$nb_code, "IO-READ-02")
})

test_that("printing a survey shows counts, never values", {
  printed <- paste(utils::capture.output(print(sv$survey)), collapse = "\n")
  expect_match(printed, "station +45 rows")
  expect_false(grepl("SYNTH0001", printed))
})
