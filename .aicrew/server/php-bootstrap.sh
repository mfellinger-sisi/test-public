#!/bin/sh
# GENERATED copy of the shared deploy scripts -- do not edit here; change common/server and re-run sync-common.mjs
# Sourced by composer.sh / composer_dev.sh. Turns a plain public php:<ver>-cli
# image into what the old private shopware-composer image provided: the pinned
# composer version ($COMPOSER_VERSION), the PHP extensions ($PHP_EXTENSIONS),
# git/unzip/ssh. Every step is skipped when already present, so a prebuilt
# $COMPOSER_IMAGE (composer + extensions baked in) makes this a no-op.
set -e

if command -v apk > /dev/null; then
  need=""
  for bin in git unzip ssh; do command -v "$bin" > /dev/null || need="$need $bin"; done
  # apk package names: git, unzip, openssh-client
  pkgs=""
  for bin in $need; do [ "$bin" = ssh ] && pkgs="$pkgs openssh-client" || pkgs="$pkgs $bin"; done
  [ -n "$pkgs" ] && apk add --no-cache $pkgs > /dev/null
elif command -v apt-get > /dev/null; then
  apt-get update -qq > /dev/null && apt-get install -y -qq git unzip openssh-client > /dev/null
fi

if [ -n "$PHP_EXTENSIONS" ]; then
  missing=""
  for ext in $PHP_EXTENSIONS; do php -m | grep -qix "$ext" || missing="$missing $ext"; done
  if [ -n "$missing" ]; then
    curl -sSLf -o /usr/local/bin/install-php-extensions \
      https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions
    chmod +x /usr/local/bin/install-php-extensions
    install-php-extensions $missing
  fi
fi

if ! command -v composer > /dev/null; then
  curl -sSLf -o /usr/local/bin/composer "https://getcomposer.org/download/${COMPOSER_VERSION:-latest-stable}/composer.phar"
  chmod +x /usr/local/bin/composer
fi
set +e
