# Changes of the GitHub pipeline files

Newest first. One `## <version>` heading per release; the install preview shows the entries between the installed
and the new release. Patch = fixes, minor = new variables, major = changes that need action.

## 1.0.7
- The job token is no longer written to composer's global `auth.json`: it travels in `COMPOSER_AUTH` for the deploy only (http-basic), and a token an older deploy left there is removed. Composer 2.4.2 refuses a stored token with a `-` in it ("contains invalid characters"), and one such token made every later composer call on the server fail (exit 34); 2.4.4 and newer accept it.

## 1.0.5
- A database URL whose user or password holds `#`, `/` or `?` (or a single quote) now stops the deploy with exit 56 and says how to fix it (percent-encode it). Before, the script carried on with an empty user and failed later with "Access denied for user ''".

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
