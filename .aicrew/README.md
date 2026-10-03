# github

The deploy pipeline for repositories on **GitHub** (github.com and Enterprise
Server): the same deploy scripts and the same `DEPLOY_*` variables as the
GitLab bundle, run by GitHub Actions. AI Crew installs it: this folder becomes
**`.aicrew/`** in the repository and AI Crew generates **`.github/workflows/aicrew.yml`**
from the project type and the list of environments. That workflow is entirely
generated (its first line says so): do not edit it, it is rewritten when
environments are added, renamed or removed. Other workflows of the repository
are never touched, and a file at that path that AI Crew did not write is not
overwritten.

## Jobs

| Job | What it does |
|---|---|
| `php-codesniffer`, `phpmd`, `phpstan` | quality checks; they **report** unless `CHECKS_BLOCK_DEPLOY` is `1` |
| `composer` (and `composer (dev packages)` for plugins and extensions) | installs the packages once and hands them to the later jobs |
| `stylelint` (TYPO3, plugins) / `yamllint` (plugins, `USE_YAMLLINT=1`) | always stop the deploy when they fail |
| `deploy <environment>` | one per environment, in the GitHub environment of the same name |
| `package` (plugins, extensions) | a zip of the repository on the default branch and on tags |

Runs start on every push and by hand (`workflow_dispatch`). The deploy jobs
pick their branch by condition, so a changed branch name is a variable, not a
new workflow:

| Role | Runs on | When |
|---|---|---|
| `staging` | `DEPLOY_STAGING_BRANCH` (default `staging`) | on every push |
| `live` | `DEPLOY_LIVE_BRANCH` (default `main`) | on every push |
| `other` | either of the two | only when started by hand |

Live deploys on every push to the live branch: the approval happens before the
push, so keep that branch for approved changes. `DEPLOY_AUTO_DEPLOY=0` (an
environment variable of the live environment) makes the live job only print the
script.

A deploy job waits for the checks and runs unless one of them **failed** (a
check switched off with `USE_PHPMD=0` / `USE_PHPSTAN=0` is skipped and does not
stop it). Deploys of one environment never run at the same time and a running
deploy is never cut off; GitHub keeps only the newest waiting run per
environment, which is what a deploy wants (the newest commit wins).

### Quality checks do not block deploys

`php-codesniffer`, `phpmd` and `phpstan` report their findings but the
workflow carries on, so existing code that does not pass the rules can still be
deployed. Set the repository variable `CHECKS_BLOCK_DEPLOY` to `1` once a
project is green: then a failing check stops the deploy. A changed value
applies to new runs; a re-run keeps the value it started with.

## Variables and secrets

The variables are the ones of the GitLab bundle (`DEPLOY_URL`, `DEPLOY_USER`,
`DEPLOY_PATH`, `DEPLOY_PHP_CMD`, `DEPLOY_PHP_DIR`, `DEPLOY_PRIVATE_KEY`,
`DEPLOY_DATABASE_URL`, `DEPLOY_ENV_<KEY>`, `DEPLOY_COMPOSER_CMD`, ...; see that
README for the meaning of each). Where they live on GitHub:

- **Environment secrets and variables** of the environment the job deploys to
  (Settings, Environments): the per-environment `DEPLOY_*` values. Credentials
  (`DEPLOY_PRIVATE_KEY`, `DEPLOY_DATABASE_URL`, `DEPLOY_ENV_*`, `DEPLOY_ENV_FILE`,
  `DEPLOY_CONFIG_FILE`) are **secrets**, everything else is a **variable**.
  AI Crew limits each environment to its branch (the *deployment branch
  policy*), which is what keeps the secrets away from other branches.
- **Repository variables**: `DEPLOY_STAGING_BRANCH`, `DEPLOY_LIVE_BRANCH`,
  `PHP_VERSION`, `COMPOSER_VERSION`, `PHP_EXTENSIONS`, `PHPSTAN_VERSION`,
  `PHPMD_VERSION`, `USE_PHPSTAN`, `USE_PHPMD`, `USE_YAMLLINT`,
  `CHECKS_BLOCK_DEPLOY`, `AICREW_RUNNER` (a runner label for self-hosted runners,
  default `ubuntu-26.04`: pinned on purpose instead of `ubuntu-latest`, which would move under the pipeline; set
  `ubuntu-24.04` to go back to the previous image).
- Names must not start with `GITHUB_`, values are limited to 48 KB.

GitHub has no file-type variables and hands a job only the names the workflow
lists. The workflow therefore passes the variable and secret stores of the
environment as JSON to the deploy step (and only to it), and `server/provider.sh`
exports the `DEPLOY_*` names (and the pipeline switches) from them. Names the
job already sets (`DEPLOY_ROLE`, `DEPLOY_ENVIRONMENT`) are never overridden.
`DEPLOY_ENV_FILE` and `DEPLOY_CONFIG_FILE` hold the file's **content**: they are
written to a private temporary file outside the checkout and the variable is
pointed at it. `DEPLOY_PRIVATE_KEY` is a plain secret fed to the ssh agent
through stdin; it never lands in the project directory or in a log.

## Requirements

- GitHub-hosted `ubuntu-26.04` runners, or self-hosted ones (label in
  `AICREW_RUNNER`) with bash, `jq` or `python3`, `curl`, ssh and either root or `sudo`
  with apt (the deploy installs `dnsutils` and `openssh-client` when missing).
- Outbound access to github.com (actions, phars) and getcomposer.org.
- The deploy target must be able to reach this GitHub: the server clones and
  fetches with the job's `GITHUB_TOKEN`, which is not stored in the checkout's
  `origin`: git gets it through an `insteadOf` rule in the deploy user's global
  git config, replaced on every deploy. The workflow's token is read-only
  (`contents: read`).
- The crew pushes to the repository with a deploy key per repository or with a
  machine user (set in AI Crew, "Push access").

`server/` is mostly a GENERATED copy of `packages/deploy/common/server/`
(everything except `provider.sh`, `composer.sh`, `composer_dev.sh` and
`deploy-plugin.sh`, which are GitHub's own): change the script in
`common/server/`, run `node packages/deploy/scripts/sync-common.mjs`, bump
`VERSION` and run `node packages/deploy/scripts/bundle-hash.mjs --update`.

## Version

`VERSION` holds the installed version (semver); `cat .aicrew/VERSION` in a
repository tells which release it runs. The deploy log prints it
(`deploy/github 1.0.0`). Bump it in every change that repositories need to
re-install: patch for fixes, minor for new variables, major for anything that
changes the generated workflow in a way that needs action. Every release gets an entry in `CHANGES.md` (a test
fails without one); the install preview shows the entries between the installed and the new version.
