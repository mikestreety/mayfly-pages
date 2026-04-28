#!/bin/bash
# ---------------------------------------------------------------------------
# preview.sh — run mayfly CI scripts locally
#
# Run from your project root (the directory containing .ddev/).
#
# Usage:
#   preview.sh [deploy|delete|stop|import-db|export-db] [<slug>]
#
#   deploy      — rsync and configure the preview environment
#   delete      — tear down the preview environment (aliases: teardown)
#   stop        — stop containers without removing data (aliases: shutdown)
#   import-db   — import a SQL dump into the preview database
#                   cat database.sql    | preview.sh import-db
#                   zcat database.sql.gz | preview.sh import-db
#                   DB_FILE=database.sql    preview.sh import-db
#                   DB_FILE=database.sql.gz preview.sh import-db
#   export-db   — dump the preview database to stdout (or DB_FILE)
#                   preview.sh export-db > database.sql
#                   DB_FILE=database.sql preview.sh export-db
#
#   <slug>      — optional preview slug (e.g. myproject-abc123); skips
#                   auto-detection of project name and branch. Useful when
#                   running outside the project directory or off the branch.
#                   Not supported with 'deploy'.
#                   e.g.: preview.sh stop myproject-abc123
#
# Auto-detects:
#   - Project name    from .ddev/config.yaml
#   - Git branch      from git rev-parse
#   - SSH key         first of ~/.ssh/id_ed25519, ~/.ssh/id_ecdsa, ~/.ssh/id_rsa
#
# Optional overrides (env vars):
#   PREVIEW_SERVER_HOST   default: host.mayfly.live
#   PREVIEW_SERVER_USER   default: deploy
#   PREVIEW_DOMAIN        default: mayfly.live
#   SSH_KEY_FILE          path to private key (overrides auto-detect)
#   DB_FILE               path to .sql/.sql.gz dump (import-db and export-db)
# ---------------------------------------------------------------------------

set -euo pipefail

COMMAND=${1:-deploy}
SLUG_OVERRIDE=${2:-}
IMAGE="ghcr.io/mayfly-live/mayfly:latest"

# ── validate and normalise command ───────────────────────────────────────────
case "$COMMAND" in
  deploy|delete|teardown|stop|shutdown|import-db|export-db) ;;
  *)
    echo "Usage: $0 [deploy|delete|stop|import-db|export-db] [<slug>]" >&2
    exit 1
    ;;
esac
case "$COMMAND" in
  teardown) COMMAND=delete ;;
  shutdown) COMMAND=stop ;;
esac

if [ -n "$SLUG_OVERRIDE" ] && [ "$COMMAND" = "deploy" ]; then
  echo "Error: slug override is not supported with 'deploy'" >&2
  exit 1
fi

# ── server config ────────────────────────────────────────────────────────────
PREVIEW_SERVER_HOST=${PREVIEW_SERVER_HOST:-host.mayfly.live}
PREVIEW_SERVER_USER=${PREVIEW_SERVER_USER:-deploy}
PREVIEW_DOMAIN=${PREVIEW_DOMAIN:-mayfly.live}

# ── project name and branch ──────────────────────────────────────────────────
# Skipped when a slug is passed directly (non-deploy commands only).
CI_PROJECT_NAME=""
CI_COMMIT_REF_NAME=""
if [ -z "$SLUG_OVERRIDE" ]; then
  if [ ! -f ".ddev/config.yaml" ]; then
    echo "Error: .ddev/config.yaml not found — run from your project root" >&2
    exit 1
  fi
  CI_PROJECT_NAME=$(grep '^name:' .ddev/config.yaml | awk '{print $2}')
  if [ -z "$CI_PROJECT_NAME" ]; then
    echo "Error: could not read 'name:' from .ddev/config.yaml" >&2
    exit 1
  fi

  CI_COMMIT_REF_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [ -z "$CI_COMMIT_REF_NAME" ]; then
    echo "Error: could not determine current git branch" >&2
    exit 1
  fi
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

# If the key is passphrase-protected, decrypt it to a temp file so the Docker
# container can load it non-interactively (ssh-add can't prompt through a pipe).
SSH_KEY_TMP=""
if ! ssh-keygen -y -P "" -f "$SSH_KEY_FILE" &>/dev/null; then
  echo "[preview] Key is passphrase-protected — enter passphrase to decrypt for this session"
  SSH_KEY_TMP=$(mktemp)
  chmod 600 "$SSH_KEY_TMP"
  cp "$SSH_KEY_FILE" "$SSH_KEY_TMP"
  if ! ssh-keygen -p -N "" -f "$SSH_KEY_TMP"; then
    rm -f "$SSH_KEY_TMP"
    echo "Error: failed to decrypt SSH key" >&2
    exit 1
  fi
  SSH_KEY_FILE="$SSH_KEY_TMP"
fi

echo "[preview] Command: ${COMMAND}"
if [ -n "$SLUG_OVERRIDE" ]; then
  echo "[preview] Slug:    ${SLUG_OVERRIDE}"
else
  echo "[preview] Project: ${CI_PROJECT_NAME}"
  echo "[preview] Branch:  ${CI_COMMIT_REF_NAME}"
fi
echo "[preview] SSH key: ${SSH_KEY_FILE}"

# ── import-db: normalise input to a plain-SQL file in the workspace ──────────
IMPORT_TMP=""
if [ "$COMMAND" = "import-db" ]; then
  if [ -n "${DB_FILE:-}" ]; then
    if [ ! -s "$DB_FILE" ]; then
      echo "[preview] ERROR: DB_FILE '${DB_FILE}' is empty or does not exist" >&2
      exit 1
    fi
    echo "[preview] DB_FILE:   ${DB_FILE}"
    case "$DB_FILE" in
      *.sql.gz)
        IMPORT_TMP=".preview-import-$$.sql"
        gunzip -c "$DB_FILE" > "$IMPORT_TMP"
        ;;
      *.sql)
        if [[ "$DB_FILE" == /* ]]; then
          IMPORT_TMP=".preview-import-$$.sql"
          cp "$DB_FILE" "$IMPORT_TMP"
        else
          IMPORT_TMP="$DB_FILE"
        fi
        ;;
      *)
        echo "[preview] ERROR: DB_FILE must have a .sql or .sql.gz extension" >&2
        exit 1
        ;;
    esac
  elif ! [ -t 0 ]; then
    IMPORT_TMP=".preview-import-$$.sql"
    cat > "$IMPORT_TMP"
  else
    echo "[preview] ERROR: import-db requires SQL on stdin — pipe a dump file or set DB_FILE" >&2
    echo "[preview]   e.g.: cat database.sql | $0 import-db" >&2
    echo "[preview]         DB_FILE=database.sql $0 import-db" >&2
    exit 1
  fi
fi

# Ensure temp files are removed even on error
trap 'rm -f "${IMPORT_TMP:-}" "${SSH_KEY_TMP:-}"' EXIT

# ── run via Docker ────────────────────────────────────────────────────────────
DOCKER_ARGS=(
  --rm
  -v "$(pwd):/workspace"
  -w /workspace
  -e "SSH_PRIVATE_KEY=$(cat "$SSH_KEY_FILE")"
  -e "PREVIEW_SERVER_HOST=${PREVIEW_SERVER_HOST}"
  -e "PREVIEW_SERVER_USER=${PREVIEW_SERVER_USER}"
  -e "PREVIEW_DOMAIN=${PREVIEW_DOMAIN}"
  -e "CI_PROJECT_NAME=${CI_PROJECT_NAME}"
  -e "CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME}"
)
[ -n "$SLUG_OVERRIDE" ] && DOCKER_ARGS+=(-e "PREVIEW_SLUG=${SLUG_OVERRIDE}")
[ -n "$IMPORT_TMP" ] && DOCKER_ARGS+=(-e "DB_FILE=${IMPORT_TMP}")

if [ "$COMMAND" = "export-db" ] && [ -n "${DB_FILE:-}" ]; then
  echo "[preview] Writing to ${DB_FILE}" >&2
  docker run "${DOCKER_ARGS[@]}" "$IMAGE" "preview-export-db" > "$DB_FILE"
else
  docker run "${DOCKER_ARGS[@]}" "$IMAGE" "preview-${COMMAND}"
fi
