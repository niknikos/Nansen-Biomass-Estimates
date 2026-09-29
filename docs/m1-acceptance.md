# M1 acceptance record

Milestone M1 (data layer, synthetic generator, airlock) has two acceptance checks
(docs/spec.md, Section 11):

1. Real and synthetic data pass the same schema checks.
2. The disclosure check rejects a deliberately disclosive export.

Check 2 and the synthetic half of check 1 run in a cloud session on synthetic data and
passed on 29 September 2026. The real half of check 1 needs real data, which never exist
in the cloud: a person runs it on the laptop, outside Claude Code (section 3 below). M1 is
not merged until that step has been reported and a person has reviewed the code.

## 1. What M1 delivers

| Module | Exported functions | Purpose |
| --- | --- | --- |
| `data_io` | `survey_schema()`, `read_biotic()`, `read_survey()`, `describe_biotic()`, `validate_survey()`, `data_root()` | Read NMDBiotic v3 XML into four tables; describe a file's structure without values; validate any survey against the schema |
| `synth` | `synth_design()`, `synth_survey()`, `synth_density()`, `write_biotic()` | Generate synthetic surveys from known fields, with their true biomass and abundance; write them as NMDBiotic XML |
| `disclosure` | `estimate_schema()`, `check_disclosure()`, `stage_export()`, `synth_export()` | Check a candidate export against D-03 and stage it for a person to release |

Design points a reviewer should know:

- **Structure.** The four tables (`mission`, `station`, `catch`, `individual`) keep the
  NMDBiotic v3 field names and native keys, as documented in BAIT's data model and field
  glossary (MIT licence, (c) Mikko Vihtakari / IMR). Lengths are in metres, weights in kg.
- **Sanitised errors (CLAUDE.md, rule 8).** `read_survey()` and `describe_biotic()` write
  parser errors and warnings to `<NANSEN_DATA_ROOT>/logs/` and print only a code such as
  `IO-READ-01` and the log file's name. Messages never contain values or file paths.
- **Cloud guard.** When `CLAUDE_CODE_REMOTE` is set, the package reads and stages only
  under `tempdir()`, where synthetic tests write. On the laptop the variable is unset and
  the guard has no effect.
- **D-03, as updated in Section 15.** At least 5 stations, and at least 3 stations with a
  positive catch unless none is positive, behind every released cell; both minimums can be
  raised, never lowered; no release that lets a withheld stratum be recovered from the
  total. The rules restrict what is released. They do not remove any station from
  estimation.
- **Deferred.** The DuckDB input (D-06) and the reuse of BAIT's database layout (D-17);
  the survey configuration schema (M2).

## 2. Cloud check (synthetic data)

**Passed**, with `Status: OK` from `R CMD check`.

| Item | Value |
| --- | --- |
| Date | 29 September 2026 |
| Code | commits `90a04d8` and `43fdfb4` on `claude/elegant-pascal-52da5l` |
| Cloud environment | `nansenbiomass-m0`; setup logs newer than the session, so the current `cloud/setup.sh` ran |
| R and packages | R 4.6.1; the versions recorded in the M0 record and pinned in `renv.lock` |
| New dependencies | None outside `renv.lock`: dplyr, rlang, sf, tibble, withr and xml2 moved to Imports |

`R CMD build` and `R CMD check --no-manual` ran in the session's scratchpad, not in the
working tree. Session charset UTF-8; **`Status: OK`**, no NOTE, WARNING or ERROR; examples
ran; tests `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 160 ]`.

**Check 1, synthetic side.** A synthetic survey (seed 1: 45 stations, 108 catch samples,
5,285 individuals) written to NMDBiotic XML and read back reproduces all four tables
exactly. `validate_survey()` gives 48 checks, 0 fail and 1 warn; the warning
(`IO-CAT-01`) is intended, since the generator splits some catches into two parts.
Deliberately corrupted copies fail the expected checks (duplicate key, orphan catch,
negative weight, missing field, impossible latitude, date outside the mission year), and
lengths entered in centimetres raise the unit and plausibility warnings.

**Check 2.** Each deliberately disclosive synthetic export is rejected with its expected
code:

| Disclosive export | Rejected by |
| --- | --- |
| Coordinate and station identifier columns added | `DC-FLD-01`, `DC-FLD-04` |
| An `sf` object with point geometry | `DC-FLD-01`, `DC-FLD-03`, `DC-FLD-04` |
| One row per station | `DC-AGG-01`, or `DC-VAL-01` when rows carry station labels |
| A stratum with 3 stations, or a cell without support | `DC-AGG-02` |
| Total released with exactly one stratum withheld | `DC-AGG-03` |
| A cell resting on 2 positive stations | `DC-AGG-04` |
| Text resembling a coordinate | `DC-VAL-02` |
| Wrong type, missing required value, missing field | `DC-TYP-01`, `DC-TYP-02`, `DC-FLD-02` |

A clean synthetic export passes and is staged with `disclosure =
pass:rules-v1:min5:pos3`. Lowering either minimum is refused, staging into an `outbox`
folder is refused, and a failing rerun removes an earlier passing export.

**Rule 8.** A sentinel string placed in synthetic input appears in the local log but in no
error, warning, printed survey or report.

## 3. Laptop check (real data): steps for a person

These steps run in R on the laptop, outside Claude Code. Nothing from them is committed.

1. Pull `claude/elegant-pascal-52da5l`. In R, in the repository:

   ```r
   renv::status()           # no change expected: no new packages
   testthat::test_local()   # the same tests, on Windows with the lockfile
   ```

   Report the `[ FAIL | WARN | SKIP | PASS ]` line.

2. For each real survey file under `NANSEN_DATA_ROOT` (the path relative to the root):

   ```r
   library(nansenbiomass)        # or pkgload::load_all()
   d <- describe_biotic("<relative path>/biotic.xml")
   d                              # structure and code counts, no values
   v <- read_survey("<relative path>/biotic.xml") |> validate_survey()
   v                              # check codes, status and counts, no values
   ```

3. Review the output, then report back, labelling surveys only as "real survey A", "real
   survey B" and so on:
   - from `describe_biotic`: the namespace version, the names of any fields with
     `in_schema = FALSE`, and, if you are content to share them, the counts of
     `stationtype`, `samplequality` and `gearcondition` codes (these inform D-09 at M2);
   - from `validate_survey`: `check_id`, `table`, `field`, `status` and `n_failed` for
     every row that is not `pass`;
   - any sanitised error code (for example `IO-READ-01`).

   Please do not paste log files, values, file paths or survey identifiers.

4. If the reader or a check fails, the code is adapted from those names and counts, and
   the steps are repeated. **Check 1 passes** when real and synthetic surveys return the
   same set of checks with no `fail`. Warnings are reviewed case by case: some, such as
   several catch parts for one species, are expected in real data.

### Laptop result

*To be recorded after the laptop run (date, commit, number of surveys, outcome, and any
adaptation made).*

## 4. Limitations

- **Real files are unseen.** The reader follows the NMDBiotic v3 schema, but the Nansen
  files may use fields, codes or versions that synthetic data do not exercise. Section 3
  exists to find this out without the data leaving the laptop.
- **No schema (XSD) validation.** Files are read by element name. A file that is valid XML
  but departs from the XSD is caught only through the checks above.
- **Reading speed.** About 2 seconds for 5,000 individuals in the cloud. Large surveys will
  take longer; this can be optimised if it matters.
- **The positive-station minimum of 3** is a proposal adopted with this milestone; the
  project lead may raise it. Positive stations are counted by species code
  (`catchcategory`), and the same counts apply to biomass and abundance cells.
- **Differencing** is checked within one survey, year, species, method and quantity.
  Differencing across quantities, methods or later releases is not checked.
- **The support table** (stations and positive stations per cell) is produced by
  `synth_export()` for synthetic data only; the pipelines produce it from M2 onwards.
- **The synthetic truth** is integrated on a 1 km grid. For a constant field it equals
  density times area exactly; otherwise the grid error is small but not zero.
