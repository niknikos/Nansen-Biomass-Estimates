# data_io: read biotic.xml files or a DuckDB database into the internal structure; validate against the schema
# Data class touched: C0; Claude may run it on synthetic data only (docs/spec.md, Section 4).
#
# M1 reads NMDBiotic v3 XML only; the DuckDB input (D-06) is deferred. Field
# names, keys, types and units follow the NMD Biotic v3 schema as documented in
# BAIT's field glossary and data model (MIT licence, (c) 2026 Mikko Vihtakari /
# Institute of Marine Research), so that the structure lines up with BAIT and
# with RstoxData.

# ---- Schema -----------------------------------------------------------------

# One row per field. `level` is the NMDBiotic element the field belongs to;
# `source` says whether it is an XML attribute or a child element. Keys are
# inherited downwards: a station is identified by the mission key plus
# serialnumber, and so on (BAIT, knowledge/sampling-units.md).
biotic_schema <- function() {
  tibble::tribble(
    ~table,       ~level,        ~field,               ~type,       ~source,     ~key,  ~unit,
    "mission",    "mission",     "missiontype",        "character", "attribute", TRUE,  NA,
    "mission",    "mission",     "startyear",          "integer",   "attribute", TRUE,  NA,
    "mission",    "mission",     "platform",           "character", "attribute", TRUE,  NA,
    "mission",    "mission",     "missionnumber",      "integer",   "attribute", TRUE,  NA,
    "mission",    "mission",     "cruise",             "character", "element",   FALSE, NA,
    "mission",    "mission",     "platformname",       "character", "element",   FALSE, NA,
    "mission",    "mission",     "missionstartdate",   "date",      "element",   FALSE, NA,
    "mission",    "mission",     "missionstopdate",    "date",      "element",   FALSE, NA,
    "station",    "fishstation", "serialnumber",       "integer",   "attribute", TRUE,  NA,
    "station",    "fishstation", "station",            "integer",   "element",   FALSE, NA,
    "station",    "fishstation", "stationstartdate",   "date",      "element",   FALSE, NA,
    "station",    "fishstation", "stationstarttime",   "character", "element",   FALSE, NA,
    "station",    "fishstation", "stationtype",        "character", "element",   FALSE, NA,
    "station",    "fishstation", "latitudestart",      "double",    "element",   FALSE, "decimal degrees",
    "station",    "fishstation", "longitudestart",     "double",    "element",   FALSE, "decimal degrees",
    "station",    "fishstation", "latitudeend",        "double",    "element",   FALSE, "decimal degrees",
    "station",    "fishstation", "longitudeend",       "double",    "element",   FALSE, "decimal degrees",
    "station",    "fishstation", "bottomdepthstart",   "double",    "element",   FALSE, "m",
    "station",    "fishstation", "bottomdepthstop",    "double",    "element",   FALSE, "m",
    "station",    "fishstation", "fishingdepthmin",    "double",    "element",   FALSE, "m",
    "station",    "fishstation", "gear",               "character", "element",   FALSE, NA,
    "station",    "fishstation", "gearcondition",      "character", "element",   FALSE, NA,
    "station",    "fishstation", "samplequality",      "character", "element",   FALSE, NA,
    "station",    "fishstation", "distance",           "double",    "element",   FALSE, "nautical miles",
    "catch",      "catchsample", "catchsampleid",      "integer",   "attribute", TRUE,  NA,
    "catch",      "catchsample", "catchcategory",      "character", "element",   FALSE, NA,
    "catch",      "catchsample", "commonname",         "character", "element",   FALSE, NA,
    "catch",      "catchsample", "aphia",              "character", "element",   FALSE, NA,
    "catch",      "catchsample", "catchpartnumber",    "integer",   "element",   FALSE, NA,
    "catch",      "catchsample", "sampletype",         "character", "element",   FALSE, NA,
    "catch",      "catchsample", "catchweight",        "double",    "element",   FALSE, "kg",
    "catch",      "catchsample", "catchcount",         "integer",   "element",   FALSE, NA,
    "catch",      "catchsample", "lengthsampleweight", "double",    "element",   FALSE, "kg",
    "catch",      "catchsample", "lengthsamplecount",  "integer",   "element",   FALSE, NA,
    "individual", "individual",  "specimenid",         "integer",   "attribute", TRUE,  NA,
    "individual", "individual",  "length",             "double",    "element",   FALSE, "m",
    "individual", "individual",  "individualweight",   "double",    "element",   FALSE, "kg",
    "individual", "individual",  "sex",                "character", "element",   FALSE, NA
  )
}

survey_tables <- c("mission", "station", "catch", "individual")

# Key columns of each table, including the keys inherited from its parents.
table_keys <- function(table) {
  s <- biotic_schema()
  upto <- survey_tables[seq_len(match(table, survey_tables))]
  s$field[s$key & s$table %in% upto]
}

# All columns of a table, in order: inherited keys first, then own fields.
table_columns <- function(table) {
  s <- biotic_schema()
  unique(c(table_keys(table), s$field[s$table == table]))
}

field_type <- function(field) {
  s <- biotic_schema()
  s$type[match(field, s$field)]
}

#' The internal survey schema
#'
#' Describes the structure that [read_biotic()] and [synth_survey()] produce: four
#' tables (`mission`, `station`, `catch`, `individual`) with NMDBiotic v3 field
#' names, keys, types and units. The schema is structural (class C3); it
#' contains no data.
#'
#' @return A tibble with one row per table and field, and the columns `table`,
#'   `field`, `type`, `key` (part of the table's own key), `inherited_key`
#'   (a key column carried down from a parent table) and `unit`.
#' @export
#' @examples
#' survey_schema()
survey_schema <- function() {
  s <- biotic_schema()
  rows <- lapply(survey_tables, function(tbl) {
    cols <- table_columns(tbl)
    own <- s[s$table == tbl, ]
    tibble::tibble(
      table = tbl,
      field = cols,
      type = field_type(cols),
      key = cols %in% own$field[own$key],
      inherited_key = !cols %in% own$field,
      unit = s$unit[match(cols, s$field)]
    )
  })
  dplyr::bind_rows(rows)
}

# ---- Reading ----------------------------------------------------------------

# Converts text to the schema type. Returns the converted vector and the number
# of non-missing inputs that could not be converted (a count, never the values).
coerce_field <- function(x, type) {
  x[!is.na(x) & !nzchar(trimws(x))] <- NA_character_
  out <- switch(type,
    character = x,
    integer = {
      num <- suppressWarnings(as.numeric(x))
      num[!is.na(num) & num != round(num)] <- NA_real_
      suppressWarnings(as.integer(num))
    },
    double = suppressWarnings(as.numeric(x)),
    date = {
      d <- rep(as.Date(NA), length(x))
      ok <- !is.na(x) & grepl("^\\d{4}-\\d{2}-\\d{2}", x)
      d[ok] <- suppressWarnings(as.Date(substr(x[ok], 1L, 10L), format = "%Y-%m-%d"))
      d
    }
  )
  list(value = out, n_failed = sum(!is.na(x) & is.na(out)))
}

# Reads the attribute or child-element text of `field` for every node.
node_field <- function(nodes, field, source) {
  if (source == "attribute") {
    xml2::xml_attr(nodes, field)
  } else {
    child <- xml2::xml_find_first(nodes, field)
    out <- xml2::xml_text(child)
    out[is.na(child)] <- NA_character_
    out
  }
}

# Builds one table from the nodes of one NMDBiotic level. `ancestors` lists, from
# nearest to furthest, the levels whose keys are inherited.
level_table <- function(doc, table, level, ancestors, failures) {
  s <- biotic_schema()
  nodes <- xml2::xml_find_all(doc, paste0("//", level))
  cols <- list()
  up <- nodes
  for (anc in ancestors) {
    # One parent per node: xml_parent() would drop duplicates.
    up <- xml2::xml_find_first(up, "..")
    anc_fields <- s[s$table == anc & s$key, ]
    for (i in seq_len(nrow(anc_fields))) {
      cols[[anc_fields$field[i]]] <- node_field(up, anc_fields$field[i], "attribute")
    }
  }
  own <- s[s$table == table, ]
  for (i in seq_len(nrow(own))) {
    cols[[own$field[i]]] <- node_field(nodes, own$field[i], own$source[i])
  }
  cols <- cols[table_columns(table)]
  n_failed <- integer(0)
  for (f in names(cols)) {
    conv <- coerce_field(cols[[f]], field_type(f))
    cols[[f]] <- conv$value
    n_failed[f] <- conv$n_failed
  }
  failures[[table]] <- n_failed
  tibble::as_tibble(cols)
}

nmdbiotic_namespace <- function(doc) {
  ns <- xml2::xml_ns(doc)
  hit <- unname(ns[grepl("nmdbiotic", ns, ignore.case = TRUE)])
  if (length(hit) == 0L) NA_character_ else hit[[1]]
}

read_biotic_file <- function(file) {
  doc <- xml2::read_xml(file)
  namespace <- nmdbiotic_namespace(doc)
  if (is.na(namespace) || !grepl("/v3", namespace)) {
    nb_abort("IO-READ-02", "The file is not an NMDBiotic v3 document.")
  }
  xml2::xml_ns_strip(doc)
  failures <- new.env()
  tables <- list(
    mission = level_table(doc, "mission", "mission", character(0), failures),
    station = level_table(doc, "station", "fishstation", "mission", failures),
    catch = level_table(doc, "catch", "catchsample", c("station", "mission"), failures),
    individual = level_table(
      doc, "individual", "individual", c("catch", "station", "mission"), failures
    )
  )
  fail_tbl <- dplyr::bind_rows(lapply(survey_tables, function(tbl) {
    n <- failures[[tbl]]
    tibble::tibble(table = tbl, field = names(n), n_failed = unname(n))
  }))
  list(tables = tables, failures = fail_tbl, namespace = namespace)
}

new_survey <- function(tables, synthetic = FALSE, coercion_failures = NULL,
                       namespace = NA_character_) {
  structure(
    tables[survey_tables],
    class = "nb_survey",
    synthetic = synthetic,
    nmdbiotic_namespace = namespace,
    coercion_failures = coercion_failures
  )
}

#' Read NMDBiotic XML files
#'
#' Parses one or more NMDBiotic v3 (biotic.xml) files into the internal survey
#' structure described by [survey_schema()]. Elements outside the schema are
#' ignored; values that cannot be converted to the schema type become `NA`, and
#' their number is recorded for [validate_survey()].
#'
#' This function reads any path and does not sanitise errors from the XML
#' parser. For real data, use [read_survey()], which resolves the path under the
#' data root and keeps error details in the local log.
#'
#' @param files Paths to one or more NMDBiotic v3 XML files.
#' @return An `nb_survey` object: a list of the tibbles `mission`, `station`,
#'   `catch` and `individual`. Printing it shows row counts only.
#' @export
#' @examples
#' sv <- synth_survey(seed = 1)
#' file <- tempfile(fileext = ".xml")
#' write_biotic(sv, file)
#' survey <- read_biotic(file)
#' survey
read_biotic <- function(files) {
  if (!is.character(files) || length(files) == 0L) {
    nb_abort("IO-READ-03", "`files` must be a character vector of file paths.")
  }
  parts <- lapply(files, read_biotic_file)
  tables <- lapply(survey_tables, function(tbl) {
    out <- dplyr::bind_rows(lapply(parts, function(p) p$tables[[tbl]]))
    if (tbl == "mission") out <- dplyr::distinct(out)
    out
  })
  names(tables) <- survey_tables
  failures <- dplyr::bind_rows(lapply(parts, `[[`, "failures")) |>
    dplyr::summarise(n_failed = sum(.data$n_failed), .by = c("table", "field"))
  namespaces <- unique(vapply(parts, `[[`, character(1), "namespace"))
  new_survey(
    tables,
    synthetic = FALSE,
    coercion_failures = failures,
    namespace = paste(namespaces, collapse = "; ")
  )
}

#' Read a survey from the data zone
#'
#' The entry point for reading real data, run by a person in R on the laptop.
#' The path is resolved under the data root; errors and warnings from the XML
#' parser are written to a local log under `<root>/logs/`, and only a sanitised
#' code and message are shown. In a cloud session (`CLAUDE_CODE_REMOTE` set) it
#' reads only from a data root inside `tempdir()`, where synthetic tests write.
#'
#' @param path Path of an NMDBiotic v3 file, relative to `root`.
#' @param root The data root. Defaults to [data_root()].
#' @return An `nb_survey` object; see [read_biotic()].
#' @export
#' @examples
#' root <- tempfile("nansen-root-")
#' dir.create(root)
#' write_biotic(synth_survey(seed = 1), file.path(root, "synthetic.xml"))
#' survey <- read_survey("synthetic.xml", root = root)
#' validate_survey(survey)
read_survey <- function(path, root = data_root()) {
  file <- resolve_data_path(path, root)
  with_sanitised_errors(
    read_biotic(file),
    log_dir = file.path(root, "logs"),
    code = "IO-READ-01",
    message = "The biotic file could not be read as NMDBiotic XML."
  )
}

#' @export
print.nb_survey <- function(x, ...) {
  flag <- if (isTRUE(attr(x, "synthetic"))) " (synthetic)" else ""
  cat("<nb_survey", flag, ">\n", sep = "")
  for (tbl in survey_tables) {
    cat(sprintf("  %-10s %d rows, %d fields\n", tbl, nrow(x[[tbl]]), ncol(x[[tbl]])))
  }
  invisible(x)
}

# ---- Structure only -------------------------------------------------------

#' Describe the structure of an NMDBiotic file
#'
#' Summarises a biotic.xml file without returning any of its values, so that the
#' reader can be adapted to real files without the data leaving the data zone.
#' It reports the namespace, the number of elements at each level, which fields
#' occur and how often they are filled, and how often each quality code occurs
#' (`stationtype`, `samplequality`, `gearcondition`), for the station
#' inclusion rules (D-09).
#'
#' @inheritParams read_survey
#' @return An `nb_description` object: a list with `namespace` (string),
#'   `elements` (tibble of element names and counts), `fields` (tibble of level,
#'   field, kind, whether it is in the schema, number of records and number
#'   filled) and `codes` (tibble of field, code and count).
#' @export
#' @examples
#' root <- tempfile("nansen-root-")
#' dir.create(root)
#' write_biotic(synth_survey(seed = 1), file.path(root, "synthetic.xml"))
#' describe_biotic("synthetic.xml", root = root)
describe_biotic <- function(path, root = data_root()) {
  file <- resolve_data_path(path, root)
  with_sanitised_errors(
    describe_biotic_file(file),
    log_dir = file.path(root, "logs"),
    code = "IO-READ-01",
    message = "The biotic file could not be read as NMDBiotic XML."
  )
}

describe_biotic_file <- function(file) {
  doc <- xml2::read_xml(file)
  namespace <- nmdbiotic_namespace(doc)
  xml2::xml_ns_strip(doc)
  all_names <- xml2::xml_name(xml2::xml_find_all(doc, "//*"))
  elements <- tibble::tibble(element = all_names) |>
    dplyr::count(.data$element, name = "n")
  s <- biotic_schema()
  levels <- c("mission", "fishstation", "catchsample", "individual")
  fields <- dplyr::bind_rows(lapply(levels, function(level) {
    nodes <- xml2::xml_find_all(doc, paste0("//", level))
    if (length(nodes) == 0L) return(NULL)
    attrs <- unlist(lapply(xml2::xml_attrs(nodes), names))
    kids <- xml2::xml_children(nodes)
    kid_names <- xml2::xml_name(kids)
    kid_filled <- nzchar(trimws(xml2::xml_text(kids))) &
      xml2::xml_length(kids) == 0L
    kid_leaf <- xml2::xml_length(kids) == 0L
    el <- tibble::tibble(field = kid_names[kid_leaf], filled = kid_filled[kid_leaf]) |>
      dplyr::summarise(
        n_present = dplyr::n(), n_filled = sum(.data$filled), .by = "field"
      ) |>
      dplyr::mutate(kind = "element")
    at <- tibble::tibble(field = attrs) |>
      dplyr::count(.data$field, name = "n_present") |>
      dplyr::mutate(n_filled = .data$n_present, kind = "attribute")
    schema_fields <- s$field[s$level == level]
    out <- dplyr::bind_rows(at, el)
    out$level <- level
    out$n_records <- length(nodes)
    out$in_schema <- out$field %in% schema_fields
    out
  })) |>
    dplyr::select("level", "field", "kind", "in_schema", "n_records", "n_present", "n_filled")
  codes <- dplyr::bind_rows(lapply(c("stationtype", "samplequality", "gearcondition"), function(f) {
    txt <- xml2::xml_text(xml2::xml_find_all(doc, paste0("//fishstation/", f)))
    n_stations <- length(xml2::xml_find_all(doc, "//fishstation"))
    counts <- tibble::tibble(code = trimws(txt)) |> dplyr::count(.data$code)
    missing <- n_stations - sum(counts$n)
    if (missing > 0L) counts <- dplyr::bind_rows(counts, tibble::tibble(code = NA, n = missing))
    dplyr::mutate(counts, field = f, .before = 1)
  }))
  structure(
    list(namespace = namespace, elements = elements, fields = fields, codes = codes),
    class = "nb_description"
  )
}

#' @export
print.nb_description <- function(x, ...) {
  cat("<nb_description> structure only, no values\n")
  cat("Namespace:", x$namespace, "\n\n")
  cat("Fields by level:\n")
  print(x$fields, n = Inf)
  cat("\nQuality codes on fishstation (counts):\n")
  print(x$codes, n = Inf)
  invisible(x)
}

# ---- Validation -----------------------------------------------------------

check_row <- function(check_id, table, field, status_if_failed, n_checked, n_failed,
                      description) {
  tibble::tibble(
    check_id = check_id,
    table = table,
    field = field,
    status = ifelse(n_failed > 0, status_if_failed, "pass"),
    n_checked = as.integer(n_checked),
    n_failed = as.integer(n_failed),
    description = description
  )
}

col_or_na <- function(df, field, n = nrow(df)) {
  if (field %in% names(df)) df[[field]] else rep(NA, n)
}

type_matches <- function(x, type) {
  switch(type,
    character = is.character(x),
    integer = is.integer(x),
    double = is.double(x),
    date = inherits(x, "Date")
  )
}

# Counts rows whose `keys` duplicate an earlier row.
n_duplicated <- function(df, keys) {
  if (!all(keys %in% names(df)) || nrow(df) == 0L) return(0L)
  sum(duplicated(df[keys]))
}

# Counts rows of `child` whose parent key has no match in `parent`.
n_orphans <- function(child, parent, keys) {
  if (!all(keys %in% names(child)) || !all(keys %in% names(parent))) return(0L)
  nrow(dplyr::anti_join(child[keys], parent[keys], by = keys))
}

# Counts values outside a condition, ignoring missing values.
n_outside <- function(x, ok) sum(!is.na(x) & !ok, na.rm = TRUE)

#' Validate a survey against the schema
#'
#' Runs the same schema checks on any `nb_survey`, real or synthetic: structure,
#' types, keys, links between tables, value ranges, units, catch parts, raising
#' inputs and completeness. The checks follow BAIT's minimum validation for
#' sampling units (knowledge/sampling-units.md). The report contains check
#' identifiers, field names and counts only, never values.
#'
#' Status is `fail` for a structural or impossible value, and `warn` for a
#' value or pattern that needs a person's judgement (for example a catch split
#' into several parts, which may or may not be additive).
#'
#' @param x An `nb_survey` object.
#' @return An `nb_validation` tibble with the columns `check_id`, `table`,
#'   `field`, `status` (`pass`, `warn` or `fail`), `n_checked`, `n_failed` and
#'   `description`.
#' @export
#' @examples
#' validate_survey(synth_survey(seed = 1)$survey)
validate_survey <- function(x) {
  if (!inherits(x, "nb_survey")) {
    nb_abort("IO-VAL-00", "`x` must be an nb_survey object.")
  }
  s <- biotic_schema()
  out <- list()
  add <- function(...) out[[length(out) + 1L]] <<- check_row(...)

  # Structure
  missing_tables <- setdiff(survey_tables, names(x))
  add("IO-STR-01", "all", NA, "fail", length(survey_tables), length(missing_tables),
      "Required tables present")
  for (tbl in intersect(survey_tables, names(x))) {
    cols <- table_columns(tbl)
    missing_cols <- setdiff(cols, names(x[[tbl]]))
    add("IO-STR-02", tbl, if (length(missing_cols)) paste(missing_cols, collapse = ", ") else NA,
        "fail", length(cols), length(missing_cols), "Required fields present")
  }
  if (length(missing_tables) > 0L) {
    return(new_validation(out))
  }

  # Types
  for (tbl in survey_tables) {
    cols <- intersect(table_columns(tbl), names(x[[tbl]]))
    wrong <- cols[!mapply(type_matches, x[[tbl]][cols], field_type(cols))]
    add("IO-TYP-01", tbl, if (length(wrong)) paste(wrong, collapse = ", ") else NA,
        "fail", length(cols), length(wrong), "Field types match the schema")
  }
  failures <- attr(x, "coercion_failures")
  if (!is.null(failures)) {
    for (i in which(failures$n_failed > 0)) {
      add("IO-TYP-02", failures$table[i], failures$field[i], "fail",
          nrow(x[[failures$table[i]]]), failures$n_failed[i],
          "Values that could not be converted to the schema type when read")
    }
    if (!any(failures$n_failed > 0)) {
      add("IO-TYP-02", "all", NA, "fail", sum(vapply(x[survey_tables], nrow, 1L)), 0L,
          "Values that could not be converted to the schema type when read")
    }
  }

  # Keys: complete and unique
  for (tbl in survey_tables) {
    keys <- intersect(table_keys(tbl), names(x[[tbl]]))
    df <- x[[tbl]]
    n_missing <- if (length(keys)) sum(!stats::complete.cases(df[keys])) else 0L
    add("IO-CMP-02", tbl, paste(keys, collapse = ", "), "fail", nrow(df), n_missing,
        "Key fields not missing")
    add(sprintf("IO-KEY-%02d", match(tbl, survey_tables)), tbl, paste(keys, collapse = ", "),
        "fail", nrow(df), n_duplicated(df, keys), "Key unique within table")
  }

  # Links between tables
  add("IO-REF-01", "station", NA, "fail", nrow(x$station),
      n_orphans(x$station, x$mission, table_keys("mission")), "Every station belongs to a mission")
  add("IO-REF-02", "catch", NA, "fail", nrow(x$catch),
      n_orphans(x$catch, x$station, table_keys("station")), "Every catch sample belongs to a station")
  add("IO-REF-03", "individual", NA, "fail", nrow(x$individual),
      n_orphans(x$individual, x$catch, table_keys("catch")),
      "Every individual belongs to a catch sample")

  # Value ranges
  st <- x$station
  ca <- x$catch
  ind <- x$individual
  for (f in c("latitudestart", "latitudeend")) {
    v <- col_or_na(st, f)
    add("IO-VAL-01", "station", f, "fail", sum(!is.na(v)), n_outside(v, v >= -90 & v <= 90),
        "Latitude within -90 to 90")
  }
  for (f in c("longitudestart", "longitudeend")) {
    v <- col_or_na(st, f)
    add("IO-VAL-02", "station", f, "fail", sum(!is.na(v)), n_outside(v, v >= -180 & v <= 180),
        "Longitude within -180 to 180")
  }
  for (f in c("catchweight", "catchcount", "lengthsampleweight", "lengthsamplecount")) {
    v <- col_or_na(ca, f)
    add("IO-VAL-03", "catch", f, "fail", sum(!is.na(v)), n_outside(v, v >= 0),
        "Weights and counts not negative")
  }
  v <- col_or_na(ind, "individualweight")
  add("IO-VAL-03", "individual", "individualweight", "fail", sum(!is.na(v)), n_outside(v, v >= 0),
      "Weights and counts not negative")
  v <- col_or_na(st, "distance")
  add("IO-VAL-04", "station", "distance", "fail", sum(!is.na(v)), n_outside(v, v > 0),
      "Towed distance positive")
  v <- col_or_na(ind, "length")
  add("IO-VAL-05", "individual", "length", "fail", sum(!is.na(v)), n_outside(v, v > 0),
      "Length positive")
  v <- col_or_na(st, "bottomdepthstart")
  add("IO-VAL-06", "station", "bottomdepthstart", "fail", sum(!is.na(v)), n_outside(v, v > 0),
      "Bottom depth positive")
  yr <- dplyr::left_join(
    st[intersect(c(table_keys("station"), "stationstartdate"), names(st))],
    x$mission[table_keys("mission")],
    by = table_keys("mission")
  )
  station_year <- as.integer(format(col_or_na(yr, "stationstartdate"), "%Y"))
  add("IO-VAL-07", "station", "stationstartdate", "fail", sum(!is.na(station_year)),
      n_outside(station_year, station_year >= yr$startyear & station_year <= yr$startyear + 1L),
      "Station date in the mission's start year or the year after")

  # Units and plausibility (BAIT, knowledge/data-model.md and data-quality.md)
  v <- col_or_na(ind, "length")
  add("IO-UNIT-01", "individual", "length", "warn", sum(!is.na(v)), n_outside(v, v <= 3),
      "Length above 3 m: probably recorded in cm, not m")
  w_g <- col_or_na(ind, "individualweight") * 1000
  l_cm <- col_or_na(ind, "length") * 100
  k <- 100 * w_g / l_cm^3
  add("IO-PLA-01", "individual", "length, individualweight", "warn", sum(is.finite(k)),
      n_outside(k[is.finite(k)], k[is.finite(k)] >= 0.02 & k[is.finite(k)] <= 10),
      "Condition factor outside 0.02 to 10: probable unit or entry error")

  # Catch parts and raising inputs (BAIT, knowledge/sampling-units.md)
  part_keys <- c(table_keys("station"), "catchcategory")
  n_multi <- if (all(part_keys %in% names(ca)) && nrow(ca) > 0L) {
    ca |>
      dplyr::count(dplyr::across(dplyr::all_of(part_keys))) |>
      dplyr::filter(.data$n > 1L) |>
      nrow()
  } else {
    0L
  }
  add("IO-CAT-01", "catch", "catchcategory", "warn", nrow(ca), n_multi,
      "Species with several catch samples at one station: sum only disjoint parts")
  lc <- col_or_na(ca, "lengthsamplecount")
  cc <- col_or_na(ca, "catchcount")
  add("IO-RAI-01", "catch", "lengthsamplecount, catchcount", "warn",
      sum(!is.na(lc) & !is.na(cc)), n_outside(lc - cc, lc <= cc),
      "Length sample count not above catch count")
  lw <- col_or_na(ca, "lengthsampleweight")
  cw <- col_or_na(ca, "catchweight")
  add("IO-RAI-02", "catch", "lengthsampleweight, catchweight", "warn",
      sum(!is.na(lw) & !is.na(cw)), n_outside(lw - cw, lw <= cw * (1 + 1e-9)),
      "Length sample weight not above catch weight")
  n_mismatch <- 0L
  n_compared <- 0L
  if (all(table_keys("catch") %in% names(ind)) && nrow(ca) > 0L) {
    measured <- ind |>
      dplyr::filter(!is.na(.data$length)) |>
      dplyr::count(dplyr::across(dplyr::all_of(table_keys("catch"))), name = "n_ind")
    cmp <- ca |>
      dplyr::filter(!is.na(.data$lengthsamplecount)) |>
      dplyr::left_join(measured, by = table_keys("catch")) |>
      dplyr::mutate(n_ind = dplyr::coalesce(.data$n_ind, 0L))
    n_compared <- nrow(cmp)
    n_mismatch <- sum(cmp$n_ind != cmp$lengthsamplecount)
  }
  add("IO-RAI-03", "catch", "lengthsamplecount", "warn", n_compared, n_mismatch,
      "Individuals measured for length match the length sample count")

  # Completeness of the fields swept-area estimation needs
  needed <- list(
    station = c("stationstartdate", "latitudestart", "longitudestart", "bottomdepthstart",
                "gear", "distance"),
    catch = c("catchcategory", "catchweight")
  )
  for (tbl in names(needed)) {
    for (f in needed[[tbl]]) {
      v <- col_or_na(x[[tbl]], f)
      add("IO-CMP-01", tbl, f, "warn", length(v), sum(is.na(v)),
          "Fields needed for swept-area estimation filled")
    }
  }
  new_validation(out)
}

unclass_validation <- function(x) {
  class(x) <- setdiff(class(x), "nb_validation")
  x
}

new_validation <- function(rows) {
  out <- dplyr::bind_rows(rows)
  class(out) <- c("nb_validation", class(out))
  out
}

#' @export
print.nb_validation <- function(x, ...) {
  n_fail <- sum(x$status == "fail")
  n_warn <- sum(x$status == "warn")
  overall <- if (n_fail > 0) "FAIL" else if (n_warn > 0) "PASS with warnings" else "PASS"
  cat(sprintf("<nb_validation> %s: %d checks, %d fail, %d warn (counts only, no values)\n",
              overall, nrow(x), n_fail, n_warn))
  print(tibble::as_tibble(unclass_validation(x))[c("check_id", "table", "field", "status",
                                                   "n_checked", "n_failed")], n = Inf)
  invisible(x)
}
