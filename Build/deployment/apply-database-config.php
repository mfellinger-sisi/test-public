<?php

declare(strict_types=1);

/*
 * Keeps the database configuration of this installation usable - on every
 * deployment, before any TYPO3 command runs.
 *
 * Three things happen here:
 *
 * 1. The CI deployment writes the credentials of the environment variable
 *    DEPLOY_DATABASE_URL into config/system/additional.php (composer layout).
 *    This installation has its document root in the project root, so TYPO3
 *    reads its configuration from typo3conf/ - the file is taken over there,
 *    but only when it really contains usable credentials.
 *
 * 2. Earlier deployments wrote that file even when no database URL was
 *    configured: with the mysqli driver and an empty host, user and database
 *    name. Such a copy overrides the working database of the installation and
 *    breaks every deployment step after the setup ("Access denied for user
 *    ''@'localhost'"), so it is removed again.
 *
 * 3. If the installation is left without a usable database configuration at
 *    all (an installation that was interrupted exactly that way), a fresh
 *    SQLite database is configured. The following deployment steps
 *    (extension:setup, bootstrap-content.php) then complete the installation.
 *    A configuration with complete credentials is never touched - a database
 *    server that is temporarily unreachable must not silently switch the
 *    installation to another database.
 */

$projectRoot = dirname(__DIR__, 2);
$source = $projectRoot . '/config/system/additional.php';
$target = $projectRoot . '/typo3conf/system/additional.php';
$settingsFile = $projectRoot . '/typo3conf/system/settings.php';

/**
 * Reads the "Default" database connection out of one of the additional.php
 * files without booting TYPO3.
 *
 * @return array<string, mixed>
 */
$readAdditional = static function (string $file): array {
    if (!is_file($file)) {
        return [];
    }

    unset($GLOBALS['TYPO3_CONF_VARS']['DB']);
    $GLOBALS['TYPO3_CONF_VARS'] = $GLOBALS['TYPO3_CONF_VARS'] ?? [];
    require $file;

    $connection = $GLOBALS['TYPO3_CONF_VARS']['DB']['Connections']['Default'] ?? [];
    unset($GLOBALS['TYPO3_CONF_VARS']['DB']);

    return is_array($connection) ? $connection : [];
};

/**
 * A connection is usable when it can actually be opened: SQLite needs a file
 * path, every server based driver needs at least a database name and a user.
 */
$isUsable = static function (array $connection): bool {
    $driver = (string)($connection['driver'] ?? '');

    if ($driver === '') {
        return false;
    }

    if (str_contains($driver, 'sqlite')) {
        return ($connection['path'] ?? '') !== '';
    }

    return ($connection['dbname'] ?? '') !== '' && ($connection['user'] ?? '') !== '';
};

// ---------------------------------------------------------------------------
// 1. Credentials of the CI deployment
// ---------------------------------------------------------------------------
$sourceConnection = $readAdditional($source);

if ($sourceConnection !== [] && $isUsable($sourceConnection)) {
    if (!copy($source, $target)) {
        fwrite(STDERR, "[database] could not copy $source to $target\n");
        exit(1);
    }

    chmod($target, 0600);
    fwrite(STDOUT, sprintf(
        "[database] using the %s database of the CI deployment\n",
        (string)$sourceConnection['driver']
    ));
    exit(0);
}

fwrite(STDOUT, $sourceConnection === []
    ? "[database] no database configuration from the CI deployment\n"
    : "[database] the CI deployment provides no usable credentials (DEPLOY_DATABASE_URL is not set)"
        . " - keeping the database of the installation\n");

// ---------------------------------------------------------------------------
// 2. Unusable copy of an earlier deployment
// ---------------------------------------------------------------------------
if (is_file($target) && !$isUsable($readAdditional($target))) {
    if (!unlink($target)) {
        fwrite(STDERR, "[database] could not remove the unusable $target\n");
        exit(1);
    }

    fwrite(STDOUT, "[database] removed the unusable typo3conf/system/additional.php\n");
}

// ---------------------------------------------------------------------------
// 3. Installation without a usable database configuration
// ---------------------------------------------------------------------------
if (!is_file($settingsFile)) {
    // First deployment: "typo3 setup" writes settings.php, see Build/deploy.sh.
    exit(0);
}

$settings = require $settingsFile;

if (!is_array($settings)) {
    fwrite(STDERR, "[database] $settingsFile does not return an array\n");
    exit(1);
}

$settingsConnection = $settings['DB']['Connections']['Default'] ?? [];
$settingsConnection = is_array($settingsConnection) ? $settingsConnection : [];

if ($isUsable($settingsConnection)) {
    exit(0);
}

$databaseFile = $projectRoot . '/typo3conf/cms-' . bin2hex(random_bytes(4)) . '.sqlite';
$settings['DB']['Connections']['Default'] = [
    'charset' => 'utf8',
    'driver' => 'pdo_sqlite',
    'path' => $databaseFile,
];

$export = "<?php\n\nreturn " . var_export($settings, true) . ";\n";

if (file_put_contents($settingsFile, $export) === false) {
    fwrite(STDERR, "[database] could not write $settingsFile\n");
    exit(1);
}

fwrite(STDOUT, "[database] the installation had no usable database configuration - a new SQLite database"
    . " was configured, the following deployment steps create schema and start page\n");

exit(0);
