#!/usr/bin/env bash
# GENERATED copy of the shared deploy scripts -- do not edit here; change common/server and re-run sync-common.mjs
PROJECT_TYPE=typo3
DEPLOYMENT_LABEL=TYPO3

project_tail() {
  local TYPO3_CONTEXT
  if [[ "$DEPLOY_ROLE" == "live" ]]; then
    TYPO3_CONTEXT=Production
  else
    if [[ "$DEPLOY_ENVIRONMENT" != "Development" ]]; then
      TYPO3_CONTEXT=Development/$DEPLOY_ENVIRONMENT
    else
      TYPO3_CONTEXT=$DEPLOY_ENVIRONMENT
    fi
  fi

  emit_mkdir
  emit_path_export
  echo "echo \$PATH"
  echo "export TYPO3_CONTEXT=$TYPO3_CONTEXT"
  emit_composer_auth
  emit_composer_file_check
  emit_php_exec_check
  git_sync_block
  emit_typo3_config
  # classic installations have no (or no complete) composer setup: only run
  # what the project provides. Anything else goes into the project's own deploy.sh.
  echo "if [[ -f composer.json ]]; then"
  emit_composer_install
  echo "fi"
  echo "if grep -qs '\"typo3-deployment-scripts\"' composer.json; then $PHP_DIR/$PHP_CMD $COMPOSER_CMD run-script typo3-deployment-scripts || exit 37 ; fi"
}

source "$(dirname "$0")/deploy.sh"