Update Modules Script for Raspberry Pi

This folder contains a script to automatically update MagicMirror modules (git + npm) and optionally restart the pm2 process.

Files
- update_modules.sh — main script. Configure the variables at the top before use.

Usage
1) Copy to the Raspberry Pi, for example into `/home/pi/scripts/` and make executable:

```bash
# on the Pi
mkdir -p ~/scripts
scp update_modules.sh pi@raspberrypi:/home/pi/scripts/
ssh pi@raspberrypi
chmod +x ~/scripts/update_modules.sh
```

2) Edit configuration at the top of `update_modules.sh`:
- `MODULES_DIR` — Pfad zu deinem MagicMirror `modules` Ordner (z. B. `/home/pi/MagicMirror/modules`).
- `PM2_PROCESS_NAME` — Name des pm2-Prozesses (z. B. `MagicMirror`).
- `RESTART_AFTER_UPDATES` — `true` oder `false` (ob pm2 nach Updates neu gestartet werden soll).
- `DRY_RUN` — `true` um zuerst eine Simulation zu fahren (keine Änderungen, kein Reboot).
- `AUTO_DISCARD_LOCAL` — `true` (Standard) verwirft automatisch lokale Änderungen in Git-Repos.
- `RUN_RASPBIAN_UPDATE` — `true` (Standard) führt apt-get full-upgrade nach Modul-Updates aus.
- `AUTO_REBOOT_AFTER_SCRIPT` — `true` (Standard) rebootet den Pi nach Skript-Ende (wird bei DRY_RUN übersprungen).
- `LOG_FILE` — Pfad zur Log-Datei (Standard: `$HOME/update_modules.log`).

3) Dry-run testen:

```bash
# auf dem Pi
DRY_RUN=true ~/scripts/update_modules.sh
# oder: export DRY_RUN=true; ~/scripts/update_modules.sh
```

4) Wenn alles in Ordnung ist, echten Lauf starten:

```bash
~/scripts/update_modules.sh
```

Cron / Timer
Wenn dein Mirror bereits zweimal täglich neu startet und du das Update während der Neustarts ausführen möchtest, plane den Cron-Job so, dass das Update kurz vor dem Restart läuft.

Beispiel crontab (editiere mit `crontab -e`):
# Ausführung täglich um 02:50 und 14:50 — passe Zeiten an deine PM2-Restarts an
50 2 * * * /home/pi/scripts/update_modules.sh >> /home/pi/update_modules.log 2>&1
50 14 * * * /home/pi/scripts/update_modules.sh >> /home/pi/update_modules.log 2>&1

Alternativ: systemd-timer (wenn bevorzugt) — ich kann das für dich erstellen, wenn du möchtest.

Universelle Modul-Update-Strategie
Das Skript funktioniert **automatisch mit allen MagicMirror-Modulen** ohne manuelle Konfiguration:

- **Intelligente npm-Strategie**:
  - Nach Git-Updates mit `package-lock.json` → automatisch `npm ci` für saubere, deterministische Installation
  - Ohne Git-Update oder ohne Lockfile → `npm install` für maximale Flexibilität
  - 3-stufiges Fallback-System bei Fehlern:
    1. `npm ci` (wenn Lockfile vorhanden)
    2. `npm install` (Standard-Fallback)
    3. `npm install --only=production` (letzter Ausweg für Kompatibilität)

- **Automatische Fehlerbehandlung**: Bei unbekannten npm-Befehlen (alte npm-Versionen) probiert das Skript automatisch kompatible Alternativen
- **Git-Update Handling**: Bei `git fetch`/`git pull` Fehlern ("another git process" oder `index.lock`) wartet das Skript automatisch und versucht mehrmals erneut (exponentielles Backoff)
- **Lokale Änderungen**: Werden automatisch verworfen wenn `AUTO_DISCARD_LOCAL=true` (Standard) via `git reset --hard` + `git clean -fdx`

**Modul-spezifische Overrides** (nur für Sonderfälle):
- **MMM-Webuntis**: Verwendet `npm install --only=production` wegen Kompatibilitätsproblemen mit sehr alten npm-Versionen
- **MMM-RTSPStream & MMM-Fuel**: Bei Git-Updates wird `node_modules` vor `npm ci` komplett gelöscht für garantiert saubere Installation (verhindert Stream-/Dependency-Probleme)
- Alle anderen Module nutzen die universelle Strategie automatisch

Du musst **keine** modul-spezifischen Regeln mehr hinzufügen - das Skript passt sich automatisch an jedes Modul an!


Optionales Raspbian-Update (full-upgrade)
---------------------------------
Das Skript kann optional nach den Modul-Updates ein komplettes, nicht-interaktives `apt-get full-upgrade` ausführen (empfohlen, wenn du Systempakete komplett aktuell halten willst). Standardmäßig ist diese Option aktiviert. Konfiguration in `update_modules.sh`:

```
RUN_RASPBIAN_UPDATE=true
MAKE_MODULE_BACKUP=true   # erstellt vorher ein tar.gz Backup des modules-Ordners
AUTO_REBOOT_AFTER_UPGRADE=false
```

Details und Hinweise:
- Das Skript verwendet `DEBIAN_FRONTEND=noninteractive` und `apt-get full-upgrade` mit Dpkg-Optionen, um interaktive Dialoge zu vermeiden.
- Vor dem Upgrade wird (wenn aktiviert) ein komprimiertes Backup deines `modules`-Ordners nach `~/module_backups/` geschrieben.
- `apt-get full-upgrade` ist mächtiger als `upgrade`: es kann Abhängigkeiten anlegen und Pakete entfernen. Daher ist ein Backup und ein kurzes Prüfintervall empfehlenswert.
- Das Skript behandelt apt/dpkg-Locks mit einem Retry/Backoff-Mechanismus.
- Falls ein Reboot erforderlich ist, wird das erkannt; das Skript kann optional automatisch rebooten (siehe `AUTO_REBOOT_AFTER_UPGRADE`). Standardmäßig bleibt das deaktiviert, da du sagtest, dass ein Reboot ohnehin extern erfolgt.

Bevor du ein automatisches full-upgrade in Produktion nutzt, empfehle ich einen Dry‑Run:

```
DRY_RUN=true ~/scripts/update_modules.sh
```



Hinweise und Edge-Cases
- **Lokale Änderungen**: Bei `AUTO_DISCARD_LOCAL=true` (Standard) werden lokale Änderungen automatisch verworfen (`git reset --hard` + `git clean -fdx`). Sonst werden Repositories mit lokalen Änderungen übersprungen.
- **Git Pull**: Das Skript verwendet `git pull --ff-only`, um automatische Merge-Commits zu vermeiden.
- **npm**: Universelle Strategie für alle Module - automatische Wahl zwischen `npm ci` und `npm install` basierend auf Git-Update-Status und Lockfile-Vorhandensein.
- **npm Fallbacks**: Bei Fehlern probiert das Skript automatisch alternative npm-Befehle (ci → install → install --only=production) für maximale Kompatibilität.
- **pm2**: Das Skript prüft und konfiguriert pm2-Autostart, bereinigt fehlerhafte Prozesse und stellt sicher, dass der systemd-Service aktiviert ist.
- **npm Warnungen**: Deprecation-Warnungen bei älteren Modulen (z.B. rimraf, eslint) sind normal und unkritisch für lokale MagicMirror-Installation.
- **Security Vulnerabilities**: Low/High Vulnerabilities in Dev-Dependencies (jsdoc, eslint) sind für lokal laufende Module unkritisch und können ignoriert werden.
- **Neue Module**: Funktionieren automatisch ohne Konfiguration - die universelle Strategie passt sich an jedes Modul an.

pm2 Autostart Setup
Das Skript konfiguriert automatisch pm2 für Autostart beim Systemboot:
- Bereinigt fehlerhafte pm2-Prozesse automatisch
- Speichert die aktuelle pm2-Konfiguration mit `pm2 save`
- Prüft und aktiviert den systemd-Service `pm2-pi.service`
- Zeigt Anweisungen an, falls manuelle Schritte erforderlich sind

Manuelle pm2-Setup-Schritte (falls noch nicht erfolgt):
```bash
# pm2 Autostart konfigurieren
pm2 startup
# Dann den angezeigten sudo-Befehl ausführen, z.B.:
# sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u pi --hp /home/pi

# Aktuelle Prozesse speichern
pm2 save

# Service aktivieren
sudo systemctl enable pm2-pi
sudo systemctl start pm2-pi

# Status prüfen
sudo systemctl status pm2-pi
pm2 list
```

Troubleshooting
- **Module funktionieren nach Update nicht**: 
  - Das Skript versucht automatisch 3 Fallback-Strategien
  - Manuelle Reparatur: `rm -rf node_modules package-lock.json && npm install` im Modul-Ordner
  - Log prüfen: `cat ~/update_modules.log` zeigt welche Strategie verwendet wurde
- **RTSP Stream zeigt nur "loading" nach Update**: 
  - Das Skript löscht jetzt automatisch `node_modules` vor `npm ci` bei Git-Updates von RTSPStream
  - Dies verhindert Dependency-Konflikte und stellt saubere Installation sicher
  - Bei Problemen: Manuell `cd /home/pi/MagicMirror/modules/MMM-RTSPStream && rm -rf node_modules && npm ci`
- **Fuel-Modul zeigt keine Daten nach Update**: 
  - Gleiche Behandlung wie RTSPStream - automatische Bereinigung bei Git-Updates
  - Manuelle Fix: `cd /home/pi/MagicMirror/modules/MMM-Fuel && rm -rf node_modules && npm install`
- **npm-Befehl schlägt fehl**: Skript probiert automatisch Alternativen (ci → install → install --only=production)
- **pm2 startet nicht automatisch**: Prüfe `sudo systemctl status pm2-pi` und ob `pm2 save` ausgeführt wurde
- **npm Deprecation Warnings**: Normal bei älteren Modulen, funktionieren meist trotzdem
- **Security Vulnerabilities**: Bei Dev-Dependencies in lokalen Modulen unkritisch, können ignoriert werden
- **Neues Modul aktualisieren**: Keine Konfiguration nötig - läuft automatisch mit der universellen Strategie
