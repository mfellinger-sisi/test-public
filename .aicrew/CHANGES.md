# Changes of the GitHub pipeline files

Newest first. One `## <version>` heading per release; the install preview shows the entries between the installed
and the new release. Patch = fixes, minor = new variables, major = changes that need action.

## 1.0.4
- README: own rules go into `.config/` of the repository (wins over `.aicrew/`, never overwritten by an update).

## 1.0.3
- `CHANGES.md` and `MANIFEST` are installed with the files: an update lists what changed, and files edited by hand
  since the install are flagged before they are overwritten.

## 1.0.2
- The generated workflow runs on `ubuntu-26.04` by default instead of `ubuntu-24.04` (checks and a deploy to an old
  server were tested on it). `AICREW_RUNNER` still overrides it per repository.

## 1.0.1
- The workflow is pinned to a runner image (`ubuntu-24.04`) instead of `ubuntu-latest`, which moves under the
  pipeline.
- Install rewrites `.github/workflows/aicrew.yml`: Node 24 action versions, phpmd and phpstan no longer skipped when
  `USE_PHPMD` / `USE_PHPSTAN` are unset, no failing download without a `composer.json`, stylelint installs its
  config package, `PROJECT_TYPE` lives in the file only (the host variable was never read).

## 1.0.0
- First release: workflow generator, deploy scripts, rulesets and tool configuration.
