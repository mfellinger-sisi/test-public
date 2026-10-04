#!/usr/bin/env bash
# Provider shim: GitHub Actions. Sourced by deploy.sh (and deploy-plugin.sh); maps GitHub's default variables to the
# neutral names the deploy scripts read, brings the environment's variables and secrets into the shell and loads the
# deploy key. Another CI host ships its own provider.sh with the same names and the same hook.
#
#   DEPLOY_ENVIRONMENT  name of the environment the job deploys to (set in the generated workflow's job env)
#   DEPLOY_REPO_URL     URL the server clones/fetches the repository from (carries the job token, deploy.sh strips it)
#   DEPLOY_PROJECT_ID   stable id of the repository on the host (survives rename and transfer)
#   DEPLOY_BRANCH       branch being deployed
#   DEPLOY_PROVIDER     provider id, shown in the "deploy/<id> <version>" log line
#
# GitHub hands a job only the variables and secrets that are named in the workflow, and the free-form
# DEPLOY_ENV_<KEY> names cannot be listed in a generated file. So the workflow passes both stores as JSON
# (AICREW_VARS, AICREW_SECRETS, from toJSON(vars) / toJSON(secrets), on the deploy step only) and this file exports
# the names a deploy reads. Whatever the job already sets (DEPLOY_ROLE, DEPLOY_ENVIRONMENT, ...) is never overridden.

GH_HOST="${GITHUB_SERVER_URL#*://}"
GH_HOST="${GH_HOST%/}"
DEPLOY_REPO_URL="https://x-access-token:${GITHUB_TOKEN}@${GH_HOST}/${GITHUB_REPOSITORY}.git"
DEPLOY_PROJECT_ID="$GITHUB_REPOSITORY_ID"
DEPLOY_BRANCH="$GITHUB_REF_NAME"
DEPLOY_PROVIDER="github"

# Names a job may receive from the variable stores; everything else (other workflows' secrets) is ignored.
AICREW_IMPORT_RE='^(DEPLOY_|USE_|PHP_|COMPOSER_|CHECKS_|PHPSTAN_|PHPMD_)[A-Z0-9_]*$'
# What the job or this file decides: a variable of that name must not change it.
AICREW_KEEP_RE='^(DEPLOY_ROLE|DEPLOY_ENVIRONMENT|DEPLOY_REPO_URL|DEPLOY_PROJECT_ID|DEPLOY_BRANCH|DEPLOY_PROVIDER)$'

# aicrew_pairs <json> -- the string members of a JSON object as NAME NUL VALUE NUL, names upper-cased (secret and
# variable names are case-insensitive on GitHub). jq where there is one (every GitHub-hosted runner), python3 otherwise.
aicrew_pairs() {
  local tool="${AICREW_JSON_TOOL:-}"
  [[ -n "$tool" ]] || { command -v jq > /dev/null && tool=jq || tool=python3; }
  case "$tool" in
    jq) jq -j 'to_entries[] | select(.value | type == "string") | (.key | ascii_upcase), "\u0000", .value, "\u0000"' <<< "$1" ;;
    python3) python3 -c 'import json, sys
for k, v in json.load(sys.stdin).items():
    if isinstance(v, str):
        sys.stdout.buffer.write(k.upper().encode() + b"\0" + v.encode() + b"\0")' <<< "$1" ;;
    *) echo "neither jq nor python3 is available on the runner" >&2 ; exit 4 ;;
  esac
}

# aicrew_import <json> -- exports the allowed names from one JSON store of NAME: value pairs.
aicrew_import() {
  local json="$1" name value
  [[ -n "$json" && "$json" != "{}" ]] || return 0
  while IFS= read -r -d '' name && IFS= read -r -d '' value; do
    [[ "$name" =~ $AICREW_IMPORT_RE ]] || continue
    [[ "$name" =~ $AICREW_KEEP_RE ]] && continue
    [[ -z "${!name+x}" ]] || continue # already set by the job
    export "$name=$value"
  done < <(aicrew_pairs "$json")
}
aicrew_import "$AICREW_VARS"
aicrew_import "$AICREW_SECRETS"
unset AICREW_VARS AICREW_SECRETS

# File-type variables do not exist on GitHub: DEPLOY_ENV_FILE and DEPLOY_CONFIG_FILE hold the CONTENT, which is
# written to a private temporary file outside the checkout (a deploy that copies the checkout must never upload
# it) and the variable is pointed at that file, as deploy.sh expects.
AICREW_TMP="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/aicrew-$$"
for name in DEPLOY_ENV_FILE DEPLOY_CONFIG_FILE; do
  if [[ -n "${!name}" ]]; then
    ( umask 077; mkdir -p "$AICREW_TMP" )
    ( umask 077; printf '%s\n' "${!name}" > "$AICREW_TMP/$name" )
    export "$name=$AICREW_TMP/$name"
  fi
done

# The deploy key goes to the ssh agent through stdin, never into a file or the checkout. CRs are stripped and a final
# newline added, which ssh-add needs. Every line is masked in the log before anything else touches it.
if [[ -n "$DEPLOY_PRIVATE_KEY" ]]; then
  while IFS= read -r line; do [[ -n "$line" ]] && echo "::add-mask::${line%$'\r'}"; done <<< "$DEPLOY_PRIVATE_KEY"
  mkdir -p ~/.ssh
  eval "$(ssh-agent -s)" > /dev/null
  { printf '%s' "$DEPLOY_PRIVATE_KEY" | tr -d '\r'; echo; } | ssh-add - || { echo "the deploy key could not be loaded (DEPLOY_PRIVATE_KEY)" >&2 ; exit 5 ; }
  grep -qs 'StrictHostKeyChecking' ~/.ssh/config 2> /dev/null || printf 'Host *\n\tStrictHostKeyChecking no\n\n' >> ~/.ssh/config
  unset DEPLOY_PRIVATE_KEY
fi

# emit_repo_auth git|composer -- host-specific authentication on the server,
# emitted into the remote script by deploy.sh's git_sync_block:
#   git       after origin is set, before fetch: lets git (and submodules on
#             the same host) authenticate against the host
#   composer  after checkout: lets composer install private packages from the
#             host (needs $PHP_DIR/$PHP_CMD/$COMPOSER_CMD, set by deploy.sh)
emit_repo_auth() {
  case "$1" in
    git)
      # The token is part of the section name, so drop sections left over from earlier deploys (their job tokens have
      # expired) instead of piling up new ones.
      echo "for k in \$(git config --global --name-only --get-regexp '^url\\..*x-access-token:.*\\.insteadof\$') ; do git config --global --remove-section \"\${k%.insteadof}\" ; done"
      echo "git config --global url.\"https://x-access-token:${GITHUB_TOKEN}@${GH_HOST}/\".insteadOf \"https://${GH_HOST}/\" || exit 58"
      ;;
    composer)
      # skipped without a composer.json (e.g. classic TYPO3). The job token expires within the hour, so it is NEVER written
      # to composer's global auth.json: a composer older than 2.2.30 refuses a token with a "-" in it, and one such token
      # left there fails every later composer call on that server (exit 34). It travels in COMPOSER_AUTH for this deploy
      # only, as http-basic (no format check). A token an older deploy left in auth.json is removed first.
      local php="$PHP_DIR/$PHP_CMD"
      echo "if [[ -f composer.json ]]; then"
      echo "  for f in \"\${COMPOSER_HOME:-/nonexistent}/auth.json\" \"\${XDG_CONFIG_HOME:-\$HOME/.config}/composer/auth.json\" \"\$HOME/.composer/auth.json\"; do"
      echo "    if [[ -f \"\$f\" ]]; then GH_HOST='${GH_HOST}' $php -r '\$a = json_decode(file_get_contents(\$argv[1])); \$h = getenv(\"GH_HOST\"); if (!is_object(\$a)) exit; \$c = false; foreach ([\"bitbucket-oauth\", \"github-oauth\", \"gitlab-oauth\", \"gitlab-token\", \"http-basic\", \"bearer\", \"forgejo-token\"] as \$k) { if (isset(\$a->\$k) && is_array(\$a->\$k) && !\$a->\$k) { \$a->\$k = new stdClass; \$c = true; } } if (isset(\$a->{\"github-oauth\"}->{\$h})) { unset(\$a->{\"github-oauth\"}->{\$h}); \$c = true; } if (\$c) file_put_contents(\$argv[1], json_encode(\$a, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));' \"\$f\"; fi"
      echo "  done"
      if [[ "$GH_HOST" != "github.com" ]]; then
        echo "  $php $COMPOSER_CMD config -g github-domains github.com ${GH_HOST} || exit 34"
      fi
      echo "  export COMPOSER_AUTH=\$(AUTH_IN=\"\${COMPOSER_AUTH:-}\" GH_HOST='${GH_HOST}' GH_TOK='${GITHUB_TOKEN}' $php -r '\$a = json_decode(getenv(\"AUTH_IN\") ?: \"{}\", true); if (!is_array(\$a)) \$a = []; \$h = getenv(\"GH_HOST\"); if (!isset(\$a[\"http-basic\"][\$h])) { \$a[\"http-basic\"][\$h] = [\"username\" => \"x-access-token\", \"password\" => getenv(\"GH_TOK\")]; } echo json_encode(\$a, JSON_UNESCAPED_SLASHES);')"
      echo "fi"
      ;;
    *) echo "emit_repo_auth: unknown phase $1" >&2 ; exit 4 ;;
  esac
}
