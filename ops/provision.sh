#!/usr/bin/env bash
#
# provision.sh — one-shot, idempotent bootstrap for a fresh Ubuntu 24.04 LTS VPS.
#
# Brings a bare box to the baseline described in docs/fplansahla.md §13.2:
#   system deploy user, nginx + PostgreSQL 16 + certbot + hardening (ufw,
#   fail2ban, unattended-upgrades), a least-privilege Postgres role/DB with
#   pg_trgm + citext, tuned Postgres config, and the /opt/sahla directory layout.
#
# USAGE (run as root on the target box):
#     sudo ./provision.sh [DB_PASSWORD]
#
#   - DB_PASSWORD is the password for the least-privilege `sahla` Postgres role.
#   - If omitted, the script prompts for it interactively (input hidden).
#   - The password is NEVER hardcoded, committed, echoed, or written to a
#     world-readable file. Store it in /etc/sahla/app.env (created by a later
#     task, chmod 600, owner deploy) as part of DATABASE_URL.
#
# IDEMPOTENT: safe to run repeatedly. Every step is guarded or naturally
# idempotent; a second run makes no changes and prints a summary.
#
# What this script deliberately does NOT do (separate bd tasks):
#   - nginx vhost, systemd unit, /etc/sahla/app.env, deploy.sh, TLS certs.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly APP="sahla"
readonly DEPLOY_USER="deploy"
readonly APP_HOME="/opt/${APP}"
readonly ETC_DIR="/etc/${APP}"
readonly DB_ROLE="sahla"
readonly DB_NAME="sahla_prod"
readonly PG_VERSION="16"
readonly PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"
readonly PG_TUNING_CONF="${PG_CONF_DIR}/conf.d/${APP}-tuning.conf"

log() { printf '\n=== %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: must run as root (try: sudo $0)" >&2
  exit 1
fi

# DB password: first argument, else interactive prompt. Never defaulted.
DB_PASSWORD="${1:-}"
if [[ -z "${DB_PASSWORD}" ]]; then
  # -s hides input so the secret never appears on screen or in scrollback.
  read -r -s -p "Password for Postgres role '${DB_ROLE}': " DB_PASSWORD
  echo
fi
if [[ -z "${DB_PASSWORD}" ]]; then
  echo "ERROR: DB password must not be empty" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# 1. System deploy user/group (home /opt/sahla)
#    Guard on `id -u` so a second run does not fail on an existing user.
# ---------------------------------------------------------------------------
log "Deploy user"
if id -u "${DEPLOY_USER}" >/dev/null 2>&1; then
  echo "user '${DEPLOY_USER}' already exists — skipping"
else
  adduser --system --group --home "${APP_HOME}" "${DEPLOY_USER}"
  echo "created system user/group '${DEPLOY_USER}' (home ${APP_HOME})"
fi

# ---------------------------------------------------------------------------
# 2. Packages
#    apt-get install -y is idempotent: already-installed packages are no-ops.
# ---------------------------------------------------------------------------
log "APT packages"
apt-get update
apt-get install -y \
  nginx \
  "postgresql-${PG_VERSION}" \
  "postgresql-contrib-${PG_VERSION}" \
  certbot \
  python3-certbot-nginx \
  ufw \
  unattended-upgrades \
  fail2ban \
  age

# ---------------------------------------------------------------------------
# 3. Firewall (ufw): allow SSH + HTTP/HTTPS, then enable.
#    `ufw allow` is idempotent (re-adding an existing rule is a no-op).
#    `ufw --force enable` avoids the interactive y/n prompt and is a no-op
#    when ufw is already active.
# ---------------------------------------------------------------------------
log "Firewall (ufw)"
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable
ufw status verbose

# ---------------------------------------------------------------------------
# 4. Hardening services: fail2ban + unattended-upgrades.
#    `systemctl enable --now` is idempotent (enables + starts; no-op if both).
# ---------------------------------------------------------------------------
log "Hardening services"
systemctl enable --now fail2ban
# The APT periodic upgrade runs via the unattended-upgrades oneshot service /
# timers; enabling the unit ensures boot-time activation on all releases.
systemctl enable --now unattended-upgrades
# Ensure unattended-upgrades is actually turned on (dpkg-reconfigure writes
# /etc/apt/apt.conf.d/20auto-upgrades). Idempotent: rewrites the same file.
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# ---------------------------------------------------------------------------
# 5. PostgreSQL role, database, extensions.
#    Postgres is not a superuser on Ubuntu's default install; we act via the
#    `postgres` OS/DB superuser. Each step guards with a psql -tc existence
#    check so a second run changes nothing.
# ---------------------------------------------------------------------------
log "PostgreSQL role + database"
systemctl enable --now postgresql

# 5a. Least-privilege login role (no superuser/createdb/createrole).
#     ALTER ... PASSWORD on the (idempotent) re-run keeps the password in sync
#     with whatever was supplied this run. Password passed via psql variable so
#     it is never interpolated into the shell/logs; :'v' quotes it as a literal.
if [[ "$(sudo -u postgres psql -tAc \
      "SELECT 1 FROM pg_roles WHERE rolname = '${DB_ROLE}'")" == "1" ]]; then
  echo "role '${DB_ROLE}' exists — syncing password"
  sudo -u postgres psql -v pw="${DB_PASSWORD}" <<SQL
ALTER ROLE ${DB_ROLE} WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'pw';
SQL
else
  echo "creating least-privilege role '${DB_ROLE}'"
  sudo -u postgres psql -v pw="${DB_PASSWORD}" <<SQL
CREATE ROLE ${DB_ROLE} WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'pw';
SQL
fi

# 5b. Database owned by the app role.
#     CREATE DATABASE cannot run inside a transaction block / IF NOT EXISTS,
#     so guard with an existence check.
if [[ "$(sudo -u postgres psql -tAc \
      "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}'")" == "1" ]]; then
  echo "database '${DB_NAME}' exists — skipping"
else
  echo "creating database '${DB_NAME}' owned by '${DB_ROLE}'"
  sudo -u postgres createdb -O "${DB_ROLE}" "${DB_NAME}"
fi

# 5c. Extensions (need superuser). CREATE EXTENSION IF NOT EXISTS is idempotent.
echo "ensuring extensions pg_trgm + citext in '${DB_NAME}'"
sudo -u postgres psql -d "${DB_NAME}" <<'SQL'
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS citext;
SQL

# ---------------------------------------------------------------------------
# 6. PostgreSQL tuning (8GB box).
#    Ubuntu's default postgresql.conf ends with `include_dir = 'conf.d'`, so a
#    drop-in file cleanly overrides the shipped defaults without hand-editing
#    the main config (safer + idempotent). We overwrite the drop-in every run
#    with the exact §13.2 values, so the file is authoritative and stable.
# ---------------------------------------------------------------------------
log "PostgreSQL tuning"
mkdir -p "${PG_CONF_DIR}/conf.d"
cat > "${PG_TUNING_CONF}" <<'EOF'
# Managed by ops/provision.sh — do not edit by hand.
# Tuning baseline for a 4 vCPU / 8 GB box (docs/fplansahla.md §13.2, §13.7).
shared_buffers = 2GB
effective_cache_size = 5GB
work_mem = 16MB
maintenance_work_mem = 256MB
wal_compression = on
max_connections = 60
# Slow-query review (§13.7): log statements slower than 500ms.
log_min_duration_statement = 500
EOF
chown postgres:postgres "${PG_TUNING_CONF}"
chmod 644 "${PG_TUNING_CONF}"
# shared_buffers / max_connections require a full restart (not just reload).
systemctl restart postgresql
echo "wrote ${PG_TUNING_CONF} and restarted postgresql"

# ---------------------------------------------------------------------------
# 7. Directory layout.
#    mkdir -p, chown -R, chmod are all naturally idempotent.
# ---------------------------------------------------------------------------
log "Directory layout"
mkdir -p "${APP_HOME}/releases" "${APP_HOME}/shared/uploads" "${ETC_DIR}"
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${APP_HOME}"
# /etc/sahla holds app.env (secrets, created later): restrict to owner+group.
chown "${DEPLOY_USER}:${DEPLOY_USER}" "${ETC_DIR}"
chmod 750 "${ETC_DIR}"

# ---------------------------------------------------------------------------
# 8. Summary — a second run shows the same state, visibly no-op.
# ---------------------------------------------------------------------------
log "Provision summary"
echo "deploy user   : $(id "${DEPLOY_USER}" 2>/dev/null || echo MISSING)"
echo "nginx         : $(nginx -v 2>&1)"
echo "postgresql    : $(sudo -u postgres psql -tAc 'SELECT version()' | head -n1)"
echo "certbot       : $(certbot --version 2>&1)"
echo "age           : $(age --version 2>&1 || echo 'installed')"
echo "ufw           : $(ufw status | head -n1)"
echo "fail2ban      : $(systemctl is-active fail2ban)"
echo "unattended-up : $(systemctl is-active unattended-upgrades)"
echo "db role       : $(sudo -u postgres psql -tAc "SELECT rolname FROM pg_roles WHERE rolname='${DB_ROLE}'")"
echo "database      : $(sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datname='${DB_NAME}'")"
echo "extensions    : $(sudo -u postgres psql -d "${DB_NAME}" -tAc "SELECT string_agg(extname,',') FROM pg_extension WHERE extname IN ('pg_trgm','citext')")"
echo "tuning conf   : ${PG_TUNING_CONF} ($( [[ -f "${PG_TUNING_CONF}" ]] && echo present || echo MISSING ))"
echo "directories   : ${APP_HOME}/{releases,shared/uploads}, ${ETC_DIR} (mode $(stat -c '%a' "${ETC_DIR}" 2>/dev/null || echo '?'))"
echo
echo "Provision complete. Next: create nginx vhost, systemd unit, and ${ETC_DIR}/app.env."
