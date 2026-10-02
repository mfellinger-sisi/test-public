#!/usr/bin/env bash
# GENERATED copy of the shared deploy scripts -- do not edit here; change common/server and re-run sync-common.mjs
PROJECT_TYPE=symfony
DEPLOYMENT_LABEL=SYMFONY

project_tail() {
  emit_mkdir
  emit_path_export
  emit_composer_auth
  emit_composer_file_check
  emit_php_exec_check
  git_sync_block
  emit_symfony_env
  emit_composer_install "--optimize-autoloader"
}

source "$(dirname "$0")/deploy.sh"