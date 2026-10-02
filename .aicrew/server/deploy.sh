#!/usr/bin/env bash
# GENERATED copy of the shared deploy scripts -- do not edit here; change common/server and re-run sync-common.mjs
# Shared deploy framework. A per-type deploy-<type>.sh script (or a client
# project's own custom wrapper) sets up the extension points below and then
# `source`s this file -- it must NOT `exec` it, since this framework needs to
# see the functions/variables the wrapper defines before it runs.
#
# Extension contract a wrapper provides before sourcing:
#   PROJECT_TYPE        (optional, cosmetic) a label used in log output and
#                        as DEPLOYMENT_LABEL's default
#   DEPLOYMENT_LABEL     (optional) text for "Perform <label> Deployment";
#                        defaults to $PROJECT_TYPE
#   REMOTE_SHELL         (optional) shell used to execute the generated
#                        remote script over ssh; defaults to "/bin/bash"
#   project_validate()   (optional) called after the shared required-variable
#                        checks but before the DNS check -- put type-specific
#                        fail-fast validation here (e.g. an extra required var)
#   project_tail()       (required) emits this type's remote deploy commands;
#                        called last, with $TARGETPATH/$PHP_DIR/$PHP_CMD/
#                        $COMPOSER_DIR/$COMPOSER_CMD/$COMPOSER_PROD/$USER/
#                        $ENVIRONMENT and the emit_*/git_sync_block helpers
#                        below all already available
# All configuration comes from DEPLOY_* variables -- there are no per-environment
# name prefixes (no DEV_/LIVE_/...). Give each environment its own value by
# scoping the variable to the CI environment (the variable's environment scope =
# the environment's name; GitLab: Settings > CI/CD > Variables).
# DEPLOY_ROLE (staging|live|other) is set by the .deploy_<role>_base job the
# deploy job extends; it decides the Live-only behavior below, the environment
# name itself is free.
# Required: DEPLOY_PATH, DEPLOY_PHP_CMD, DEPLOY_PHP_DIR, DEPLOY_USER (plus the
# environment URL, from DEPLOY_URL, and DEPLOY_PRIVATE_KEY for ssh).
# Optional: DEPLOY_COMPOSER_CMD / DEPLOY_COMPOSER_BASE (which composer to use,
# see below), DEPLOY_APP_ENV, DEPLOY_DATABASE_URL, DEPLOY_ENV_FILE, DEPLOY_ENV_<KEY>,
# DEPLOY_CONFIG_FILE, DEPLOY_TYPO3_VERSION, DEPLOY_TYPO3_MODE,
# DEPLOY_AUTO_INSTALL, DEPLOY_NODE_VERSION, DEPLOY_AUTO_DEPLOY.
# Deliberately not named bare PATH/USER/etc: those would collide with the
# shell's own $PATH/$USER.
#
# CI host facts are read under neutral names only (DEPLOY_ENVIRONMENT,
# DEPLOY_REPO_URL, DEPLOY_PROJECT_ID, DEPLOY_BRANCH, plus DEPLOY_PROVIDER for the
# log line), filled by provider.sh
# next to this file -- the one place that knows the CI host's own variables.
# Host-specific authentication on the server comes from the same file:
# emit_repo_auth git|composer (see git_sync_block).
# The tools the deploy itself needs on the runner: dig and ssh. An Alpine image (GitLab) takes them from apk, a
# Debian or Ubuntu runner (GitHub) from apt; where both are there already nothing is installed.
if ! command -v dig > /dev/null || ! command -v ssh > /dev/null; then
  if command -v apk > /dev/null; then
    apk add bind-tools openssh-client
  elif command -v apt-get > /dev/null; then
    APT_SUDO=""; [[ "$(id -u)" != "0" ]] && APT_SUDO="sudo"
    $APT_SUDO apt-get update -qq > /dev/null && $APT_SUDO apt-get install -y -qq dnsutils openssh-client > /dev/null
  fi
fi

# shellcheck source=provider.sh
source "$(dirname "$0")/provider.sh" || { echo "provider.sh not found next to deploy.sh" ; exit 4 ; }
declare -f emit_repo_auth > /dev/null || { echo "provider.sh does not define emit_repo_auth" ; exit 4 ; }

echo "deploy/${DEPLOY_PROVIDER:-ci} $(cat "$(dirname "$0")/../VERSION" 2>/dev/null)"

echo "DEPLOY_ENVIRONMENT=$DEPLOY_ENVIRONMENT"
if [[ -z "$DEPLOY_ENVIRONMENT" ]] ; then echo "DEPLOY_ENVIRONMENT (the CI environment name) is not defined" ; exit 1 ; fi

ENVIRONMENT=$(echo "$DEPLOY_ENVIRONMENT" | tr '[:lower:]' '[:upper:]')
[[ "$ENVIRONMENT" == "DEVELOPMENT" ]] && ENVIRONMENT=DEV

echo "ENVIRONMENT=$ENVIRONMENT"
if [[ -z "$ENVIRONMENT" ]]; then echo "ENVIRONMENT is not defined" ; exit 2; fi
# (only used as the Shopware 5 environment name, see deploy-shopware5.sh)

echo "DEPLOY_ROLE=$DEPLOY_ROLE"
case "$DEPLOY_ROLE" in
  staging|live|other) ;;
  *) echo "DEPLOY_ROLE must be staging, live or other -- extend .deploy_staging_base, .deploy_live_base or .deploy_other_base" ; exit 3 ;;
esac

REMOTE_SHELL="${REMOTE_SHELL:-/bin/bash}"
DEPLOYMENT_LABEL="${DEPLOYMENT_LABEL:-$PROJECT_TYPE}"

if ! declare -f project_tail > /dev/null; then
  echo "project_tail is not defined -- the wrapper script must define it before sourcing deploy.sh" ; exit 16
fi

# Which composer runs on the target. The lookup itself happens on the server
# (see emit_composer_file_check); here only the candidate is decided:
#   1. DEPLOY_COMPOSER_CMD   a path or a command name: composer,
#                            /usr/local/bin/composer2, /opt/composer-2.7.9.phar.
#                            A CI variable value may reference
#                            $COMPOSER_VERSION to pick a version-named command
#                            (e.g. /usr/local/bin/composer-$COMPOSER_VERSION).
#   2. DEPLOY_COMPOSER_BASE  a directory with one subdirectory per version:
#                            <base>/$COMPOSER_VERSION/composer
#   3. neither               "composer" from the server's PATH (single install)
# The result must be a PHP script or phar: it is run as `php <file>`.
COMPOSER_DIR=""
if [[ -n "$DEPLOY_COMPOSER_CMD" ]]; then
  COMPOSER_CANDIDATE="$DEPLOY_COMPOSER_CMD"
elif [[ -n "$DEPLOY_COMPOSER_BASE" ]]; then
  if [[ -z "$COMPOSER_VERSION" ]]; then echo "COMPOSER_VERSION is not defined (needed with DEPLOY_COMPOSER_BASE)" ; exit 9 ; fi
  COMPOSER_CANDIDATE="${DEPLOY_COMPOSER_BASE%/}/${COMPOSER_VERSION}/composer"
else
  COMPOSER_CANDIDATE="composer"
fi
[[ "$COMPOSER_CANDIDATE" == */* ]] && COMPOSER_DIR="${COMPOSER_CANDIDATE%/*}"
echo "COMPOSER_CANDIDATE=$COMPOSER_CANDIDATE"

PHP_CMD="$DEPLOY_PHP_CMD"
echo "PHP_CMD=$PHP_CMD"

PHP_DIR="$DEPLOY_PHP_DIR"
echo "PHP_DIR=$PHP_DIR"

TARGETPATH="$DEPLOY_PATH"
echo "TARGETPATH=$TARGETPATH"

USER="$DEPLOY_USER"
echo "USER=$USER"

if [[ -z "$PHP_CMD" ]]; then echo "DEPLOY_PHP_CMD is not defined" ; exit 11 ; fi
if [[ -z "$PHP_DIR" ]]; then echo "DEPLOY_PHP_DIR is not defined" ; exit 12 ; fi
if [[ -z "$TARGETPATH" ]]; then echo "DEPLOY_PATH is not defined" ; exit 13 ; fi
if [[ -z "$USER" ]]; then echo "DEPLOY_USER is not defined" ; exit 14 ; fi
if [[ -z "$DEPLOY_URL" ]]; then echo "DEPLOY_URL is not defined" ; exit 15 ; fi

# DEPLOY_URL may be a bare host (live.example.com) or a full URL
# (https://live.example.com:8443/shop/). ssh/dig/ping get the bare host; the
# web path only ends up in APP_URL (it says nothing about the server directory,
# that is DEPLOY_PATH).
DEPLOY_SCHEME="https"
DEPLOY_REST="$DEPLOY_URL"
if [[ "$DEPLOY_REST" =~ ^([A-Za-z][A-Za-z0-9+.-]*)://(.*)$ ]]; then
  DEPLOY_SCHEME="${BASH_REMATCH[1]}"
  DEPLOY_REST="${BASH_REMATCH[2]}"
fi
DEPLOY_HOSTPORT="${DEPLOY_REST%%/*}"
DEPLOY_HOSTPORT="${DEPLOY_HOSTPORT##*@}"
DEPLOY_WEBPATH="${DEPLOY_REST#"${DEPLOY_REST%%/*}"}"
DEPLOY_HOST="${DEPLOY_HOSTPORT%%:*}"
DEPLOY_APP_URL="${DEPLOY_SCHEME}://${DEPLOY_HOSTPORT}${DEPLOY_WEBPATH%/}"
echo "DEPLOY_HOST=$DEPLOY_HOST"
echo "DEPLOY_APP_URL=$DEPLOY_APP_URL"
if [[ -z "$DEPLOY_HOST" ]]; then echo "cannot read a host from DEPLOY_URL=$DEPLOY_URL" ; exit 15 ; fi

if declare -f project_validate > /dev/null; then
  project_validate
fi

DOMAIN_EXIST=$(dig +noall +answer -t A $DEPLOY_HOST)
echo "DOMAIN_EXIST=$DOMAIN_EXIST"

if [[ -z "$DOMAIN_EXIST" ]]; then echo "Target-Domain: $DEPLOY_HOST not found" ; exit 17 ; fi

IP=$(ping -c 1 $DEPLOY_HOST | grep "from" | sed -e "s#.* from \(.*\): .*#\1#")
# A runner that blocks ICMP still resolved the name: take the address from the DNS answer then.
[[ -z "$IP" ]] && IP=$(echo "$DOMAIN_EXIST" | awk '$4 == "A" { print $5; exit }')
echo "IP=$IP"

if [[ -z "$IP" ]]; then echo "Error in DNS resolution" ; exit 18 ; fi

echo "Deploying $DEPLOY_BRANCH to $DEPLOY_HOST \($IP\) on $TARGETPATH as $USER"

echo "Perform $DEPLOYMENT_LABEL Deployment"

# The generated remote script resolves the composer file into $COMPOSER_BIN
# (emit_composer_file_check); COMPOSER_CMD is that variable, kept unexpanded so
# every project_tail that echoes it references the remote one.
COMPOSER_CMD='$COMPOSER_BIN'

# Composer prod/dev mode: defaults to prod (--no-dev) only on the live role, dev
# (dev dependencies kept) everywhere else -- DEPLOY_APP_ENV=prod|dev (scoped to
# the environment) overrides that. Unset means "use the default".
APP_ENV_OVERRIDE="$DEPLOY_APP_ENV"
echo "APP_ENV_OVERRIDE=$APP_ENV_OVERRIDE"
if [[ -n "$APP_ENV_OVERRIDE" ]]; then
  [[ "$APP_ENV_OVERRIDE" == "prod" ]] && COMPOSER_PROD=1 || COMPOSER_PROD=0
else
  [[ "$DEPLOY_ROLE" == "live" ]] && COMPOSER_PROD=1 || COMPOSER_PROD=0
fi
echo "COMPOSER_PROD=$COMPOSER_PROD"

# Canonical remote-script exit codes: every distinct failure has exactly one
# code, used the same way for every project type that can hit it, so the
# same error always returns the same exit status regardless of PROJECT_TYPE.
#  19 composer not found                28 git checkout failed
#  20 php binary not executable         29 git branch --set-upstream failed
#  21 targetpath not a directory        30 git pull failed
#  22 DEPLOY_REPO_URL not set           31 git submodule sync failed
#  23 git clone failed                  32 git submodule init failed
#  24 DEPLOY_BRANCH invalid            33 git submodule update failed
#  25 git stash clear failed            34 composer repo auth config failed
#  26 git stash failed                  35 required binary not executable
#  27 git fetch failed                     (bin/console, build-storefront.sh,
#                                            build.sh, build-js.sh)
#  36 composer install failed           41 artisan view:clear failed
#  37 typo3 composer run-script failed  42 artisan view:cache failed
#  38 artisan cache:clear failed        43 plugin refresh failed
#  39 artisan route:clear failed        44 cache clear failed
#  40 artisan route:cache failed        45 theme cache/compile failed
#                                       46 build-storefront.sh run failed
#                                       47 build.sh run failed
#                                       48 build-js.sh run failed
#                                       49 nvm bootstrap/source failed
#                                       50 nvm install <version> failed
#                                       51 nvm use <version> failed
#                                       52 no .env and no DATABASE_URL configured
#                                          (Symfony: only when the project uses doctrine)
#                                       53 writing .env failed
#                                       54 jwt secret generation failed
#                                       55 system:install failed
#                                       56 extra .env value contains a single quote
#                                       57 copying the .env files to the server failed
#                                       58 git config failed
#                                       59 TYPO3 version can't be determined
#                                       60 DATABASE_URL not usable for TYPO3 < 6 (use the config file)
#                                       61 target path not empty and not a git checkout
#                                       62 checkout belongs to a different project

# DEPLOY_REPO_URL without userinfo (the job token): what origin is set to.
DEPLOY_REPO_URL_PUBLIC="$DEPLOY_REPO_URL"
if [[ "$DEPLOY_REPO_URL" =~ ^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]*@(.*)$ ]]; then
  DEPLOY_REPO_URL_PUBLIC="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
fi

# DEPLOY_ACCEPT_REMOTE (optional, scoped to the environment, remove it after
# the deploy): the normalized URL of a checkout's current origin that may be
# taken over once although it belongs to a different project URL and has no
# matching stored project id. Only URL characters are allowed, since the value
# ends up in the remote script.
if [[ -n "$DEPLOY_ACCEPT_REMOTE" && ! "$DEPLOY_ACCEPT_REMOTE" =~ ^[A-Za-z0-9@:/._~+-]+$ ]]; then
  echo "DEPLOY_ACCEPT_REMOTE contains characters that are not allowed in a URL" ; exit 5
fi

# Shared git clone/sync/submodule block, identical across all types.
git_sync_block() {
  echo "if [[ ! -d $TARGETPATH ]]; then echo \"$TARGETPATH is not a directory\" ; exit 21 ; fi"
  echo "cd $TARGETPATH"
  # Deploy guard: only an empty directory (clone) or an existing checkout may be
  # deployed into -- never a directory with unrelated content.
  echo "if [[ ! -d .git && -n \"\$(ls -A)\" ]]; then echo \"$TARGETPATH is not empty and not a git checkout -- refusing to deploy into it\" ; exit 61 ; fi"
  echo "if [[ -z $DEPLOY_REPO_URL ]]; then echo \"REPOSITORY URL is not set\" ; exit 22 ; fi"
  emit_origin_guard
  echo "if [[ ! -d .git ]]; then git clone $DEPLOY_REPO_URL . || exit 23 ; fi"
  # origin never keeps a token (the job token expires anyway): git and
  # submodules authenticate through emit_repo_auth git, which follows.
  echo "git remote set-url origin $DEPLOY_REPO_URL_PUBLIC"
  emit_project_id_store
  emit_repo_auth git
  echo "if [[ -z $DEPLOY_BRANCH ]]; then echo \"$DEPLOY_BRANCH is not valid\" ; exit 24 ; fi"
  echo "git stash clear || exit 25"
  echo "git stash || exit 26"
  echo "git fetch || exit 27"
  echo "git checkout $DEPLOY_BRANCH || exit 28"
  echo "git branch --set-upstream-to=origin/$DEPLOY_BRANCH $DEPLOY_BRANCH || exit 29"
  echo "git pull || exit 30"
  echo "git stash pop | 2>/dev/null"
  echo "git submodule sync || exit 31"
  echo "git submodule init || exit 32"
  echo "git submodule update || exit 33"
  emit_repo_auth composer
}

# Deploy guard, part 2: an existing checkout must belong to this project.
# Both URLs are normalized to lowercase host/path (no scheme, userinfo, port,
# trailing .git or slash; scp-style user@host:path mapped), so https/ssh and
# token/no-token forms of the same project compare equal. A different URL is
# still accepted when the checkout's stored deploy.projectId equals
# <host>:$DEPLOY_PROJECT_ID of the running job: the same project, moved or
# renamed on the host (the id survives that, the URL does not); origin is then
# updated by the set-url that follows. A checkout whose normalized origin
# equals the normalized DEPLOY_ACCEPT_REMOTE is taken over the same way (the
# operator's one-shot confirmation). Anything else stops with exit 62.
# Only normalized URLs are printed: DEPLOY_REPO_URL carries the job token.
emit_origin_guard() {
  cat <<'NORM'
deploy_norm_url() {
  local u="$1" hp path
  u="${u%/}"; u="${u%.git}"; u="${u%/}"
  if [[ "$u" =~ ^[A-Za-z][A-Za-z0-9+.-]*://(.*)$ ]]; then
    u="${BASH_REMATCH[1]}"
    hp="${u%%/*}"; path=""; [[ "$u" == */* ]] && path="${u#*/}"
    hp="${hp##*@}"; hp="${hp%%:*}"
    u="$hp/$path"
  elif [[ "$u" =~ ^([^@/]+@)?([^:/]+):(.*)$ ]]; then
    u="${BASH_REMATCH[2]}/${BASH_REMATCH[3]#/}"
  fi
  printf '%s\n' "$u" | tr '[:upper:]' '[:lower:]'
}
NORM
  cat <<GUARD
if [[ -d .git ]]; then
  DEPLOY_ORIGIN_NORM=\$(deploy_norm_url "\$(git remote get-url origin 2>/dev/null)")
  DEPLOY_REPO_NORM=\$(deploy_norm_url "$DEPLOY_REPO_URL")
  if [[ "\$DEPLOY_ORIGIN_NORM" != "\$DEPLOY_REPO_NORM" ]]; then
    DEPLOY_ID_STORED=\$(git config --get deploy.projectId)
    DEPLOY_ID_CURRENT="\${DEPLOY_REPO_NORM%%/*}:$DEPLOY_PROJECT_ID"
    DEPLOY_ACCEPT_NORM=\$(deploy_norm_url "$DEPLOY_ACCEPT_REMOTE")
    if [[ -n "$DEPLOY_PROJECT_ID" && "\$DEPLOY_ID_STORED" == "\$DEPLOY_ID_CURRENT" ]]; then
      echo "checkout origin \$DEPLOY_ORIGIN_NORM is project \$DEPLOY_ID_CURRENT, now \$DEPLOY_REPO_NORM (moved or renamed) -- updating origin"
    elif [[ -n "$DEPLOY_ACCEPT_REMOTE" && "\$DEPLOY_ORIGIN_NORM" == "\$DEPLOY_ACCEPT_NORM" ]]; then
      echo "checkout origin \$DEPLOY_ORIGIN_NORM accepted by DEPLOY_ACCEPT_REMOTE -- taking it over for \$DEPLOY_REPO_NORM; remove DEPLOY_ACCEPT_REMOTE now"
    else
      echo "checkout origin \$DEPLOY_ORIGIN_NORM is not this project (\$DEPLOY_REPO_NORM) -- refusing to deploy into it"
      exit 62
    fi
  fi
fi
GUARD
}

# Deploy guard, part 3: record which project this checkout belongs to, as
# <host>:<project id> in the checkout's git config (deploy.projectId). Written
# on every deploy that passed the guard, so a checkout taken over by URL,
# move or DEPLOY_ACCEPT_REMOTE carries the current id from then on; the next
# deploy after a move on the host recognizes it by this id (see
# emit_origin_guard). Skipped when the host provides no project id.
emit_project_id_store() {
  [[ -n "$DEPLOY_PROJECT_ID" ]] || return 0
  echo "DEPLOY_REPO_NORM=\$(deploy_norm_url \"$DEPLOY_REPO_URL\")"
  echo "git config deploy.projectId \"\${DEPLOY_REPO_NORM%%/*}:$DEPLOY_PROJECT_ID\" || exit 58"
}

# Further common building blocks available to every project_tail.
emit_mkdir() {
  echo "mkdir -p $TARGETPATH"
}

emit_path_export() {
  echo "export PATH=${COMPOSER_DIR:+$COMPOSER_DIR:}$PHP_DIR:\$PATH"
}

emit_composer_auth() {
  echo "export COMPOSER_AUTH='$COMPOSER_AUTH'"
}

# Resolves the composer candidate on the server into $COMPOSER_BIN: a bare
# command name is looked up in the server's PATH (which emit_path_export has
# already extended), a path is taken as is (a leading ~/ becomes $HOME).
emit_composer_file_check() {
  local c="$COMPOSER_CANDIDATE"
  [[ "$c" == "~/"* ]] && c="\$HOME/${c#\~/}"
  echo "COMPOSER_BIN=\"$c\""
  echo "if [[ \"\$COMPOSER_BIN\" != */* ]]; then COMPOSER_BIN=\$(command -v \"\$COMPOSER_BIN\") ; fi"
  echo "if [[ ! -f \"\$COMPOSER_BIN\" ]]; then echo \"composer not found (tried: $COMPOSER_CANDIDATE) -- set DEPLOY_COMPOSER_CMD or DEPLOY_COMPOSER_BASE, or install composer on the server\" ; exit 19 ; fi"
  echo "echo \"COMPOSER_BIN=\$COMPOSER_BIN\""
}

emit_php_exec_check() {
  echo "if [[ ! -x $PHP_DIR/$PHP_CMD ]]; then echo \"$PHP_DIR/$PHP_CMD is not executable\" ; exit 20 ; fi"
}

# $1: path to a required binary/script that must be executable
emit_executable_check() {
  echo "if [[ ! -x $1 ]]; then echo \"$1 is not executable\" ; exit 35 ; fi"
}

# $1: extra composer install flags beyond the environment-driven ones (e.g.
# "--optimize-autoloader"). Every project type gets the same dev/prod
# distinction, decided by $COMPOSER_PROD (see its computation above):
# --no-dev only in prod mode, --prefer-dist always.
emit_composer_install() {
  local extra="$1"
  local -a flags=()
  [[ -n "$extra" ]] && flags+=("$extra")
  [[ "$COMPOSER_PROD" == "1" ]] && flags+=("--no-dev")
  flags+=("--prefer-dist")
  echo "$PHP_DIR/$PHP_CMD $COMPOSER_CMD install ${flags[*]} || exit 36"
}

# $1: bin/console command prefix ("" or "sw:"), $2: command, $3: exit code
emit_console_command() {
  echo "$PHP_DIR/$PHP_CMD bin/console $1$2 || exit $3"
}

# Dotenv bootstrap, shared by the project types whose config lives in env
# files. Must run AFTER git_sync_block (the clone needs an empty dir). Values
# are written to a file git doesn't track, so the deploy never conflicts with
# `git pull`. Wrappers below pick the right options per type:
#   emit_shopware_env / emit_symfony_env   .env.local (Symfony loads it after,
#                                          i.e. overriding, a committed .env)
#   emit_laravel_env                       .env (Laravel has no .env.local;
#                                          created from .env.example if missing)
# Sources, lowest to highest precedence:
#   1. the repo's .env, and a hand-made server .env
#   2. defaults, only filled in when the key is in neither .env nor .env.local:
#      APP_URL (from DEPLOY_URL, scheme and web path included), the secret (generated on the server
#      once, never logged), Shopware's INSTANCE_ID. APP_ENV is the exception:
#      it follows $COMPOSER_PROD unless the target file sets it, because a repo
#      .env saying dev breaks a --no-dev install.
#   3. DEPLOY_DATABASE_URL (replaces DATABASE_URL;
#      with --require-db the deploy stops, exit 52, if none exists anywhere)
#   4. DEPLOY_ENV_FILE: a *file*-type CI variable with
#      KEY=value lines; each key it contains replaces that key in the target
#   5. DEPLOY_ENV_<KEY>: single keys, same replace
#      semantics, win over the file
# Keys in the target that CI doesn't mention are left alone. The values travel
# as a file next to ci-deploy.sh (see the scp at the end), so they never
# show up in the job log -- no masking needed. NOTE: the file is only created
# here on the runner; the live role with DEPLOY_AUTO_DEPLOY other than 1 only dumps the script.
#
# Options: --file <name>            target (default .env.local)
#          --app-env <prod> <dev>   APP_ENV values (default prod dev)
#          --secret <KEY> <hex|base64>   generated secret (default APP_SECRET hex)
#          --instance-id            also generate INSTANCE_ID (Shopware)
#          --require-db             DATABASE_URL must exist (exit 52)
#          --require-db-doctrine    same, but only when the project uses doctrine (composer.lock,
#                                   else composer.json: dbal, orm, doctrine-bundle, mongodb-odm)
#                                   (otherwise the check is skipped and logged)
#          --from-example           create the target from .env.example
#          --export-env             source .env/.env.local for later build steps
emit_env_bootstrap() {
  local target=".env.local" prod_val="prod" dev_val="dev" secret_key="APP_SECRET" secret_kind="hex"
  local instance=0 need_db=0 need_db_doctrine=0 example=0 export_env=0
  while (( $# )); do
    case "$1" in
      --file) target="$2"; shift ;;
      --app-env) prod_val="$2"; dev_val="$3"; shift 2 ;;
      --secret) secret_key="$2"; secret_kind="$3"; shift 2 ;;
      --instance-id) instance=1 ;;
      --require-db) need_db=1 ;;
      --require-db-doctrine) need_db_doctrine=1 ;;
      --from-example) example=1 ;;
      --export-env) export_env=1 ;;
      *) echo "emit_env_bootstrap: unknown option $1" >&2 ; exit 16 ;;
    esac
    shift
  done

  local db_var="DEPLOY_DATABASE_URL"
  local db_url="$DEPLOY_DATABASE_URL"
  local env_file="$DEPLOY_ENV_FILE"
  local app_env="$dev_val"
  [[ "$COMPOSER_PROD" == "1" ]] && app_env="$prod_val"

  # runner side: ci-deploy.env = DB url + env file + per-key variables,
  # in that order (later lines replace earlier ones on the server)
  : > ci-deploy.env
  if [[ -n "$db_url" ]]; then
    if [[ "$db_url" == *"'"* ]]; then echo "$db_var contains a single quote, which can't be written to $target" >&2 ; exit 56 ; fi
    printf "DATABASE_URL='%s'\n" "$db_url" >> ci-deploy.env
  fi
  if [[ -n "$env_file" && -f "$env_file" ]]; then
    cat "$env_file" >> ci-deploy.env
    printf '\n' >> ci-deploy.env
  fi
  local -A extra=()
  local v k
  for v in $(compgen -v DEPLOY_ENV_); do extra[${v#DEPLOY_ENV_}]="${!v}"; done
  for k in "${!extra[@]}"; do
    # DEPLOY_ENV_FILE is the file variable, not a key
    [[ "$k" == "FILE" ]] && continue
    [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    if [[ "${extra[$k]}" == *"'"* ]]; then echo "${k} contains a single quote, which can't be written to $target" >&2 ; exit 56 ; fi
    printf "%s='%s'\n" "$k" "${extra[$k]}" >> ci-deploy.env
  done

  # remote side
  echo "ENVFILE='$target'"
  cat <<'REMOTE'
merge_env() { # $1 file whose KEY=value lines replace those keys in $ENVFILE
  [[ -s "$1" ]] || { rm -f "$1" ; return 0 ; }
  local line key
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
    key="${line%%=*}"
    { grep -v "^$key=" "$ENVFILE" 2>/dev/null || true ; } > "$ENVFILE.tmp" && mv "$ENVFILE.tmp" "$ENVFILE" || exit 53
    printf '%s\n' "$line" >> "$ENVFILE"
  done < "$1"
  chmod 600 "$ENVFILE"
  rm -f "$1"
}
fill_env() { grep -qs "^$1=" .env .env.local "$ENVFILE" || printf "%s='%s'\n" "$1" "$2" >> "$ENVFILE" || exit 53 ; }
REMOTE
  if (( example )); then
    echo "if [[ ! -f \"\$ENVFILE\" && -f .env.example ]]; then grep -v '^APP_ENV=\\|^APP_KEY=' .env.example > \"\$ENVFILE\" ; fi"
  fi
  echo "grep -qs '^APP_ENV=' \"\$ENVFILE\" || printf 'APP_ENV=$app_env\\n' >> \"\$ENVFILE\" || exit 53"
  echo "fill_env APP_URL '$DEPLOY_APP_URL'"
  if [[ "$secret_kind" == "base64" ]]; then
    echo "fill_env $secret_key \"base64:\$(openssl rand -base64 32)\""
  else
    echo "fill_env $secret_key \"\$(openssl rand -hex 32)\""
  fi
  (( instance )) && echo "fill_env INSTANCE_ID \"\$(openssl rand -hex 16)\""
  echo "[[ -f \"\$ENVFILE\" ]] && chmod 600 \"\$ENVFILE\""
  echo "merge_env \"\$HOME/ci-deploy.env\""
  if (( need_db )); then
    echo "grep -qs '^DATABASE_URL=' .env .env.local || { echo \"no DATABASE_URL in .env/.env.local and DEPLOY_DATABASE_URL is not defined\" ; exit 52 ; }"
  fi
  if (( need_db_doctrine )); then
    # composer.lock (installed packages, dev ones excluded) tells about indirect
    # use too (symfony/orm-pack); composer.json is the fallback without a lock.
    cat <<'REMOTE'
uses_doctrine() {
  local pkg='"name": "doctrine/(dbal|orm|doctrine-bundle|mongodb-odm|mongodb-odm-bundle)"'
  if [[ -f composer.lock ]]; then
    sed '/"packages-dev"/,$d' composer.lock | grep -qE "$pkg"
  else
    grep -qE '"doctrine/(dbal|orm|doctrine-bundle|mongodb-odm|mongodb-odm-bundle)"' composer.json 2>/dev/null
  fi
}
if uses_doctrine ; then
  grep -qs '^DATABASE_URL=' .env .env.local || { echo "no DATABASE_URL in .env/.env.local and DEPLOY_DATABASE_URL is not defined (the project requires doctrine)" ; exit 52 ; }
else
  echo "no doctrine/dbal or doctrine/orm in composer.lock/composer.json: DATABASE_URL not required"
fi
REMOTE
  fi
  if (( export_env )); then
    echo "set -o allexport ; [[ -f .env ]] && source .env ; [[ -f .env.local ]] && source .env.local ; set +o allexport"
  fi
}

emit_shopware_env() { emit_env_bootstrap --file .env.local --instance-id --require-db --export-env ; }
emit_symfony_env() { emit_env_bootstrap --file .env.local --require-db-doctrine ; }
emit_laravel_env() { emit_env_bootstrap --file .env --app-env production local --secret APP_KEY base64 --from-example ; }

# Shopware 5 only: config.php lives in the repo (or is missing) and Shopware
# merges config_${SHOPWARE_ENV}.php on top of it, so that is the file we manage
# (keep it out of git). Sources:
#   DEPLOY_CONFIG_FILE: a *file*-type CI variable
#      with a complete PHP config (<?php return [...];), copied verbatim
#   otherwise DEPLOY_DATABASE_URL: mysql://user:pass@host:port/db
#      is turned into the 'db' block on the server
# When either is set, config_<env>.php is fully managed and rewritten on every
# deploy. When neither is set nothing is touched. Stops with exit 52 if the
# shop ends up with neither config.php nor config_<env>.php. Like the dotenv
# bootstrap the values travel as files, never through the job log.
emit_shopware5_config() {
  local db_var="DEPLOY_DATABASE_URL"
  local db_url="$DEPLOY_DATABASE_URL"
  local cfg_file="$DEPLOY_CONFIG_FILE"

  rm -f ci-deploy.config.php
  : > ci-deploy.env
  if [[ -n "$cfg_file" && -f "$cfg_file" ]]; then
    cp "$cfg_file" ci-deploy.config.php
  elif [[ -n "$db_url" ]]; then
    if [[ "$db_url" == *"'"* ]]; then echo "$db_var contains a single quote" >&2 ; exit 56 ; fi
    printf "DATABASE_URL='%s'\n" "$db_url" > ci-deploy.env
  fi

  echo 'CFG="config_${SHOPWARE_ENV}.php"'
  echo 'if [[ -s "$HOME/ci-deploy.config.php" ]]; then mv "$HOME/ci-deploy.config.php" "$CFG" && chmod 600 "$CFG" || exit 53'
  echo 'elif [[ -s "$HOME/ci-deploy.env" ]]; then'
  echo "  DB_URL=\$(sed -n \"s/^DATABASE_URL='\\(.*\\)'\$/\\1/p\" \"\$HOME/ci-deploy.env\") $PHP_DIR/$PHP_CMD -r '\$u = parse_url(getenv(\"DB_URL\")); \$db = [\"host\" => \$u[\"host\"] ?? \"localhost\", \"port\" => (string) (\$u[\"port\"] ?? 3306), \"username\" => urldecode(\$u[\"user\"] ?? \"\"), \"password\" => urldecode(\$u[\"pass\"] ?? \"\"), \"dbname\" => ltrim(\$u[\"path\"] ?? \"\", \"/\")]; echo \"<?php\\nreturn \" . var_export([\"db\" => \$db], true) . \";\\n\";' > \"\$CFG\" && chmod 600 \"\$CFG\" || exit 53"
  echo 'fi'
  echo 'rm -f "$HOME/ci-deploy.config.php" "$HOME/ci-deploy.env"'
  echo '[[ -f config.php || -f "$CFG" ]] || { echo "no config.php in the repository and no $CFG (set DEPLOY_CONFIG_FILE or DEPLOY_DATABASE_URL)" ; exit 52 ; }'
}

# TYPO3 only: writes the environment specific configuration on top of what the
# repository/install tool manages. The path depends on the TYPO3 major version:
#   12+   config/system/additional.php          (composer based installation)
#         typo3conf/system/additional.php        (classic installation)
#   6-11  typo3conf/AdditionalConfiguration.php
#   <6    typo3conf/localconf.php               (the whole file, no override
#                                                file exists there)
# The version comes from DEPLOY_TYPO3_VERSION
# (major number) or, if unset, from typo3/cms-core in composer.lock (so <6
# projects, which have no composer.lock, must set the variable; exit 59).
# For 12+ the installation type is "composer" if composer.lock contains
# typo3/cms-core or config/system exists, otherwise "classic"; override with
# DEPLOY_TYPO3_MODE = composer|classic.
# Sources, like Shopware 5:
#   DEPLOY_CONFIG_FILE: a *file*-type CI variable
#      with the complete PHP file, copied verbatim to the version's path
#   otherwise DEPLOY_DATABASE_URL:
#      mysql://user:pass@host:port/db is turned into the DB settings on the
#      server: ['DB']['Connections']['Default'] for 8+, ['DB']['host'] etc. for
#      6-7. Not possible for <6, where the whole localconf.php is replaced
#      (exit 60: use the file variable).
# When either is set the target is fully managed and rewritten on every deploy
# (keep it out of git); when neither is set nothing is touched. Values travel
# as files next to ci-deploy.sh, never through the job log.
emit_typo3_config() {
  local db_var="DEPLOY_DATABASE_URL"
  local db_url="$DEPLOY_DATABASE_URL"
  local cfg_file="$DEPLOY_CONFIG_FILE"
  local version="$DEPLOY_TYPO3_VERSION"
  local mode="$DEPLOY_TYPO3_MODE"
  if [[ -n "$mode" && "$mode" != "composer" && "$mode" != "classic" ]]; then echo "DEPLOY_TYPO3_MODE must be composer or classic" >&2 ; exit 16 ; fi

  rm -f ci-deploy.config.php
  : > ci-deploy.env
  if [[ -n "$cfg_file" && -f "$cfg_file" ]]; then
    cp "$cfg_file" ci-deploy.config.php
  elif [[ -n "$db_url" ]]; then
    if [[ "$db_url" == *"'"* ]]; then echo "$db_var contains a single quote" >&2 ; exit 56 ; fi
    printf "DATABASE_URL='%s'\n" "$db_url" > ci-deploy.env
  else
    return 0
  fi

  echo "T3V='${version%%.*}'"
  echo "T3MODE='$mode'"
  echo "if [[ -z \"\$T3V\" && -f composer.lock ]]; then T3V=\$($PHP_DIR/$PHP_CMD -r '\$l = json_decode(file_get_contents(\"composer.lock\"), true); foreach (array_merge(\$l[\"packages\"] ?? [], \$l[\"packages-dev\"] ?? []) as \$p) { if (\$p[\"name\"] === \"typo3/cms-core\") { echo (int) ltrim(\$p[\"version\"], \"v\"); } }') ; fi"
  cat <<'REMOTE'
[[ "$T3V" =~ ^[0-9]+$ && "$T3V" -gt 0 ]] || { echo "cannot determine the TYPO3 version: set DEPLOY_TYPO3_VERSION" ; exit 59 ; }
if (( T3V >= 12 )); then
  if [[ -z "$T3MODE" ]]; then
    if grep -qs '"typo3/cms-core"' composer.lock || [[ -d config/system ]]; then T3MODE=composer ; else T3MODE=classic ; fi
  fi
  if [[ "$T3MODE" == composer ]]; then CFG=config/system/additional.php ; else CFG=typo3conf/system/additional.php ; fi
elif (( T3V >= 6 )); then CFG=typo3conf/AdditionalConfiguration.php
else CFG=typo3conf/localconf.php ; fi
mkdir -p "$(dirname "$CFG")" || exit 53
if [[ -s "$HOME/ci-deploy.config.php" ]]; then
  mv "$HOME/ci-deploy.config.php" "$CFG" && chmod 600 "$CFG" || exit 53
elif [[ -s "$HOME/ci-deploy.env" ]]; then
  (( T3V >= 6 )) || { echo "DATABASE_URL can't be turned into a TYPO3 $T3V localconf.php, use DEPLOY_CONFIG_FILE" ; exit 60 ; }
  cat > "$HOME/ci-deploy-db.php" <<'PHP'
<?php
$u = parse_url(getenv('DB_URL'));
$v = (int) getenv('T3V');
$h = $u['host'] ?? 'localhost'; $p = (int) ($u['port'] ?? 3306);
$n = urldecode($u['user'] ?? ''); $w = urldecode($u['pass'] ?? ''); $d = ltrim($u['path'] ?? '', '/');
echo "<?php\n";
if ($v >= 8) {
    echo "\$GLOBALS['TYPO3_CONF_VARS']['DB']['Connections']['Default'] = array_merge(\$GLOBALS['TYPO3_CONF_VARS']['DB']['Connections']['Default'] ?? [], "
        . var_export(['driver' => 'mysqli', 'host' => $h, 'port' => $p, 'user' => $n, 'password' => $w, 'dbname' => $d], true) . ");\n";
} else {
    foreach (['host' => $h, 'port' => $p, 'username' => $n, 'password' => $w, 'database' => $d] as $k => $x) {
        echo "\$GLOBALS['TYPO3_CONF_VARS']['DB']['$k'] = " . var_export($x, true) . ";\n";
    }
}
PHP
REMOTE
  echo "  T3V=\"\$T3V\" DB_URL=\$(sed -n \"s/^DATABASE_URL='\\(.*\\)'\$/\\1/p\" \"\$HOME/ci-deploy.env\") $PHP_DIR/$PHP_CMD \"\$HOME/ci-deploy-db.php\" > \"\$CFG\" && chmod 600 \"\$CFG\" || exit 53"
  echo '  rm -f "$HOME/ci-deploy-db.php"'
  echo 'fi'
  echo 'rm -f "$HOME/ci-deploy.config.php" "$HOME/ci-deploy.env"'
}

# Shopware only: run after composer install. Creates the JWT keys if missing
# and, only if DEPLOY_AUTO_INSTALL=1 is set,
# installs into an empty database (skipped when Shopware is already installed).
emit_shopware_bootstrap() {
  local install="$DEPLOY_AUTO_INSTALL"
  echo "if [[ ! -f config/jwt/private.pem ]]; then $PHP_DIR/$PHP_CMD bin/console system:generate-jwt-secret || exit 54 ; fi"
  if [[ "$install" == "1" ]]; then
    echo "if ! $PHP_DIR/$PHP_CMD bin/console system:is-installed ; then $PHP_DIR/$PHP_CMD bin/console system:install --basic-setup || exit 55 ; fi"
  fi
}

# Version of https://github.com/nvm-sh/nvm's install.sh to bootstrap with
# when nvm isn't already present on the target server -- pinned for
# reproducibility, bump deliberately.
NVM_INSTALL_VERSION="v0.40.1"

# Optional: DEPLOY_NODE_VERSION picks a Node version via nvm for project types whose build step needs one
# different from the server's default -- e.g. a Shopware version that isn't
# compatible with it. No-op (server's default Node stays in effect) when
# neither is set, so existing projects are unaffected. Installs nvm itself
# (via its official install.sh, pinned to $NVM_INSTALL_VERSION) into
# ~/.nvm on the target server first if it isn't there yet.
emit_nvm_use() {
  local node_version="$DEPLOY_NODE_VERSION"
  if [[ -n "$node_version" ]]; then
    echo "export NVM_DIR=\"\$HOME/.nvm\""
    echo "if [[ ! -s \"\$NVM_DIR/nvm.sh\" ]]; then curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_INSTALL_VERSION/install.sh | bash || exit 49 ; fi"
    echo ". \"\$NVM_DIR/nvm.sh\" || exit 49"
    echo "nvm install $node_version || exit 50"
    echo "nvm use $node_version || exit 51"
  fi
}

{ project_tail ; } > ci-deploy.sh

cat ci-deploy.sh

# Every role except live executes immediately. Live executes only with
# DEPLOY_AUTO_DEPLOY=1, which .deploy_live_base sets; a CI/CD variable
# DEPLOY_AUTO_DEPLOY=0 (scoped to the live environment) overrides it, and the
# job then only dumps the script for manual execution on the server.
echo "DEPLOY_AUTO_DEPLOY=$DEPLOY_AUTO_DEPLOY"
if [[ "$DEPLOY_ROLE" != "live" || "$DEPLOY_AUTO_DEPLOY" == "1" ]]; then
  for f in ci-deploy.env ci-deploy.config.php; do
    if [[ -f "$f" ]]; then
      scp -o StrictHostKeyChecking=no "$f" $USER@$DEPLOY_HOST:~/"$f" || exit 57
    fi
  done
  scp -o StrictHostKeyChecking=no ci-deploy.sh $USER@$DEPLOY_HOST:~/ci-deploy.sh &&
  ssh -o StrictHostKeyChecking=no $USER@$DEPLOY_HOST "$REMOTE_SHELL ~/ci-deploy.sh"
fi