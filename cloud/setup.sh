#!/usr/bin/env bash
# cloud/setup.sh: provision a Claude Code cloud environment for nansenbiomass
#
# What it does
#   1. Installs R from CRAN's Ubuntu repository (noble-cran40).
#   2. Installs the runtime libraries that the precompiled sf and terra binaries
#      link against (GDAL, GEOS, PROJ, udunits), and, at the same time, the R
#      tooling packages (renv, testthat, roxygen2, yaml).
#   3. Installs the spatial packages (sf, terra, sdmTMB) as precompiled Linux
#      binaries from Posit Package Manager (P3M), and configures R so that later
#      installs, including renv::restore(), also use binaries.
#   4. If the repository already holds an renv.lock, restores it, which fills the
#      renv cache so that restores in later sessions are fast.
#
# Why it is lean
#   Everything is installed as binaries, so no compilers or development headers
#   are installed: an earlier version that installed libgdal-dev and r-base-dev
#   (371 packages with their dependencies, against 135 for the runtime libraries)
#   exceeded the roughly five-minute setup budget. The consequence is that this
#   environment cannot compile R packages from source. That is not needed for M0
#   or M1; revisit it at M2 (StoX packages) and M3 (sdmTMBexperiments).
#
# How to use it
#   Paste this file into the environment's "Setup script" field (cloud environment
#   menu in the session's title bar, then Edit). It runs as root on Ubuntu 24.04,
#   with the repository cloned, before Claude Code starts. If it finishes within
#   roughly five minutes the result is cached, and later sessions skip it; the
#   cache is rebuilt when the script or the allowed hosts change, and after about
#   seven days. A script that runs longer can make the session fail to start with a
#   generic error. A non-zero exit also stops the session from starting, so only
#   stages whose failure would leave R unusable are allowed to fail.
#
# Network allowlist (custom allowed domains, with the default list included)
#   archive.ubuntu.com, security.ubuntu.com  Ubuntu packages (in the default list)
#   cloud.r-project.org                      R itself and the CRAN apt signing key
#   p3m.dev                                  binary R packages
#   packagemanager.posit.co                  former P3M address, still used by some tools
#   Needed only from later milestones:
#   stoxproject.github.io                    StoX R packages (M2)
#   github.com, api.github.com,
#   codeload.github.com                      sdmTMBexperiments from GitHub (M3; default list)
#
# Timing
#   Each stage prints its elapsed time. The first run of the earlier version
#   reached the CRAN repository (R 4.6.1) but ran out of time installing
#   development libraries; this version has not yet been timed end to end.
#
# Data
#   This script installs software only. It reads no data and must never be
#   extended to fetch any (CLAUDE.md; docs/spec.md, Section 3).

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

UBUNTU_CODENAME="noble"
CRAN_APT="https://cloud.r-project.org/bin/linux/ubuntu"
P3M_REPO="https://p3m.dev/cran/__linux__/${UBUNTU_CODENAME}/latest"
TOOL_PACKAGES="renv testthat roxygen2 yaml"
SPATIAL_PACKAGES="sf terra sdmTMB"
# Runtime libraries only; the binaries from P3M are built against these.
SPATIAL_LIBS=(libgdal34t64 libgeos-c1t64 libproj25 libudunits2-0)

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

LOG_DIR=/tmp/nansenbiomass-setup
mkdir -p "$LOG_DIR"

start=$SECONDS
stage() { printf '\n[setup %4ds] %s\n' "$((SECONDS - start))" "$*"; }

# Installs the R packages named in $1 and stops if any is missing afterwards
# (install.packages() itself only warns).
install_r_packages() {
  R_PACKAGES="$1" Rscript -e '
    pkgs <- strsplit(Sys.getenv("R_PACKAGES"), " ", fixed = TRUE)[[1]]
    install.packages(pkgs)
    missing <- setdiff(pkgs, rownames(installed.packages()))
    if (length(missing) > 0) {
      stop("Not installed: ", paste(missing, collapse = ", "))
    }
  '
}

# apt reads only Ubuntu's own archive and CRAN, so the third-party sources in the
# base image (PPAs, Docker) cannot fail the run under a narrow allowlist.
APT_DIR=/etc/apt/nansenbiomass.sources.d
APT_OPTS=(-o "Dir::Etc::SourceList=/dev/null" -o "Dir::Etc::SourceParts=${APT_DIR}")

stage "Configuring apt sources (Ubuntu archive and CRAN)"
$SUDO mkdir -p "$APT_DIR"
if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
  $SUDO cp /etc/apt/sources.list.d/ubuntu.sources "$APT_DIR/ubuntu.sources"
else
  $SUDO cp /etc/apt/sources.list "$APT_DIR/ubuntu.list"
fi
curl -fsSL "${CRAN_APT}/marutter_pubkey.asc" |
  $SUDO tee /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc >/dev/null
echo "deb ${CRAN_APT} ${UBUNTU_CODENAME}-cran40/" |
  $SUDO tee "$APT_DIR/cran.list" >/dev/null

stage "Installing R"
$SUDO apt-get "${APT_OPTS[@]}" update -qq
# libxml2 is needed by the xml2 binary that roxygen2 depends on.
$SUDO apt-get "${APT_OPTS[@]}" install -y -qq --no-install-recommends r-base-core libxml2
R --version | head -n 1

stage "Configuring R to install binary packages from P3M"
RPROFILE_SITE="$(R RHOME)/etc/Rprofile.site"
if ! grep -q 'nansenbiomass setup' "$RPROFILE_SITE" 2>/dev/null; then
  $SUDO tee -a "$RPROFILE_SITE" >/dev/null <<EOF

# nansenbiomass setup: binary packages from Posit Package Manager
local({
  options(
    repos = c(CRAN = "${P3M_REPO}"),
    # P3M serves Linux binaries only when the user agent names R and the platform
    HTTPUserAgent = sprintf(
      "R/%s R (%s)", getRversion(),
      paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])
    ),
    Ncpus = max(1L, parallel::detectCores())
  )
})
EOF
fi
# renv::restore() otherwise uses the repositories recorded in renv.lock, which
# on a Windows laptop serve no Linux binaries.
RENVIRON_SITE="$(R RHOME)/etc/Renviron.site"
if ! grep -q 'RENV_CONFIG_REPOS_OVERRIDE' "$RENVIRON_SITE" 2>/dev/null; then
  echo "RENV_CONFIG_REPOS_OVERRIDE=${P3M_REPO}" | $SUDO tee -a "$RENVIRON_SITE" >/dev/null
fi

# The spatial libraries (apt) and the tooling packages (R) do not depend on each
# other, so they are installed at the same time.
stage "Installing spatial libraries and R tooling packages (${TOOL_PACKAGES}) in parallel"
$SUDO apt-get "${APT_OPTS[@]}" install -y -qq --no-install-recommends "${SPATIAL_LIBS[@]}" \
  >"$LOG_DIR/apt-spatial.log" 2>&1 &
apt_pid=$!
install_r_packages "$TOOL_PACKAGES" >"$LOG_DIR/r-tools.log" 2>&1 &
tools_pid=$!
apt_status=0
wait "$apt_pid" || apt_status=$?
tools_status=0
wait "$tools_pid" || tools_status=$?
if [ "$apt_status" -ne 0 ] || [ "$tools_status" -ne 0 ]; then
  echo "Parallel stage failed (apt: $apt_status, R tooling: $tools_status). Last log lines:"
  tail -n 30 "$LOG_DIR/apt-spatial.log" "$LOG_DIR/r-tools.log"
  exit 1
fi

stage "Installing spatial R packages: ${SPATIAL_PACKAGES}"
install_r_packages "$SPATIAL_PACKAGES"

stage "Checking the installation"
R_PACKAGES="$TOOL_PACKAGES $SPATIAL_PACKAGES" Rscript -e '
  pkgs <- strsplit(Sys.getenv("R_PACKAGES"), " ", fixed = TRUE)[[1]]
  for (p in pkgs) {
    # Loading, not just finding, confirms that the binaries link correctly.
    suppressPackageStartupMessages(loadNamespace(p))
    cat(sprintf("%-10s %s\n", p, format(packageVersion(p))))
  }
  print(sf::sf_extSoftVersion()[c("GEOS", "GDAL", "proj.4")])
  cat("terra linked to GDAL", terra::gdal(), "\n")
'

# Restoring the lockfile is useful but not essential here: a failure is reported
# and the session still starts, so it can be investigated from within it.
REPO_DIR=""
for d in "${NANSENBIOMASS_DIR:-}" "$PWD" /home/user/nansenbiomass; do
  if [ -n "$d" ] && [ -f "$d/DESCRIPTION" ] &&
    grep -q '^Package: nansenbiomass$' "$d/DESCRIPTION"; then
    REPO_DIR="$d"
    break
  fi
done
if [ -n "$REPO_DIR" ] && [ -f "$REPO_DIR/renv.lock" ]; then
  stage "Restoring renv.lock in ${REPO_DIR}"
  (cd "$REPO_DIR" && Rscript -e 'renv::restore(prompt = FALSE)') ||
    echo "WARNING: renv::restore() failed; run it in the session to see why."
else
  stage "No renv.lock found; skipping renv::restore()"
fi

stage "Done"
