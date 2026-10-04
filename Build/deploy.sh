#!/usr/bin/env bash
#
# Deployment steps of this TYPO3 installation.
#
# The CI deployment runs "composer run-script typo3-deployment-scripts" after
# "composer install" on the target server, which calls this script. It is
# idempotent: the first run installs TYPO3 (configuration, database, backend
# user, start page), every later run only updates schema, extensions and caches.
#
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ADMIN_USER="admin"
ADMIN_EMAIL="kunde@example.com"
PROJECT_NAME="signundsinn GmbH"
PASSWORD_FILE="typo3temp/var/initial-admin-password.txt"

log() {
    echo "[deploy] $*"
}

# ---------------------------------------------------------------------------
# 1. PHP binary: the PHP of the deployment ("php" in its PATH) is used, it is
#    the version the environment is configured with and the one composer
#    installed the packages with. Only if that one is older than the PHP 8.2
#    TYPO3 13 LTS needs, a newer binary is looked for. TYPO3_PHP_BINARY
#    overrides the detection if a host needs a specific path.
# ---------------------------------------------------------------------------
find_php() {
    local candidate
    for candidate in "${TYPO3_PHP_BINARY:-}" php php8.2 php8.3 php8.4; do
        [ -n "$candidate" ] || continue
        command -v "$candidate" >/dev/null 2>&1 || continue
        if "$candidate" -r 'exit(PHP_VERSION_ID >= 80200 ? 0 : 1);' >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done
    return 1
}

if ! PHP_BIN="$(find_php)"; then
    log "ERROR: no PHP 8.2 or newer found on this server (needed by TYPO3 13 LTS)."
    exit 1
fi
log "using $PHP_BIN ($("$PHP_BIN" -r 'echo PHP_VERSION;'))"

typo3() {
    "$PHP_BIN" vendor/bin/typo3 "$@"
}

# ---------------------------------------------------------------------------
# 2. Directories the installation needs. The document root is the project
#    root, therefore TYPO3 keeps its configuration in typo3conf/ and its
#    runtime data in typo3temp/var/ (both blocked by .htaccess).
# ---------------------------------------------------------------------------
mkdir -p typo3conf/system typo3conf/sites typo3temp/var fileadmin

# The CI deployment writes database credentials from DEPLOY_DATABASE_URL into
# config/system/additional.php (composer layout). This installation reads
# typo3conf/system/additional.php, so the file is taken over here - but only
# when it contains usable credentials (see the script for the details).
"$PHP_BIN" Build/deployment/apply-database-config.php

# ---------------------------------------------------------------------------
# 3. Installation. Without database credentials from the CI the installation
#    uses SQLite, which needs no database server. If the project is later
#    moved to MySQL (CI variable DEPLOY_DATABASE_URL, see README), the
#    credentials in typo3conf/system/additional.php take precedence over the
#    values written here - the existing content has to be migrated.
#
#    "typo3 setup" writes the configuration, creates the database schema and
#    the first backend user. It also runs when the configuration exists but
#    the database is empty: a deployment that was interrupted during the first
#    installation is finished that way instead of failing for good.
# ---------------------------------------------------------------------------
install_typo3() {
    local initial_password
    initial_password="$("$PHP_BIN" Build/deployment/generate-password.php)"

    TYPO3_DB_DRIVER="${TYPO3_DB_DRIVER:-sqlite}" \
    TYPO3_DB_HOST="${TYPO3_DB_HOST:-localhost}" \
    TYPO3_DB_PORT="${TYPO3_DB_PORT:-3306}" \
    TYPO3_DB_DBNAME="${TYPO3_DB_DBNAME:-typo3}" \
    TYPO3_DB_USERNAME="${TYPO3_DB_USERNAME:-typo3}" \
    TYPO3_DB_PASSWORD="${TYPO3_DB_PASSWORD:-}" \
    TYPO3_SETUP_ADMIN_USERNAME="$ADMIN_USER" \
    TYPO3_SETUP_ADMIN_PASSWORD="$initial_password" \
    TYPO3_SETUP_ADMIN_EMAIL="$ADMIN_EMAIL" \
    TYPO3_PROJECT_NAME="$PROJECT_NAME" \
    TYPO3_SERVER_TYPE="apache" \
        typo3 setup --no-interaction --force

    ( umask 077 ; printf '%s\n' "$initial_password" > "$PASSWORD_FILE" )
    log "initial backend password written to $PASSWORD_FILE"
}

if [ ! -f typo3conf/system/settings.php ]; then
    log "no settings.php yet - installing TYPO3"
    install_typo3
else
    # A database that cannot be reached would otherwise only show up as a 500
    # error in the browser, so it is checked before anything is changed.
    log "checking the database"
    set +e
    "$PHP_BIN" Build/deployment/check-database.php
    DATABASE_STATE=$?
    set -e

    case "$DATABASE_STATE" in
        0) ;;
        10)
            log "the configuration exists, but the database is empty - completing the installation"
            install_typo3
            ;;
        *)
            log "ERROR: the database of typo3conf/system/settings.php cannot be reached (see above)."
            log "       Set DEPLOY_DATABASE_URL in the deployment or remove the wrong credentials."
            exit 1
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# 4. Project settings, database schema, extensions, initial content, caches.
# ---------------------------------------------------------------------------
"$PHP_BIN" Build/deployment/apply-settings.php

# "extension:setup" is the schema/extension update of TYPO3 13: it adds new
# tables and fields of all extensions and imports their static data.
log "setting up extensions and updating the database schema"
typo3 extension:setup --no-interaction

log "running upgrade wizards"
typo3 upgrade:run --no-interaction || log "upgrade:run reported a problem - continuing"

"$PHP_BIN" Build/deployment/bootstrap-content.php

log "updating language packs"
typo3 language:update --no-interaction || log "language:update failed - continuing"

log "flushing caches"
typo3 cache:flush
typo3 cache:warmup || log "cache:warmup failed - continuing"

log "done"
