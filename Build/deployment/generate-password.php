<?php

declare(strict_types=1);

/*
 * Prints one strong random password. Used by Build/deploy.sh for the initial
 * backend administrator, so that no password ever has to live in the
 * repository. The generated value is stored on the server only.
 */

$alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
$password = '';

for ($i = 0; $i < 24; $i++) {
    $password .= $alphabet[random_int(0, strlen($alphabet) - 1)];
}

// Guarantee the character classes TYPO3's password policy asks for.
echo $password . 'aZ9!' . PHP_EOL;
