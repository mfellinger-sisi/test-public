#!/usr/bin/env bash
# GENERATED copy of the shared deploy scripts -- do not edit here; change common/server and re-run sync-common.mjs
if [[ "$USE_PHPSTAN" == "1" ]]; then
  echo phpstan for project type ${PROJECT_TYPE} with PHP ${PHP_VERSION} 

  # Runs in the job's own PHP image ($TOOLS_IMAGE, PHP $PHP_VERSION) -- no docker-in-docker.
  PHPSTAN_VERSION="${PHPSTAN_VERSION:-1.12.24}"
  # A runner user that cannot write to /usr/local/bin sets PHPSTAN_PHAR to a path of its own.
  PHPSTAN_PHAR="${PHPSTAN_PHAR:-/usr/local/bin/phpstan.phar}"
  if [[ ! -f "$PHPSTAN_PHAR" ]]; then
    curl -sSLf -o "$PHPSTAN_PHAR" "https://github.com/phpstan/phpstan/releases/download/${PHPSTAN_VERSION}/phpstan.phar" || exit 1
  fi
  PHPSTAN_CMD="php -d memory_limit=${PHPSTAN_MEMORY_LIMIT:-2G} $PHPSTAN_PHAR"
  PHPSTAN_DIR_PREFIX=.
  echo "PHPSTAN_CMD: $PHPSTAN_CMD"

  # Priority of config files:
  # .config/phpstan.neon
  # .config/phpstan-server-${PROJECT_TYPE}.neon
  # .aicrew/phpstan-server-${PROJECT_TYPE}.neon
  # .aicrew/phpstan-server.neon
  [ -f "./.aicrew/phpstan-server-${PROJECT_TYPE}.neon" ] && RULESET_PATH=./.aicrew/phpstan-server-${PROJECT_TYPE}.neon || RULESET_PATH=./.aicrew/phpstan-server.neon
  [ -f "./.config/phpstan-server-${PROJECT_TYPE}.neon" ] && RULESET_PATH=./.config/phpstan-server-${PROJECT_TYPE}.neon || RULESET_PATH=${RULESET_PATH}
  [ -f "./.config/phpstan.neon" ] && RULESET_PATH=./.config/phpstan.neon || RULESET_PATH=${RULESET_PATH}

  echo Using ruleset ${RULESET_PATH}

  if [[ "$PROJECT_TYPE" == "laravel" ]]; then
    DIR=$PHPSTAN_DIR_PREFIX/app/
  fi

  if [[ "$PROJECT_TYPE" == "shopware5" ]]; then
    DIR=$PHPSTAN_DIR_PREFIX/custom/project/
  fi

  if [[ "$PROJECT_TYPE" == "shopware6" || "$PROJECT_TYPE" == "shopware65" ]]; then
    DIR=$PHPSTAN_DIR_PREFIX/custom/static-plugins/
  fi

  if [[ "$PROJECT_TYPE" == "typo3" ]]; then
    [ -d "./extensions" ] && DIR=$PHPSTAN_DIR_PREFIX/extensions/
    [ -d "./packages" ] && DIR=$PHPSTAN_DIR_PREFIX/packages/
  fi

  if [[ "$PROJECT_TYPE" == "typo3_extension" ]]; then
    pwd
    find . -not \( -path ./vendor -prune \) -not \( -path ./libs -prune \) -not \( -path ./public -prune \) -name \*.php > analyze_files.txt
    cat analyze_files.txt | xargs $PHPSTAN_CMD analyze -c ${RULESET_PATH}
  else
    if [[ "$PROJECT_TYPE" =~ ^plugin* ]]; then
      pwd
      find . -not \( -path ./vendor -prune \) -not \( -path ./libs -prune \) -name \*.php > analyze_files.txt
      cat analyze_files.txt | xargs $PHPSTAN_CMD analyze -c ${RULESET_PATH}
    else
      pwd
      $PHPSTAN_CMD analyze \
      -c ${RULESET_PATH} \
      $DIR
    fi
  fi
fi
