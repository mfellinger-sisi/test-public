<?php

declare(strict_types=1);

use TYPO3\CMS\Core\Core\Bootstrap;
use TYPO3\CMS\Core\Core\SystemEnvironmentBuilder;
use TYPO3\CMS\Core\Crypto\PasswordHashing\PasswordHashFactory;
use TYPO3\CMS\Core\Database\ConnectionPool;
use TYPO3\CMS\Core\Utility\GeneralUtility;

/*
 * Creates the records a fresh database needs so that the site answers right
 * after the first deployment:
 *
 *  - the root page (uid 1) the site configuration in
 *    config/sites/main/config.yaml points to,
 *  - the root TypoScript template record (the TypoScript itself comes from
 *    config/sites/main/setup.typoscript, the site configuration),
 *  - a backend administrator, if the database contains none.
 *
 * Every step is skipped when the record already exists, so the script can run
 * on every deployment. Editorial content is never touched.
 */

$projectRoot = dirname(__DIR__, 2);
$classLoader = require $projectRoot . '/vendor/autoload.php';

SystemEnvironmentBuilder::run(0, SystemEnvironmentBuilder::REQUESTTYPE_CLI);
Bootstrap::init($classLoader, true);

$connectionPool = GeneralUtility::makeInstance(ConnectionPool::class);
$now = time();

$countRows = static function (string $table) use ($connectionPool): int {
    $queryBuilder = $connectionPool->getQueryBuilderForTable($table);
    $queryBuilder->getRestrictions()->removeAll();

    return (int)$queryBuilder
        ->count('uid')
        ->from($table)
        ->executeQuery()
        ->fetchOne();
};

// ---------------------------------------------------------------------------
// Root page
// ---------------------------------------------------------------------------
if ($countRows('pages') === 0) {
    $connectionPool->getConnectionForTable('pages')->insert('pages', [
        'uid' => 1,
        'pid' => 0,
        'title' => 'Startseite',
        'slug' => '/',
        'doktype' => 1,
        'is_siteroot' => 1,
        'hidden' => 0,
        'deleted' => 0,
        'sorting' => 256,
        'tstamp' => $now,
        'crdate' => $now,
        'perms_userid' => 1,
        'perms_groupid' => 1,
        'perms_user' => 31,
        'perms_group' => 31,
        'perms_everybody' => 0,
    ]);
    echo "[content] root page created\n";
} else {
    echo "[content] page tree already exists\n";
}

// ---------------------------------------------------------------------------
// Root TypoScript template
// ---------------------------------------------------------------------------
if ($countRows('sys_template') === 0) {
    $connectionPool->getConnectionForTable('sys_template')->insert('sys_template', [
        'pid' => 1,
        'title' => 'Website (signundsinn)',
        'root' => 1,
        // 0: the TypoScript of the site sets (fluid_styled_content, seo, ...)
        // stays included - it provides the rendering of the content elements.
        'clear' => 0,
        'constants' => '',
        'config' => '',
        'hidden' => 0,
        'deleted' => 0,
        'sorting' => 256,
        'tstamp' => $now,
        'crdate' => $now,
    ]);
    echo "[content] root TypoScript template created\n";
} else {
    echo "[content] TypoScript template already exists\n";

    // Installations from before the composer layout imported the TypoScript
    // from Build/TypoScript/, which is no longer reachable that way. It now
    // comes from the site configuration, so the obsolete import is removed.
    $legacyImport = "@import 'Build/TypoScript/setup.typoscript'\n";
    $connectionPool->getConnectionForTable('sys_template')->update(
        'sys_template',
        ['config' => '', 'tstamp' => $now],
        ['config' => $legacyImport]
    );
}

// ---------------------------------------------------------------------------
// Backend administrator
// ---------------------------------------------------------------------------
if ($countRows('be_users') === 0) {
    $password = trim((string)shell_exec(
        escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(__DIR__ . '/generate-password.php')
    ));

    if ($password === '') {
        fwrite(STDERR, "[content] could not generate a password for the admin user\n");
        exit(1);
    }

    $hashedPassword = GeneralUtility::makeInstance(PasswordHashFactory::class)
        ->getDefaultHashInstance('BE')
        ->getHashedPassword($password);

    $connectionPool->getConnectionForTable('be_users')->insert('be_users', [
        'username' => 'admin',
        'password' => $hashedPassword,
        'email' => 'kunde@example.com',
        'realName' => 'Administrator',
        'admin' => 1,
        'disable' => 0,
        'deleted' => 0,
        'tstamp' => $now,
        'crdate' => $now,
    ]);

    $passwordFile = $projectRoot . '/var/initial-admin-password.txt';
    $previousUmask = umask(0077);
    file_put_contents($passwordFile, $password . PHP_EOL);
    umask($previousUmask);

    echo "[content] backend administrator created, password written to var/initial-admin-password.txt\n";
} else {
    echo "[content] backend user already exists\n";
}
