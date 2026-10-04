<?php

declare(strict_types=1);

/*
 * Takes over the database configuration of the CI deployment.
 *
 * The CI deployment writes the credentials of the environment variable
 * DEPLOY_DATABASE_URL into config/system/additional.php (composer layout).
 * This installation has its document root in the project root, so TYPO3 reads
 * its configuration from typo3conf/ - the file has to be copied there.
 *
 * Important: the CI writes that file even when no database URL is configured.
 * It then contains the mysqli driver with an empty host, user and database
 * name, which would override the working database of the installation and
 * break every deployment step after the setup ("Access denied for user ''").
 * Therefore the file is only taken over when it really contains usable
 * credentials, and an unusable copy of an earlier deployment is removed again.
 */

$projectRoot = dirname(__DIR__, 2);
$source = $projectRoot . '/config/system/additional.php';
$target = $projectRoot . '/typo3conf/system/additional.php';

/**
 * Reads the "Default" database connection out of one of the additional.php
 * files without booting TYPO3.
 *
 * @return array<string, mixed>
 */
$readConnection = static function (string $file): array {
    if (!is_file($file)) {
        return [];
    }

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

$sourceConnection = $readConnection($source);

if ($sourceConnection === []) {
    fwrite(STDOUT, "[database] no database configuration from the CI deployment\n");
    exit(0);
}

if ($isUsable($sourceConnection)) {
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

fwrite(
    STDOUT,
    "[database] the CI deployment provides no database credentials (DEPLOY_DATABASE_URL is not set)"
    . " - keeping the database of the installation\n"
);

// Remove an unusable copy of an earlier deployment, otherwise it keeps
// overriding the working connection of typo3conf/system/settings.php.
if (is_file($target) && !$isUsable($readConnection($target))) {
    if (!unlink($target)) {
        fwrite(STDERR, "[database] could not remove the unusable $target\n");
        exit(1);
    }

    fwrite(STDOUT, "[database] removed the unusable typo3conf/system/additional.php\n");
}

exit(0);
