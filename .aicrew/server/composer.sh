#!/usr/bin/env bash
# Composer install for the checks on a GitHub runner (setup-php provides php and composer). The job's token is
# composer's github-oauth for this host (rate limit, and packages of this repository); packages from other private
# repositories need a COMPOSER_AUTH secret, which composer reads by itself.
if [[ -f "composer.json" || -f "composer.lock" ]] ; then
  GH_HOST="${GITHUB_SERVER_URL#*://}"
  GH_HOST="${GH_HOST:-github.com}"
  if [[ -n "$GITHUB_TOKEN" ]]; then
    [[ "$GH_HOST" != "github.com" ]] && composer config -g github-domains github.com "$GH_HOST"
    composer config -g "github-oauth.${GH_HOST}" "$GITHUB_TOKEN"
  fi
  echo composer install --prefer-dist --no-dev --no-scripts
  composer install --prefer-dist --no-dev --no-scripts
fi
