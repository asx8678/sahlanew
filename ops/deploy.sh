#!/usr/bin/env bash
set -euo pipefail

# Deploy a Sahla release tarball with migrations, health gate, and automatic
# rollback on failure.  Run as the deploy user from the build server or CI.
#
# Usage: ops/deploy.sh <git-sha>
#
# Expects the release tarball at /tmp/sahla-<sha>.tar.gz and installs it under
# /opt/sahla/releases/<sha>.  A symlink at /opt/sahla/current is flipped after
# migrations succeed; if the health gate fails the previous release is restored.

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <git-sha>" >&2
  exit 1
fi

SHA="$1"
TARBALL="/tmp/sahla-${SHA}.tar.gz"
RELEASE_ROOT="/opt/sahla/releases"
RELEASE_DIR="${RELEASE_ROOT}/${SHA}"
CURRENT_LINK="/opt/sahla/current"
SHARED_DIR="/opt/sahla/shared"
PREVIOUS_LINK="$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)"

if [ ! -f "$TARBALL" ]; then
  echo "Release tarball not found: $TARBALL" >&2
  exit 1
fi

if [ -d "$RELEASE_DIR" ]; then
  echo "Release directory already exists: $RELEASE_DIR" >&2
  exit 1
fi

echo "==> Extracting release ${SHA}"
mkdir -p "$RELEASE_ROOT"
tar -xzf "$TARBALL" -C "$RELEASE_ROOT"

# Ensure the shared uploads directory exists and is reachable from the release.
echo "==> Linking shared uploads directory"
mkdir -p "${SHARED_DIR}/uploads"
ln -sfn "${SHARED_DIR}/uploads" "${RELEASE_DIR}/uploads"

echo "==> Running migrations"
# shellcheck source=/etc/sahla/app.env
. /etc/sahla/app.env
export DATABASE_URL SECRET_KEY_BASE PHX_HOST CLOAK_KEY HMAC_KEY \
  PORT POOL_SIZE SMS_PROVIDER SMS_API_KEY SMS_SENDER POSTMARK_API_KEY \
  TURNSTILE_SITE_KEY TURNSTILE_SECRET UPLOADS_DIR SENTRY_DSN PLAUSIBLE_DOMAIN \
  DNS_CLUSTER_QUERY MAIL_FROM_NAME MAIL_FROM_EMAIL

"${RELEASE_DIR}/bin/sahla" eval "Sahla.Release.migrate()"

echo "==> Flipping current symlink"
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"

echo "==> Restarting service"
systemctl restart sahla

# Wait for the endpoint to come up.  The exact timing depends on ERTS boot,
# so we retry a few times before giving up.
echo "==> Running health gate"
PORT="${PORT:-4000}"
HEALTH_URL="http://127.0.0.1:${PORT}/health"
for i in $(seq 1 30); do
  if curl -fsS "$HEALTH_URL" >/dev/null; then
    echo "==> Health gate passed"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "==> Health gate failed after 30 attempts" >&2

    if [ -n "$PREVIOUS_LINK" ] && [ -d "$PREVIOUS_LINK" ]; then
      echo "==> Rolling back to previous release: $PREVIOUS_LINK"
      ln -sfn "$PREVIOUS_LINK" "$CURRENT_LINK"
      systemctl restart sahla
    else
      echo "==> No previous release to roll back to" >&2
    fi

    exit 1
  fi
  sleep 1
done

echo "==> Pruning old releases (keeping newest 5)"
cd "$RELEASE_ROOT"
ls -1t | tail -n +6 | xargs -r rm -rf

echo "==> Deploy complete: ${SHA}"
