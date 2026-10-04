<?php

declare(strict_types=1);

use Doctrine\DBAL\DriverManager;

/*
 * Checks the database of the installation before the deployment changes
 * schema, extensions and content. Without this check a wrong or incomplete
 * database configuration only shows up as a 500 error in the browser.
 *
 * TYPO3 is deliberately not booted here: the check has to work on an
 * installation whose configuration is still incomplete. The connection is
 * built straight from config/system/settings.php (plus additional.php, in
 * the same order TYPO3 reads them).
 *
 * Exit codes (evaluated by Build/deploy.sh):
 *   0  connection works and the schema is there
 *   10 connection works, but the database is still empty
 *   20 the configured database cannot be reached
 */

const DATABASE_OK = 0;
const DATABASE_EMPTY = 10;
const DATABASE_UNREACHABLE = 20;

$projectRoot = dirname(__DIR__, 2);

require $projectRoot . '/vendor/autoload.php';

$settingsFile = $projectRoot . '/config/system/settings.php';
$additionalFile = $projectRoot . '/config/system/additional.php';

$settings = is_file($settingsFile) ? require $settingsFile : [];
$parameters = [];

if (is_array($settings)) {
    $parameters = $settings['DB']['Connections']['Default'] ?? [];
    $parameters = is_array($parameters) ? $parameters : [];
}

if (is_file($additionalFile)) {
    $GLOBALS['TYPO3_CONF_VARS']['DB']['Connections']['Default'] = $parameters;
    require $additionalFile;
    $fromAdditional = $GLOBALS['TYPO3_CONF_VARS']['DB']['Connections']['Default'] ?? [];
    $parameters = is_array($fromAdditional) ? $fromAdditional : $parameters;
}

// Keys TYPO3 adds for itself and Doctrine does not need for the connection.
unset($parameters['wrapperClass'], $parameters['tableoptions'], $parameters['initCommands']);

if (($parameters['driver'] ?? '') === '') {
    fwrite(STDERR, "[database] no database configuration found in config/system/\n");
    exit(DATABASE_UNREACHABLE);
}

// SQLite: opening the connection would create the file, which would leave an
// empty database behind on every check.
if (str_contains((string)$parameters['driver'], 'sqlite') && !is_file((string)($parameters['path'] ?? ''))) {
    fwrite(STDOUT, "[database] the SQLite database of the configuration does not exist yet\n");
    exit(DATABASE_EMPTY);
}

try {
    $connection = DriverManager::getConnection($parameters);
    $connection->executeQuery('SELECT 1');
} catch (Throwable $exception) {
    fwrite(STDERR, '[database] the configured database cannot be reached: ' . $exception->getMessage() . "\n");
    exit(DATABASE_UNREACHABLE);
}

try {
    $hasSchema = $connection->createSchemaManager()->tablesExist(['be_users', 'pages']);
} catch (Throwable $exception) {
    fwrite(STDERR, '[database] the tables of the database cannot be read: ' . $exception->getMessage() . "\n");
    exit(DATABASE_UNREACHABLE);
}

if (!$hasSchema) {
    fwrite(STDOUT, "[database] the database is reachable, but still without tables\n");
    exit(DATABASE_EMPTY);
}

fwrite(STDOUT, sprintf(
    "[database] %s database reachable, schema present\n",
    (string)$parameters['driver']
));

exit(DATABASE_OK);
