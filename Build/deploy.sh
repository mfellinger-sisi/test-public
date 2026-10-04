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
PASSWORD_FILE="var/initial-admin-password.txt"

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
# 2. Directories the installation needs. This is the standard TYPO3 composer
#    layout: public/ is the document root (the only folder the web server
#    serves), configuration lives in config/ and runtime data in var/ - both,
#    like vendor/ and Build/, outside of the web root.
#
#    An installation from the earlier layout (project root as document root,
#    configuration in typo3conf/) is migrated first, so its settings, database
#    and uploaded files survive the switch.
# ---------------------------------------------------------------------------
migrate_legacy_layout() {
    [ -f typo3conf/system/settings.php ] || return 0

    log "migrating the earlier layout (typo3conf/) to config/, var/ and public/"
    mkdir -p config/system var public
    "$PHP_BIN" Build/deployment/migrate-legacy-layout.php

    if [ -d fileadmin ] && [ ! -e public/fileadmin ]; then
        mv fileadmin public/fileadmin
    fi
    if [ -f typo3temp/var/initial-admin-password.txt ] && [ ! -e "$PASSWORD_FILE" ]; then
        mv typo3temp/var/initial-admin-password.txt "$PASSWORD_FILE"
    fi

    # What is left is generated again below public/ (index.php, typo3/,
    # _assets/, typo3temp/) or has been taken over above.
    rm -rf typo3conf typo3temp index.php typo3 _assets uploads
}

migrate_legacy_layout

mkdir -p config/system config/sites var public/fileadmin

# The CI deployment writes the credentials of DEPLOY_DATABASE_URL into
# config/system/additional.php, which TYPO3 reads directly. An unusable file
# (no credentials) is removed again, see the script for the details.
"$PHP_BIN" Build/deployment/apply-database-config.php

# ---------------------------------------------------------------------------
# 3. Installation. Without database credentials from the CI the installation
#    uses SQLite, which needs no database server. With credentials from the
#    CI (CI variable DEPLOY_DATABASE_URL, see README) they are read from
#    config/system/additional.php and handed to the setup, so schema,
#    settings.php and the following steps all use the same MySQL database.
#
#    "typo3 setup" writes the configuration, creates the database schema and
#    the first backend user. It also runs when the configuration exists but
#    the database is empty: a deployment that was interrupted during the first
#    installation is finished that way instead of failing for good.
# ---------------------------------------------------------------------------
install_typo3() {
    local initial_password
    initial_password="$("$PHP_BIN" Build/deployment/generate-password.php)"

    # The credentials of config/system/additional.php (CI deployment) go to
    # the setup, so schema and settings.php land in the same database that the
    # following steps use. Without them the setup would fall back to SQLite
    # while everything after it works on MySQL. Done in a subshell: the
    # password stays out of this script's environment and out of the log.
    (
        database_env="$("$PHP_BIN" Build/deployment/read-database-env.php)"
        eval "$database_env"
        if [ -n "${TYPO3_DB_DRIVER:-}" ]; then
            log "handing the credentials of the CI deployment (${TYPO3_DB_DRIVER}) to the setup"
        fi
        install_typo3_setup "$initial_password"
    )

    ( umask 077 ; printf '%s\n' "$initial_password" > "$PASSWORD_FILE" )
    log "initial backend password written to $PASSWORD_FILE"
}

install_typo3_setup() {
    local initial_password="$1"

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
}

if [ ! -f config/system/settings.php ]; then
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
            log "ERROR: the database of config/system/settings.php cannot be reached (see above)."
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
