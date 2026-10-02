#!/bin/bash
# GENERATED copy of the shared deploy scripts -- do not edit here; change common/server and re-run sync-common.mjs
echo "phpcs for ${PROJECT_TYPE}"
mkdir -p ./.reports

PHPCS_DIR=./

[ -f ./.aicrew/ruleset-${PROJECT_TYPE}.xml ] && RULESET_PATH=./.aicrew/ruleset-${PROJECT_TYPE}.xml || RULESET_PATH=./.aicrew/ruleset.xml
[ -f "./.config/ruleset.xml" ] && RULESET_PATH=./.config/ruleset.xml || RULESET_PATH=${RULESET_PATH}

[ "${PROJECT_TYPE}" = "shopware5" ] && PHPCS_DIR=./custom/project
[ "${PROJECT_TYPE}" = "shopware6" ] && PHPCS_DIR=./custom/static-plugins/
[ "${PROJECT_TYPE}" = "shopware65" ] && PHPCS_DIR=./custom/static-plugins/
if [ "${PROJECT_TYPE}" = "typo3" ] ; then
  [ -d "./extensions/" ] && PHPCS_DIR=./extensions/
  [ -d "./packages/" ] && PHPCS_DIR=./packages/
fi

if [ -d "${PHPCS_DIR}" ] ; then
	phpcs -s \
	      --report-full \
	      --report-checkstyle=./.reports/phpcs-checkstyle.txt \
	      --report-code=./.reports/phpcs-code.txt \
	      --report-csv=./.reports/phpcs.csv \
	      --report-emacs=./.reports/phpcs-emacs.txt \
	      --report-gitblame=./.reports/phpcs-blame.txt \
	      --report-info=./.reports/phpcs-info.txt \
	      --report-json=./.reports/phpcs.json \
	      --report-junit=./.reports/phpcs-junit.xml \
	      --report-summary=./.reports/phpcs-summary.txt \
	      --report-source=./.reports/phpcs-source.txt \
	      --ignore=*/vendor/* \
	      -n --extensions=php --standard=${RULESET_PATH} -p \
	      ${PHPCS_DIR}
fi
