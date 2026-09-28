# M0 acceptance record

Milestone M0 (safeguards and scaffolding) has two acceptance checks (docs/spec.md,
Section 11):

1. A local session cannot open the data zone or run commands.
2. A cloud session builds and tests the package on synthetic data.

Both were run on 28 September 2026 and both passed. This note records the evidence and
its limits. M0 is not merged until a person has reviewed the code (Section 11).

## 1. Local safeguards

Passed. The two-phase canary test, its conditions, every probe and its limitations are
recorded in [`local-safeguards.md`](local-safeguards.md), section 4; the procedure is in
[`safeguard-test/README.md`](safeguard-test/README.md).

## 2. Cloud build and test

**Passed**, with `Status: OK` from `R CMD check`.

### Conditions

| Item | Value |
| --- | --- |
| Date | 28 September 2026, 11:58 UTC |
| Commit | `18d7e7a` on `claude/m0-safeguards-scaffolding-i1iyaz` |
| Cloud environment | `nansenbiomass-m0`, created that day; first session, so the setup script ran fresh |
| Setup script | [`cloud/setup.sh`](../cloud/setup.sh) at `18d7e7a`, pasted into the environment's settings |
| Environment variables | `LANG=C.UTF-8` |
| Allowed domains | `cloud.r-project.org`, `p3m.dev`, `rspm-sync.rstudio.com`, `packagemanager.posit.co`, plus the default list |
| R | 4.6.1 (2026-06-24) |
| Packages | renv 1.2.4, testthat 3.3.2, roxygen2 8.1.0, yaml 2.3.12, codetools 0.2.20, sf 1.1.3, terra 1.9.50, sdmTMB 1.1.0 |
| System libraries | GEOS 3.12.1, GDAL 3.8.4, PROJ 9.4.0 |

The check session confirmed first that the setup had run in that session (its logs were
written in the minute before it started), that `LANG` was `C.UTF-8`, and that
`codetools` and the `en_US.utf8` locale were present. It changed, committed and pushed
nothing, and ran the build and check in its scratchpad.

### Result

- `R CMD build` produced `nansenbiomass_0.0.0.9000.tar.gz`; the output was routine.
  `.Rbuildignore` kept `outbox/`, `configs/`, `synthetic/`, `cloud/`, `docs/` and
  `.claude/` out of the tarball.
- `R CMD check --no-manual`: session charset UTF-8; **`Status: OK`**; no NOTE, WARNING or
  ERROR (`checking examples ... NONE` is informational).
- Tests: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1 ]`.

### Limitations

- **"On synthetic data" is met only in a narrow sense.** No real data were involved, but
  no synthetic data were either: the single test checks that the package namespace
  loads, and every module in `R/` is still an empty file. That is what a scaffolding
  milestone should contain. The first test on synthetic data will come with the `synth`
  module (M1).
- **renv was not active.** The repository has no `renv.lock` yet (the lockfile is to be
  created on the laptop), so the check ran against the package versions the setup script
  installed, listed above.
- **No examples yet.** `CLAUDE.md` requires a runnable example on synthetic data for each
  exported function; the check will start testing examples once there are any.

### How the check got there

Six earlier runs found and fixed the following. They are recorded because each lesson
applies to later milestones.

| Run | Finding | Resolution |
| --- | --- | --- |
| 1 | Session failed to start while apt was configuring development libraries | Setup exceeded the roughly five-minute budget. The script now installs runtime libraries and binaries only (135 packages with dependencies, against 371); it can no longer compile from source, to be revisited at M2 and M3. |
| 2 | Every R package download failed, although P3M's package index was read | P3M redirects package downloads (HTTP 307) to `rspm-sync.rstudio.com`, which was not allowed. Host added; the script now diagnoses failed downloads and no longer stops the session over them. |
| 3 | Check passed with `2 WARNINGs, 1 NOTE`: hidden `inst/stox/.gitkeep`, empty `inst`, locale | `inst/stox/README.md` replaces the placeholder; the script generates `en_US.UTF-8` and installs `codetools`. |
| 4 to 6 | `1 WARNING` (locale), `LANG` unset, `codetools` missing; setup logs dated from run 3 | These sessions started from run 3's cached environment. The setup-script and variable changes saved to that environment did not reach new sessions. A new environment, `nansenbiomass-m0`, ran the current script on its first session. |

**Lesson for later milestones.** When the setup script changes, check that the next
session's setup logs in `/tmp/nansenbiomass-setup` are newer than the session itself. If
they are not, the session ran from a cached environment; creating a new environment is
the reliable way to get a fresh one.

## 3. The renv lockfile in the cloud

The lockfile was created on the laptop and added in commit `f0f59cc` (R 4.6.1; 82
packages, all from CRAN; sf 1.1-3, terra 1.9-50, sdmTMB 1.1.0, testthat 3.3.2, roxygen2
8.1.0, yaml 2.3.12, renv 1.2.4, the same versions the cloud environment had installed).
A cloud session with the lockfile in place (same environment, 28 September 2026) showed:

- **Evidence.** With renv's autoloader on, R started in the repository root could not find
  testthat, yaml, sf, terra or sdmTMB. `renv::restore()` failed at igraph, whose binary
  needs the system library `libglpk.so.40`. `R CMD check` in a scratchpad still gave
  `Status: OK`. The report's timings were not available to the main session.
- **Interpretation.** renv points R at an empty project library and ignores the system
  library that `cloud/setup.sh` filled. The lockfile pins the versions the cloud already
  has, so restoring it there would change nothing today.
- **Decision.** Cloud sessions switch the autoloader off with
  `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE` in the `env` block of `.claude/settings.json`,
  which the documentation says is read in cloud sessions on a single repository and
  travels with the repository. The lockfile governs the laptop, where real-data runs
  happen. Restoring it in the cloud (which needs `libglpk40` and a time check against the
  five-minute budget) is deferred until the lockfile and the installed versions can
  drift apart, probably at M1.

## Open points

- **Spec wording.** The check session proposed a note in docs/spec.md, Section 11, that
  M0's cloud check tests the scaffold only, and that the first check on synthetic data
  comes with `synth`. This needs the project lead's decision.
- **renv in the cloud.** Whether the environment variable in `.claude/settings.json`
  takes effect in a cloud session is checked in section 3 below once verified; see the
  result recorded there.
- **Earlier environments.** `nansenbiomass` holds a stale cache and can be archived;
  `NN` has the R hosts added, which other projects do not need.
