#!/bin/sh
# GENERATED copy of the shared deploy scripts -- do not edit here; change common/server and re-run sync-common.mjs
# Runs inside the pipelinecomponents/yamllint image (see the yamllint job).
YAMLLINT_CONFIG=.aicrew/.yamllint

if test -f ".config/.yamllint"; then
  YAMLLINT_CONFIG=.config/.yamllint
fi

pwd
yamllint --version
[ -d src ] && yamllint -s -c "$YAMLLINT_CONFIG" src
[ -d test ] && yamllint -s -c "$YAMLLINT_CONFIG" test
