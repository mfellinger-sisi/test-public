# Abgeschaltete Testumgebung auf web105 (ai-crew-test.eywora.com)

Bis Oktober 2026 lag eine frühere Testumgebung des Projekts auf dem Webspace
`web105` des Servers `int.signundsinn.de` (Domain `ai-crew-test.eywora.com`,
Pfad `web/github-public-staging`). Der Stand dort war veraltet (Pipeline
`.aicrew 1.0.0`, Projektstand von Anfang Oktober 2026) und wurde seit dem
Umzug auf `dev2` nicht mehr beliefert – Tests an dieser Adresse lieferten
deshalb falsche Ergebnisse.

## Was geschehen ist (Ticket #9)

1. Der alte Projektstand wurde aus `web/github-public-staging/` entfernt
   (inklusive `.git`, `.github`, `.aicrew` und `.env.local`; damit ist auch
   das dort gespeicherte, abgelaufene Deployment-Zugangstoken verschwunden).
   Vorher wurde ein vollständiges Archiv außerhalb des Web-Pfads abgelegt:
   `~/private/github-public-staging-abgeschaltet-2026-10-04.tar.gz`.
2. Statt des Projekts liegen dort jetzt die beiden Dateien aus diesem
   Verzeichnis: `index.html` (Hinweisseite, `noindex`, Verweis auf die
   aktuelle Umgebung) und `.htaccess` (kein Directory-Listing, kein PHP,
   `X-Robots-Tag: noindex`, alle Unterpfade beantworten die Hinweisseite).
3. Im Projekt wurde die letzte Referenz auf die alte Domain entfernt
   (`trustedHostsPattern` in `Build/deployment/apply-settings.php`).

Die aktuelle Testumgebung ist
<http://ai-crew-test.dev.signundsinn.de/github-public-staging/>.

## Dateien erneut einspielen

Die Dateien sind nicht Teil eines Deployments (`Build/` wird von der
`.htaccess` des Projekts vom Web ausgeschlossen). Sie werden bei Bedarf
manuell kopiert:

```sh
scp Build/legacy-staging/index.html Build/legacy-staging/.htaccess \
    <user>@int.signundsinn.de:web/github-public-staging/
```

## Vollständige Abschaltung durch den Hoster

Die Hinweisseite ist die maximal mögliche Maßnahme mit dem vorhandenen
Webspace-Zugang (kein ISPConfig-Admin). Damit die Adresse ganz verschwindet,
sind Server-Administrator-Rechte nötig:

1. In ISPConfig unter *Sites* die Domain/das Alias `ai-crew-test.eywora.com`
   des Webspace `web105` löschen (oder die Website deaktivieren, falls der
   Webspace nur für dieses Projekt genutzt wurde – im Verzeichnis `web/`
   liegen daneben noch `deploy_staging/` und `deploy_live/` anderer Tests).
2. Den DNS-Eintrag `ai-crew-test.eywora.com` (A `159.69.65.94`) entfernen.
3. Danach prüfen: `curl -I http://ai-crew-test.eywora.com/github-public-staging/`
   darf keine Antwort dieses Webspace mehr liefern.
