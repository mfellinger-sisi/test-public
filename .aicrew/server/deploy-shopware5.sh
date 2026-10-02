#!/usr/bin/env bash
# GENERATED copy of the shared deploy scripts -- do not edit here; change common/server and re-run sync-common.mjs
PROJECT_TYPE=shopware5
DEPLOYMENT_LABEL="Shopware 5"

project_tail() {
  emit_mkdir
  emit_path_export
  emit_composer_auth
  echo "export SHOPWARE_ENV=$(echo "$ENVIRONMENT" | tr '[:upper:]' '[:lower:]')"
  emit_composer_file_check
  emit_php_exec_check
  git_sync_block
  emit_shopware5_config
  emit_executable_check bin/console
  emit_composer_install
  emit_console_command "sw:" "plugin:refresh" 43
  emit_console_command "sw:" "cache:clear" 44
  emit_console_command "sw:" "theme:cache:generate" 45
}

source "$(dirname "$0")/deploy.sh"