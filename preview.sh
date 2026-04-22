#!/bin/bash
# ---------------------------------------------------------------------------
# preview.sh — run ddev-hosted CI scripts locally
#
# Run from your TYPO3 project root (the directory containing .ddev/).
#
# Usage:
#   preview.sh [deploy|stop|import-db|export-db]
#
#   deploy      — rsync and configure the preview environment
#   stop        — tear down the preview environment
#   import-db   — import a SQL dump into the preview database
#                   cat database.sql | preview.sh import-db
#                   zcat database.sql.gz | preview.sh import-db
#                   DB_FILE=database.sql preview.sh import-db
#                   DB_FILE=database.sql.gz preview.sh import-db
#   export-db   — dump the preview database to stdout (or DB_FILE)
#                   preview.sh export-db > database.sql
#                   DB_FILE=database.sql preview.sh export-db
#
# Auto-detects:
#   - Project name    from .ddev/config.yaml
#   - Git branch      from git rev-parse
#   - SSH key         first of ~/.ssh/id_ed25519, ~/.ssh/id_ecdsa, ~/.ssh/id_rsa
#
# Optional overrides (env vars):
#   PREVIEW_SERVER_HOST   default: deploy.mayfly.live
#   PREVIEW_SERVER_USER   default: deploy
#   PREVIEW_DOMAIN        default: mayfly.live
#   SSH_KEY_FILE          path to private key (overrides auto-detect)
#   DB_FILE               path to .sql dump (import-db and export-db)
# ---------------------------------------------------------------------------

set -euo pipefail

COMMAND=${1:-deploy}
IMAGE="ghcr.io/mikestreety/ddev-hosted:latest"

# ── validate command ─────────────────────────────────────────────────────────
case "$COMMAND" in
  deploy|stop|import-db|export-db) ;;
  *)
    echo "Usage: $0 [deploy|stop|import-db|export-db]" >&2
    exit 1
    ;;
esac

# ── server config ────────────────────────────────────────────────────────────
PREVIEW_SERVER_HOST=${PREVIEW_SERVER_HOST:-deploy.mayfly.live}
PREVIEW_SERVER_USER=${PREVIEW_SERVER_USER:-deploy}
PREVIEW_DOMAIN=${PREVIEW_DOMAIN:-mayfly.live}

# ── project name from .ddev/config.yaml ──────────────────────────────────────
if [ ! -f ".ddev/config.yaml" ]; then
  echo "Error: .ddev/config.yaml not found — run from your project root" >&2
  exit 1
fi
CI_PROJECT_NAME=$(grep '^name:' .ddev/config.yaml | awk '{print $2}')
if [ -z "$CI_PROJECT_NAME" ]; then
  echo "Error: could not read 'name:' from .ddev/config.yaml" >&2
  exit 1
fi

# ── git branch ───────────────────────────────────────────────────────────────
CI_COMMIT_REF_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [ -z "$CI_COMMIT_REF_NAME" ]; then
  echo "Error: could not determine current git branch" >&2
  exit 1
fi

# ── SSH key ──────────────────────────────────────────────────────────────────
SSH_KEY_FILE=${SSH_KEY_FILE:-}
if [ -z "$SSH_KEY_FILE" ]; then
  for candidate in ~/.ssh/id_ed25519 ~/.ssh/id_ecdsa ~/.ssh/id_rsa; do
    if [ -f "$candidate" ]; then
      SSH_KEY_FILE="$candidate"
      break
    fi
  done
fi
if [ -z "$SSH_KEY_FILE" ]; then
  echo "Error: no SSH key found in ~/.ssh/ — set SSH_KEY_FILE to your private key path" >&2
  exit 1
fi

echo "[preview] Command:  ${COMMAND}"
echo "[preview] Project:  ${CI_PROJECT_NAME}"
echo "[preview] Branch:   ${CI_COMMIT_REF_NAME}"
echo "[preview] Server:   ${PREVIEW_SERVER_USER}@${PREVIEW_SERVER_HOST}"
echo "[preview] Domain:   ${PREVIEW_DOMAIN}"
echo "[preview] SSH key:  ${SSH_KEY_FILE}"

# ── helpers for import-db / export-db ────────────────────────────────────────

# resolve_slug — populates $SLUG via one SSH round-trip for PREVIEW_USER.
# Mirrors lib.sh:compute_slug — keep in sync if that function changes.
resolve_slug() {
  PREVIEW_USER=$(ssh -i "$SSH_KEY_FILE" \
    "${PREVIEW_SERVER_USER}@${PREVIEW_SERVER_HOST}" 'whoami')
  local _name _hash _suffix _maxname
  _name=$(printf '%s' "$CI_PROJECT_NAME" \
    | tr '[:upper:]' '[:lower:]' \
    | tr ' _' '-' \
    | tr -cs 'a-z0-9-' '-' \
    | sed 's/^-//;s/-$//')
  _hash=$(printf '%s' "$CI_COMMIT_REF_NAME" | sha256sum | cut -c1-10)
  _suffix="-${_hash}.${PREVIEW_USER}.${PREVIEW_DOMAIN}"
  _maxname=$(( 253 - ${#_suffix} ))
  (( _maxname > 30 )) && _maxname=30
  _name="${_name:0:${_maxname}}"
  _name=$(printf '%s' "$_name" | sed 's/-*$//')
  SLUG="${_name}-${_hash}"
}

# ── import-db — direct SSH, no Docker ────────────────────────────────────────
if [ "$COMMAND" = "import-db" ]; then

  if [ -n "${DB_FILE:-}" ]; then
    if [ ! -s "$DB_FILE" ]; then
      echo "[preview] ERROR: DB_FILE '${DB_FILE}' is empty or does not exist" >&2
      exit 1
    fi
    case "$DB_FILE" in
      *.sql.gz) exec 0< <(gunzip -c "$DB_FILE") ;;
      *.sql)    exec 0< "$DB_FILE" ;;
      *)
        echo "[preview] ERROR: DB_FILE must have a .sql or .sql.gz extension" >&2
        exit 1
        ;;
    esac
    echo "[preview] DB_FILE:   ${DB_FILE}"
  elif [ -t 0 ]; then
    echo "[preview] ERROR: import-db requires SQL on stdin — pipe a dump file or set DB_FILE" >&2
    echo "[preview]   e.g.: cat database.sql | $0 import-db" >&2
    echo "[preview]         DB_FILE=database.sql $0 import-db" >&2
    exit 1
  fi

  resolve_slug
  echo "[preview] Slug:     ${SLUG}"
  echo "[preview] Importing database..."

  ssh -i "$SSH_KEY_FILE" \
    "${PREVIEW_SERVER_USER}@${PREVIEW_SERVER_HOST}" \
    "bash /opt/preview-scripts/import-preview-db.sh '${SLUG}'"
  exit 0
fi

# ── export-db — direct SSH, no Docker ────────────────────────────────────────
if [ "$COMMAND" = "export-db" ]; then

  resolve_slug
  echo "[preview] Slug:     ${SLUG}" >&2
  echo "[preview] Exporting database..." >&2

  if [ -n "${DB_FILE:-}" ]; then
    echo "[preview] Writing to ${DB_FILE}" >&2
    ssh -i "$SSH_KEY_FILE" \
      "${PREVIEW_SERVER_USER}@${PREVIEW_SERVER_HOST}" \
      "bash /opt/preview-scripts/export-preview-db.sh '${SLUG}'" > "$DB_FILE"
  else
    ssh -i "$SSH_KEY_FILE" \
      "${PREVIEW_SERVER_USER}@${PREVIEW_SERVER_HOST}" \
      "bash /opt/preview-scripts/export-preview-db.sh '${SLUG}'"
  fi
  exit 0
fi

# ── deploy / stop via Docker ──────────────────────────────────────────────────
docker run --rm \
  -v "$(pwd):/workspace" \
  -w /workspace \
  -e "SSH_PRIVATE_KEY=$(cat "$SSH_KEY_FILE")" \
  -e "PREVIEW_SERVER_HOST=${PREVIEW_SERVER_HOST}" \
  -e "PREVIEW_SERVER_USER=${PREVIEW_SERVER_USER}" \
  -e "PREVIEW_DOMAIN=${PREVIEW_DOMAIN}" \
  -e "CI_PROJECT_NAME=${CI_PROJECT_NAME}" \
  -e "CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME}" \
  "$IMAGE" \
  "preview-${COMMAND}"
