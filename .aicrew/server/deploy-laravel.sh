#!/usr/bin/env bash
# GENERATED copy of the shared deploy scripts -- do not edit here; change common/server and re-run sync-common.mjs
PROJECT_TYPE=laravel
DEPLOYMENT_LABEL=LARAVEL

project_tail() {
  emit_mkdir
  emit_path_export
  emit_composer_auth
  emit_composer_file_check
  emit_php_exec_check
  git_sync_block
  emit_laravel_env
  emit_composer_install "--optimize-autoloader"
  echo "./artisan cache:clear || exit 38"
  echo "./artisan route:clear || exit 39"
  echo "./artisan route:cache || exit 40"
  echo "./artisan view:clear || exit 41"
  echo "./artisan view:cache || exit 42"
}

source "$(dirname "$0")/deploy.sh"