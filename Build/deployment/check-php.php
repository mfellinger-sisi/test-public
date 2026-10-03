<?php

declare(strict_types=1);

/*
 * Composer "pre-install-cmd"/"pre-update-cmd" guard.
 *
 * TYPO3 13 LTS needs PHP 8.2 or newer - already for "composer install",
 * because the TYPO3 composer plugin runs inside the PHP process that started
 * composer. With an older binary composer aborts with a parse error deep
 * inside vendor/, which says nothing about the real cause. Composer runs this
 * script through "@php", so it always sees exactly that binary.
 */

if (PHP_VERSION_ID >= 80200) {
    exit(0);
}

fwrite(STDERR, sprintf(
    "\n  This TYPO3 installation needs PHP 8.2 or newer, composer is running with PHP %s\n"
    . "  (%s).\n\n"
    . "  On the hosting PHP 8.2 is available as \"php8.2\": run composer with it\n"
    . "  (php8.2 \$(command -v composer) install). For the automated deployment set\n"
    . "  the CI variable DEPLOY_PHP_CMD to \"php8.2\".\n\n",
    PHP_VERSION,
    PHP_BINARY
));

exit(1);
