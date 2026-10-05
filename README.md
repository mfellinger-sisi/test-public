# signundsinn GmbH – TYPO3-Website

TYPO3 13.4 LTS als Composer-Projekt. Dieses Repository enthält die
Grundinstallation: Konfiguration, Site-Konfiguration und die Skripte, die bei
jedem Deployment Datenbank, Erweiterungen und Caches aktualisieren.

## Voraussetzungen

* PHP **8.2** oder neuer (TYPO3 13 LTS). Das Deployment läuft mit der PHP-
  Version der Umgebung (Staging: 8.2, `/usr/local/php/8.2/php`);
  `Build/deploy.sh` nutzt genau diese (`php` im PATH des Deployments) und
  sucht nur dann eine neuere, wenn sie älter als 8.2 ist. `TYPO3_PHP_BINARY`
  überschreibt die Suche. Beim Arbeiten in der Login-Shell ist `php`
  möglicherweise eine andere Version – Composer dort mit
  `php8.2 $(command -v composer) …` aufrufen.
* Composer 2
* Datenbank: SQLite (Standard der Erstinstallation) oder MySQL/MariaDB

## Verzeichnis-Layout

Standard-Layout von TYPO3 für Composer-Projekte (`extra.typo3/cms.web-dir` =
`public`). Der Webserver liefert **nur** `public/` aus – auf Staging per
Apache-`Alias /github-public-staging <Projekt>/public`. Alles andere liegt
außerhalb des Web-Pfads und ist nicht abrufbar:

| Ordner | Inhalt |
| --- | --- |
| `public/` | Web-Root: `.htaccess` (versioniert), `index.php`, `typo3/`, `_assets/`, `fileadmin/`, `typo3temp/` (erzeugt) |
| `config/sites/` | Site-Konfiguration (versioniert): `main/config.yaml` und das Projekt-TypoScript `main/setup.typoscript` |
| `config/system/` | `settings.php` (von TYPO3 erzeugt) und `additional.php` (von der CI aus `DEPLOY_DATABASE_URL`), nicht versioniert |
| `var/` | Laufzeitdaten: Logs, Cache, SQLite-Datenbank, Erstpasswort – nicht versioniert |
| `Build/` | Deployment-Skripte |

Nicht versioniert (wird je Umgebung erzeugt): `vendor/`, alles in `public/`
außer `.htaccess`, `var/`, `config/system/`.

Eine Installation aus dem früheren Layout (Projektwurzel als Web-Root,
Konfiguration in `typo3conf/`) übernimmt `Build/deploy.sh` beim nächsten
Deployment automatisch (`Build/deployment/migrate-legacy-layout.php`):
`settings.php` und Datenbank bleiben erhalten, `fileadmin/` zieht nach
`public/fileadmin/` um, die alten Verzeichnisse werden entfernt.

## Umgebungen

Es gibt genau **eine** Testumgebung (Staging):
<http://ai-crew-test.dev.signundsinn.de/github-public-staging/> (Branch
`staging`, Server `dev2`, PHP 8.2, Zugriff über die bekannte Zugangsabfrage).

Die frühere Testumgebung `ai-crew-test.eywora.com/github-public-staging`
(Webspace `web105` auf `int.signundsinn.de`) ist seit Oktober 2026
abgeschaltet und liefert nur noch eine Hinweisseite – siehe
`Build/legacy-staging/README.md`. Dort bitte nicht mehr testen.

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
Server in `var/initial-admin-password.txt` (nicht über das Web
erreichbar). Alternativ: `php8.2 vendor/bin/typo3 backend:resetpassword`.

### Datenbank

Ohne Zugangsdaten installiert sich TYPO3 mit SQLite
(`var/sqlite/cms-*.sqlite`). Für MySQL/MariaDB genügt die CI-Variable
`DEPLOY_DATABASE_URL` (`mysql://user:pass@host:3306/datenbank`): die Pipeline
schreibt daraus `config/system/additional.php`, das TYPO3 direkt liest.
Bestehende Inhalte müssen bei einem Wechsel der Datenbank migriert werden.

Bei der Erstinstallation liest `Build/deployment/read-database-env.php` die
Zugangsdaten aus `config/system/additional.php`, und `Build/deploy.sh`
übergibt sie als `TYPO3_DB_*` an `typo3 setup`. Ohne das würde das Setup das
Schema in SQLite anlegen, während alle weiteren Schritte gegen MySQL arbeiten
(„Table 'be_users' doesn't exist“ bei `extension:setup`). Die Zugangsdaten
landen dabei nur in der Umgebung des Setup-Prozesses, nie im Log.

Wichtig: Deployments haben `config/system/additional.php` auch ohne gesetztes
`DEPLOY_DATABASE_URL` geschrieben – dann mit leerem Benutzer und leerem
Datenbanknamen. Diese Datei überschreibt die funktionierende Verbindung, und
das Deployment bricht nach dem Setup mit „Access denied for user
''@'localhost'“ ab. `Build/deployment/apply-database-config.php` hält das
gerade:

1. Eine unbrauchbare `config/system/additional.php` (ohne Zugangsdaten) wird
   entfernt, eine mit nutzbaren Zugangsdaten bleibt unverändert.
2. Hat die Installation danach gar keine nutzbare Datenbank-Konfiguration
   mehr, wird eine neue SQLite-Datenbank eingetragen. Eine Konfiguration mit
   vollständigen Zugangsdaten bleibt immer unangetastet.

`Build/deployment/check-database.php` prüft anschließend die Verbindung:
ist die Datenbank erreichbar, aber leer (abgebrochene Erstinstallation), führt
`Build/deploy.sh` die Installation zu Ende; ist sie nicht erreichbar, bricht
das Deployment mit klarer Meldung ab, statt eine 500-Seite auszuliefern.

## Application Context und Site-Konfiguration

Web-Requests erhalten den Kontext über die `public/.htaccess`: Pfade unter
`/github-public-staging/` laufen als `Development/staging`, Pfade unter
`/github-public-live/` als `Production/Live`, alles andere als `Production`. `config/sites/main/config.yaml` wählt daran die Basis-URL
(`baseVariants`: `/github-public-staging/` bzw. `/github-public-live/`). Kommt eine weitere Umgebung hinzu, beide Stellen ergänzen.

Die Basis-URLs sind absichtlich **relativ** (`/`,
`/github-public-staging/` bzw. `/github-public-live/`) und enthalten keine Domain: TYPO3 findet seine Site
damit unter jedem Hostnamen und sowohl über `http` als auch über `https`. Eine
absolute Basis-URL führt bei jedem Domainwechsel zu „No site configuration
found“. Aus demselben Grund wird `reverseProxySSL` nicht gesetzt – das Schema
kommt aus dem Request bzw. aus `X-Forwarded-Proto`.

## Frontend

Das Frontend rendert vorläufig über das Site-TypoScript
`config/sites/main/setup.typoscript` (Seitentitel, Inhaltselemente der
Hauptspalte, Adresszeile); TYPO3 lädt es automatisch neben `config.yaml`. Layout und
Templates ziehen mit dem Sitepackage in eine eigene Extension um; danach kann
die Datei entfallen. Externe Ressourcen (Fonts, CDN-Bibliotheken, Tracker)
werden nicht eingebunden – alles kommt von der eigenen Domain.
