#!/usr/bin/env bash
# GENERATED copy of the shared deploy scripts -- do not edit here; change common/server and re-run sync-common.mjs

[ -f "./.config/.stylelintrc.json" ] && CONFIG_PATH=./.config/.stylelintrc.json || CONFIG_PATH=.aicrew/.stylelintrc.json
stylelint --allow-empty-input --color --config $CONFIG_PATH --color '**/*.scss'
stylelint --allow-empty-input --color --config $CONFIG_PATH --color '**/*.less'
