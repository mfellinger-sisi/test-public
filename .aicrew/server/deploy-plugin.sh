#!/usr/bin/env bash
# Plugin and extension projects deploy by copying the checkout (rsync over ssh) instead of a git checkout on the
# server. Needs DEPLOY_SERVER (host), DEPLOY_USER, DEPLOY_PATH and DEPLOY_PRIVATE_KEY.
if ! command -v rsync > /dev/null; then
  APT_SUDO=""; [[ "$(id -u)" != "0" ]] && APT_SUDO="sudo"
  $APT_SUDO apt-get update -qq > /dev/null && $APT_SUDO apt-get install -y -qq rsync openssh-client > /dev/null
fi
source "$(dirname "$0")/provider.sh" || { echo "provider.sh not found next to deploy-plugin.sh" ; exit 4 ; }
echo "deploy/${DEPLOY_PROVIDER} $(cat "$(dirname "$0")/../VERSION" 2>/dev/null)"
for v in DEPLOY_SERVER DEPLOY_USER DEPLOY_PATH; do
  [[ -n "${!v}" ]] || { echo "$v is not defined" ; exit 11 ; }
done
echo "$DEPLOY_USER@$DEPLOY_SERVER:$DEPLOY_PATH"
ssh -o StrictHostKeyChecking=no -p22 "$DEPLOY_USER@$DEPLOY_SERVER" "mkdir -p $DEPLOY_PATH" || exit 21
rsync -rav -e ssh ./ "$DEPLOY_USER@$DEPLOY_SERVER:$DEPLOY_PATH" || exit 57
