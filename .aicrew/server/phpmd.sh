#!/usr/bin/env bash
# GENERATED copy of the shared deploy scripts -- do not edit here; change common/server and re-run sync-common.mjs
echo "phpmd for ${PROJECT_TYPE}"
mkdir -p "$(pwd)/.reports"

[ -f ./.config/phpmd.xml ] && PHPMD_CONFIG=./.config/phpmd.xml || PHPMD_CONFIG=./.aicrew/phpmd.xml

DIRS=( / )

if [[ "$PROJECT_TYPE" == "shopware5" ]]; then
  DIRS=( /engine/Shopware/Plugins/Local/ /custom/project/ )
fi

if [[ "$PROJECT_TYPE" == "shopware6" ]]; then
  DIRS=( /custom/static-plugins/ )
fi

if [[ "$PROJECT_TYPE" == "shopware65" ]]; then
  DIRS=( /custom/static-plugins/ )
fi

if [[ "$PROJECT_TYPE" == "typo3" ]]; then
  [ -d extensions ] && DIRS=( /extensions/ )
  [ -d packages ] && DIRS=( /packages/ )
fi

if [[ "$PROJECT_TYPE" == "typo3_extension" ]]; then
  DIRS=( /Classes/ /Configuration/ /Resources/ ext_emconf.php ext_localconf.php ext_tables.php)
fi

if [[ "$PROJECT_TYPE" == "laravel" ]]; then
  DIRS=( ./app/ ./bootstrap/ ./config ./database/ ./resources ./routes ./tests )
fi

echo "phpmd.sh PWD: $(pwd)"
PHPMD_VERSION="${PHPMD_VERSION:-2.15.0}"
# A runner user that cannot write to /usr/local/bin sets PHPMD_PHAR to a path of its own.
PHPMD_PHAR="${PHPMD_PHAR:-/usr/local/bin/phpmd.phar}"
if [[ ! -f "$PHPMD_PHAR" ]]; then
  curl -sSLf -o "$PHPMD_PHAR" "https://github.com/phpmd/phpmd/releases/download/${PHPMD_VERSION}/phpmd.phar" || exit 1
fi
for DIR in "${DIRS[@]}"
do
  # DIRS are project-relative; a leading "/" only marks them as such
  DIR="./${DIR#/}"
  if [[ -r $DIR ]]; then
    php -d memory_limit=-1 "$PHPMD_PHAR" \
      "$DIR" text "$PHPMD_CONFIG" \
      --reportfile=./.reports/phpmd-custom.txt \
      --exclude=*/vendor/*,*/Packages/Libraries/*
  fi
done
