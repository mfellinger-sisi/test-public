#!/usr/bin/env bash
# GENERATED copy of the shared deploy scripts -- do not edit here; change common/server and re-run sync-common.mjs
PROJECT_TYPE=shopware6
DEPLOYMENT_LABEL="Shopware 6"
REMOTE_SHELL="/bin/bash --login -x"

project_tail() {
  emit_mkdir
  emit_path_export
  emit_composer_auth
  emit_nvm_use
  echo "echo \$PATH"
  echo "which npm"
  emit_composer_file_check
  emit_php_exec_check
  git_sync_block
  emit_shopware_env
  emit_executable_check bin/build-storefront.sh
  emit_executable_check bin/build.sh
  emit_executable_check bin/console
  emit_composer_install
  emit_shopware_bootstrap
  echo "$TARGETPATH/bin/build-storefront.sh || exit 46"
  echo "$TARGETPATH/bin/build.sh || exit 47"
  emit_console_command "" "plugin:refresh" 43
  emit_console_command "" "cache:clear" 44
  emit_console_command "" "theme:compile" 45
}

source "$(dirname "$0")/deploy.sh"