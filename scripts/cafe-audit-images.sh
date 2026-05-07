#!/usr/bin/env bash
# Audit: images OQS (build-oqs, runtime-oqs) — Docker Scout, rapport Markdown.
# Compatible bash 3.2+ (macOS). Pas de module Go dans ce dépôt.
#
# Prérequis: docker, extension Docker Scout. Variables: IMAGE_PREFIX, IMAGE_TAG, OQS_BASE, REPORT_DIR, SKIP_SCOUT, SCOUT_INTERMEDIATE.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_PREFIX="${IMAGE_PREFIX:-oleglod}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
IMAGE_TAG="${IMAGE_TAG:-cafe-audit-$RUN_ID}"
REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
REPORT_FILE="${REPORT_FILE:-$REPORT_DIR/cafe-crypto-backend-security-audit-$RUN_ID.md}"
OQS_BASE="${OQS_BASE:-oleglod/cafe-crypto-backend}"
SKIP_SCOUT="${SKIP_SCOUT:-0}"
SCOUT_INTERMEDIATE="${SCOUT_INTERMEDIATE:-0}"

info()  { printf '%s\n' "→ $*"; }
warn()  { printf '%s\n' "⚠ $*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

scout_parse() {
  tr -d '\033' | grep -E 'Target[[:space:]]+│' | head -1 | \
    sed -E 's/.*[[:space:]]([0-9]+)C[[:space:]]+([0-9]+)H[[:space:]]+([0-9]+)M[[:space:]]+([0-9]+)L.*/C=\1 H=\2 M=\3 L=\4/' || echo "C=? H=? M=? L=?"
}
scout_qv() {
  local img="$1"
  [ "$SKIP_SCOUT" = 1 ] && { echo "SKIP_SCOUT=1"; return; }
  have docker && docker scout version >/dev/null 2>&1 || { echo "Scout n/a"; return; }
  docker scout quickview "local://$img" 2>&1 | scout_parse
}
should_scout() {
  [ "$SCOUT_INTERMEDIATE" = 1 ] && return 0
  case "$1" in *:build-oqs) return 1 ;; esac
  return 0
}

# Variables scalaires (bash 3.2 — pas de tableaux associatifs)
IM_BUILD=""
IM_RUN=""
SC_BUILD=""
SC_RUN=""
OK_BUILD=0
OK_RUN=0

main() {
  mkdir -p "$REPORT_DIR"
  info "REPO_ROOT=$REPO_ROOT"

  IM_BUILD="${OQS_BASE}:build-oqs"
  IM_RUN="${OQS_BASE}:runtime-oqs"

  if ( cd "$REPO_ROOT" && docker build -f docker/Dockerfile-oqs --target build-oqs -t "$IM_BUILD" . ); then
    OK_BUILD=1
  else
    OK_BUILD=0
    warn "build-oqs a échoué"
  fi

  if ( cd "$REPO_ROOT" && docker build -f docker/Dockerfile-oqs --target runtime-oqs -t "$IM_RUN" . ); then
    OK_RUN=1
    docker tag "$IM_RUN" "${IMAGE_PREFIX}/cafe-crypto-backend:${IMAGE_TAG}" 2>/dev/null || true
  else
    OK_RUN=0
    warn "runtime-oqs a échoué"
  fi

  if [ "$OK_BUILD" = 1 ]; then
    if ! should_scout "$IM_BUILD"; then SC_BUILD="interm. (SCOUT_INTERMEDIATE=1)"
    elif [ "$SKIP_SCOUT" = 1 ]; then SC_BUILD=SKIP
    else SC_BUILD=$(scout_qv "$IM_BUILD" || true); fi
  else SC_BUILD="build KO"; fi

  if [ "$OK_RUN" = 1 ]; then
    if ! should_scout "$IM_RUN"; then SC_RUN="interm. (SCOUT_INTERMEDIATE=1)"
    elif [ "$SKIP_SCOUT" = 1 ]; then SC_RUN=SKIP
    else SC_RUN=$(scout_qv "$IM_RUN" || true); fi
  else SC_RUN="build KO"; fi

  {
    echo "# cafe-crypto-backend — audit images"
    echo "- Généré: $(date -u '+%Y-%m-%d %H:%M UTC')"
    echo "- Dépôt: \`$REPO_ROOT\`"
    echo ""
    echo "## Synthèse (Docker Scout quickview, ligne Target)"
    echo "| id | image | build | C/H/M/L |"
    echo "|---|----|----|----|"
    b1="✗"; [ "$OK_BUILD" = 1 ] && b1="✓"
    b2="✗"; [ "$OK_RUN" = 1 ] && b2="✓"
    echo "| \`build_oqs\` | \`$IM_BUILD\` | $b1 | $SC_BUILD |"
    echo "| \`runtime_oqs\` | \`$IM_RUN\` | $b2 | $SC_RUN |"
    echo ""
    echo "## Détail CVE (docker scout cves --format markdown)"
    if [ "$OK_BUILD" = 1 ] && should_scout "$IM_BUILD" && [ "$SKIP_SCOUT" != 1 ] && docker scout version >/dev/null 2>&1; then
      echo "### build_oqs"
      docker scout cves "local://$IM_BUILD" --format markdown 2>&1 || true
      echo ""
    fi
    if [ "$OK_RUN" = 1 ] && should_scout "$IM_RUN" && [ "$SKIP_SCOUT" != 1 ] && docker scout version >/dev/null 2>&1; then
      echo "### runtime_oqs"
      docker scout cves "local://$IM_RUN" --format markdown 2>&1 || true
      echo ""
    fi
  } > "$REPORT_FILE"
  info "Rapport: $REPORT_FILE"
}

main
