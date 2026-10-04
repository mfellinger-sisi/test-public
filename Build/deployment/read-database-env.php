<?php

declare(strict_types=1);

/*
 * Prints the database credentials of typo3conf/system/additional.php as shell
 * "export" lines, so that Build/deploy.sh can hand them to "typo3 setup".
 *
 * Why: "typo3 setup" creates the database schema in the database it is told
 * about through TYPO3_DB_* (SQLite if nothing is given) and writes exactly
 * that connection into settings.php. The credentials of the CI deployment in
 * additional.php override settings.php, so every following step (extension
 * setup, content, caches) works on the MySQL database while the schema ended
 * up in SQLite - the deployment aborted. With the real credentials handed to
 * the setup, schema, settings.php and additional.php all point to one database.
 *
 * Usage: eval "$(php Build/deployment/read-database-env.php)"
 * Prints nothing when additional.php is missing or has no usable server
 * connection (the setup then keeps its SQLite default). The password only
 * travels through the environment of the setup process and never appears in a
 * log.
 */

$projectRoot = dirname(__DIR__, 2);
$file = $projectRoot . '/typo3conf/system/additional.php';

if (!is_file($file)) {
    exit(0);
}

$GLOBALS['TYPO3_CONF_VARS'] = [];
require $file;

$connection = $GLOBALS['TYPO3_CONF_VARS']['DB']['Connections']['Default'] ?? [];

if (!is_array($connection)) {
    exit(0);
}

$driver = (string)($connection['driver'] ?? '');
$database = (string)($connection['dbname'] ?? '');
$user = (string)($connection['user'] ?? '');

// SQLite needs no credentials, an incomplete server connection cannot be used.
if ($driver === '' || str_contains($driver, 'sqlite') || $database === '' || $user === '') {
    exit(0);
}

$variables = [
    'TYPO3_DB_DRIVER' => $driver,
    'TYPO3_DB_HOST' => (string)($connection['host'] ?? 'localhost'),
    'TYPO3_DB_PORT' => (string)($connection['port'] ?? 3306),
    'TYPO3_DB_DBNAME' => $database,
    'TYPO3_DB_USERNAME' => $user,
    'TYPO3_DB_PASSWORD' => (string)($connection['password'] ?? ''),
];

foreach ($variables as $name => $value) {
    echo 'export ' . $name . '=' . escapeshellarg($value) . "\n";
}
