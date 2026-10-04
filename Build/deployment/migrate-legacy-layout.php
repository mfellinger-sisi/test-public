<?php

declare(strict_types=1);

/*
 * One-time migration of an installation that was set up in the earlier layout
 * (project root as document root, configuration in typo3conf/system/) to the
 * standard composer layout (document root public/, configuration in
 * config/system/, runtime data in var/).
 *
 * The existing settings.php is taken over, so the encryption key, the install
 * tool password and - above all - the database stay as they are. A SQLite
 * database below typo3conf/ moves to var/sqlite/. Build/deploy.sh removes the
 * rest of the old layout afterwards.
 *
 * Does nothing when typo3conf/system/settings.php does not exist or when
 * config/system/settings.php exists already, so it is safe on every run.
 */

$projectRoot = dirname(__DIR__, 2);
$legacySettings = $projectRoot . '/typo3conf/system/settings.php';
$settingsFile = $projectRoot . '/config/system/settings.php';

if (!is_file($legacySettings) || is_file($settingsFile)) {
    exit(0);
}

$settings = require $legacySettings;

if (!is_array($settings)) {
    fwrite(STDERR, "[migrate] $legacySettings does not return an array\n");
    exit(1);
}

$connection = $settings['DB']['Connections']['Default'] ?? [];
$sqliteFile = is_array($connection) && str_contains((string)($connection['driver'] ?? ''), 'sqlite')
    ? (string)($connection['path'] ?? '')
    : '';

if ($sqliteFile !== '' && str_starts_with($sqliteFile, $projectRoot . '/typo3conf/')) {
    $targetDirectory = $projectRoot . '/var/sqlite';

    if (!is_dir($targetDirectory) && !mkdir($targetDirectory, 0775, true) && !is_dir($targetDirectory)) {
        fwrite(STDERR, "[migrate] could not create $targetDirectory\n");
        exit(1);
    }

    $target = $targetDirectory . '/' . basename($sqliteFile);

    if (is_file($sqliteFile) && !copy($sqliteFile, $target)) {
        fwrite(STDERR, "[migrate] could not copy the SQLite database to $target\n");
        exit(1);
    }

    $settings['DB']['Connections']['Default']['path'] = $target;
    fwrite(STDOUT, "[migrate] SQLite database moved to var/sqlite/\n");
}

if (!is_dir(dirname($settingsFile)) && !mkdir(dirname($settingsFile), 0775, true) && !is_dir(dirname($settingsFile))) {
    fwrite(STDERR, "[migrate] could not create config/system\n");
    exit(1);
}

$export = "<?php\n\nreturn " . var_export($settings, true) . ";\n";

if (file_put_contents($settingsFile, $export) === false) {
    fwrite(STDERR, "[migrate] could not write $settingsFile\n");
    exit(1);
}

chmod($settingsFile, 0600);
fwrite(STDOUT, "[migrate] settings.php taken over from typo3conf/system/ to config/system/\n");
