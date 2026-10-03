# signundsinn GmbH – TYPO3-Website

TYPO3 13.4 LTS als Composer-Projekt. Dieses Repository enthält die
Grundinstallation: Konfiguration, Site-Konfiguration und die Skripte, die bei
jedem Deployment Datenbank, Erweiterungen und Caches aktualisieren.

## Voraussetzungen

* PHP **8.2** oder neuer (TYPO3 13 LTS). Auf dem Hosting steht PHP 8.2 als
  `php8.2` bereit, `php` ist dort noch 8.1 – Composer deshalb immer mit
  `php8.2 $(command -v composer) …` aufrufen.
* Composer 2
* Datenbank: SQLite (Standard der Erstinstallation) oder MySQL/MariaDB

## Verzeichnis-Layout

Das Hosting liefert das Projektverzeichnis direkt als DocumentRoot aus
(`…/web/<projekt>/`). TYPO3 legt seine Konfiguration daher in `typo3conf/` und
seine Laufzeitdaten in `typo3temp/` ab (nicht in `config/` bzw. `var/`).
`vendor/`, `typo3conf/`, `Build/` und die Dateien des Repositories liegen damit
physisch im Web-Pfad und werden von der `.htaccess` gesperrt – Änderungen an
diesen Regeln bitte immer gegen das Live-Layout prüfen.

Nicht versioniert (wird je Umgebung erzeugt): `vendor/`, `index.php`,
`typo3/`, `_assets/`, `typo3temp/`, `fileadmin/`, `typo3conf/*` außer
`typo3conf/sites/`.

## Deployment

Die CI führt auf dem Server nach `git pull` aus:

1. `composer install --prefer-dist`
2. `composer run-script typo3-deployment-scripts` → `Build/deploy.sh`

`Build/deploy.sh` ist idempotent:

* erster Lauf: TYPO3 installieren (`typo3 setup`, Datenbank, Backend-Admin),
* jeder Lauf: Projekt-Settings anwenden (`Build/deployment/apply-settings.php`),
  Schema/Erweiterungen aktualisieren (`extension:setup`), Upgrade-Wizards,
  Grunddaten sicherstellen (`Build/deployment/bootstrap-content.php`),
  Sprachpakete und Caches.

Das Passwort des initial angelegten Backend-Benutzers `admin` steht auf dem
Server in `typo3temp/var/initial-admin-password.txt` (nicht über das Web
erreichbar). Alternativ: `php8.2 vendor/bin/typo3 backend:resetpassword`.

### Datenbank

Ohne Zugangsdaten installiert sich TYPO3 mit SQLite
(`typo3conf/cms-*.sqlite`). Für MySQL/MariaDB genügt die CI-Variable
`DEPLOY_DATABASE_URL` (`mysql://user:pass@host:3306/datenbank`): die Pipeline
schreibt daraus `config/system/additional.php`, `Build/deploy.sh` übernimmt die
Datei nach `typo3conf/system/additional.php`. Bestehende Inhalte müssen dabei
migriert werden.

## Application Context und Site-Konfiguration

Web-Requests erhalten den Kontext über die `.htaccess`: Pfade unter
`/github-public-staging/` laufen als `Development/staging`, alles andere als
`Production`. `typo3conf/sites/main/config.yaml` wählt daran die Basis-URL
(`baseVariants`). Kommt eine weitere Umgebung hinzu, beide Stellen ergänzen.

## Frontend

Das Frontend rendert vorläufig über `Build/TypoScript/setup.typoscript`
(Seitentitel, Inhaltselemente der Hauptspalte, Adresszeile). Layout und
Templates ziehen mit dem Sitepackage in eine eigene Extension um; danach kann
die Datei entfallen. Externe Ressourcen (Fonts, CDN-Bibliotheken, Tracker)
werden nicht eingebunden – alles kommt von der eigenen Domain.
