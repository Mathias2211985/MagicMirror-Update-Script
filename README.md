Update Modules Script for Raspberry Pi

This folder contains a script to automatically update MagicMirror modules (git + npm) and optionally restart the pm2 process.

**🆕 Neue Features (Januar 2026)**
- ✓ **E-Mail-Benachrichtigungen**: Optional bei Fehlern oder erfolgreichen Updates
- ✓ **Log-Rotation**: Automatische Rotation wenn Log zu groß wird (Standard: 5MB)
- ✓ **Externe Konfiguration**: Config-Datei statt Skript editieren
- ✓ **Healthcheck vor Reboot**: Prüft ob MagicMirror läuft bevor Neustart
- ✓ **Lockfile**: Verhindert parallele Ausführungen
- ✓ **Backup-Cleanup**: Alte Backups werden automatisch gelöscht (behält 5)

**🆕 Cron-Optimierungen & Update-Zuverlässigkeit (Januar 2026)**
- ✓ **Garantierte Module-Updates**: Verbesserte git pull Logik erkennt verfügbare Updates zuverlässig
- ✓ **Fallback-Mechanismus**: Wenn `git pull` versagt, wird automatisch `git reset --hard origin/branch` verwendet
- ✓ **Update-Statistiken**: Zeigt am Ende Zusammenfassung (verarbeitet/aktualisiert/fehlgeschlagen)
- ✓ **TMPDIR Fix**: Setzt TMPDIR automatisch für nvm-Kompatibilität
- ✓ **Node.js v22 Standard**: Verwendet v22 LTS statt v24 für bessere ARM-Kompatibilität
- ✓ **Architektur-Erkennung**: Erkennt automatisch armv7l/armhf und wählt kompatible Node.js Version
- ✓ **Robustere Ausführung**: set -u statt pipefail (einzelne Fehler stoppen nicht das Skript)
- ✓ **PATH für Cron-Jobs**: node/npm/git werden automatisch gefunden
- ✓ **nvm-Unterstützung**: Automatisches Laden in Cron-Umgebung
- ✓ **Intelligenter Reboot**: Nur wenn Updates installiert wurden (nicht bei jedem Lauf)
- ✓ **Besseres Fehler-Handling**: Modul-Fehler werden geloggt, Skript läuft weiter
- ✓ **Subshell-Isolation**: Jedes Modul läuft isoliert vom Hauptskript (set +e)

**🆕 Verbesserte RTSPStream-Unterstützung (Dezember 2024)**
- ✓ Erweiterte ffmpeg-Prozess-Erkennung (mehrere Muster)
- ✓ Doppelte Überprüfung und Beendigung von Zombie-Prozessen
- ✓ Verbesserte npm-Cache-Bereinigung (inkl. /tmp/npm-*)
- ✓ Zusätzliche Dependency-Checks (url, fs, path)
- ✓ Erweiterte ffmpeg-Diagnose (PATH, Berechtigungen)
- ✓ Fallback npm install --force bei Problemen
- ✓ Automatische RTSPStream-Reparatur integriert im Hauptskript

Files
- `update_modules.sh` — Hauptskript. Konfiguration anpassen vor Verwendung.
- `config.example.sh` — Beispiel-Konfigurationsdatei (kopieren und anpassen).

Installation
1) Kopiere auf den Raspberry Pi, z.B. nach `/home/pi/scripts/`:

```bash
# auf dem Pi
mkdir -p ~/scripts
scp update_modules.sh config.example.sh pi@raspberrypi:/home/pi/scripts/
ssh pi@raspberrypi
chmod +x ~/scripts/update_modules.sh
```

2) **Option A**: Externe Konfigurationsdatei verwenden (empfohlen):

```bash
# Konfigurationsverzeichnis erstellen
mkdir -p ~/.config/magicmirror-update

# Beispielkonfiguration kopieren und anpassen
cp ~/scripts/config.example.sh ~/.config/magicmirror-update/config.sh
nano ~/.config/magicmirror-update/config.sh
```

2) **Option B**: Variablen direkt im Skript anpassen:
- `MAGICMIRROR_DIR` — Pfad zum MagicMirror-Hauptverzeichnis (z. B. `/home/pi/MagicMirror`).
- `MODULES_DIR` — Pfad zu deinem MagicMirror `modules` Ordner (z. B. `/home/pi/MagicMirror/modules`).
- `UPDATE_MAGICMIRROR_CORE` — `true` (Standard) aktualisiert MagicMirror Core vor den Modulen via `git pull && node --run install-mm`.
- `PM2_PROCESS_NAME` — Name des pm2-Prozesses (z. B. `MagicMirror`).
- `RESTART_AFTER_UPDATES` — `true` oder `false` (ob der Pi nach Updates neu gestartet werden soll).
- `DRY_RUN` — `true` um zuerst eine Simulation zu fahren (keine Änderungen, kein Reboot).
- `AUTO_DISCARD_LOCAL` — `true` (Standard) verwirft automatisch lokale Änderungen in Git-Repos.
- `RUN_RASPBIAN_UPDATE` — `true` (Standard) führt `apt-get update` und `apt-get full-upgrade` nach Modul-Updates aus.
- `AUTO_REBOOT_AFTER_SCRIPT` — `false` (Standard) rebootet **nicht** nach jedem Lauf (nur bei Updates).
- `REBOOT_ONLY_ON_UPDATES` — `true` (Standard) rebootet **nur** wenn Updates installiert wurden.
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

E-Mail-Benachrichtigungen einrichten
------------------------------------
Das Skript kann E-Mails bei Fehlern oder erfolgreichen Updates senden.

**Voraussetzung**: Ein Mail-Tool muss installiert und konfiguriert sein:
- `msmtp` (empfohlen für Gmail/SMTP)
- `ssmtp`
- `mail` (mailutils)
- `sendmail`

**Beispiel msmtp-Konfiguration** (`~/.msmtprc`):
```
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account        gmail
host           smtp.gmail.com
port           587
from           deine-email@gmail.com
user           deine-email@gmail.com
password       dein-app-passwort

account default : gmail
```

**E-Mail in Config aktivieren**:
```bash
EMAIL_ENABLED=true
EMAIL_RECIPIENT="deine-email@example.com"
EMAIL_ON_ERROR=true      # Bei Fehlern benachrichtigen
EMAIL_ON_SUCCESS=false   # Bei Erfolg benachrichtigen (optional)
```

Healthcheck
-----------
Vor einem Reboot kann das Skript prüfen, ob MagicMirror korrekt startet:

```bash
HEALTHCHECK_BEFORE_REBOOT=true
HEALTHCHECK_TIMEOUT=30
HEALTHCHECK_URL="http://localhost:8080"
```

Das Skript:
1. Startet MagicMirror via pm2 neu
2. Wartet bis zu 30 Sekunden auf den Start
3. Prüft optional ob die Web-Oberfläche erreichbar ist
4. Sendet E-Mail bei Problemen (wenn aktiviert)

Cron / Timer
Das Skript kann automatisch per Cron-Job zweimal täglich ausgeführt werden. Nach erfolgreichen Updates startet der Pi automatisch neu.

**Cron-Optimierungen (Januar 2026):**
Das Skript ist jetzt speziell für zuverlässige Cron-Ausführung optimiert:

- **Robuste Fehlerbehandlung**: Einzelne Modul-Fehler stoppen nicht das gesamte Skript
- **Automatischer PATH**: node, npm, git werden automatisch gefunden
- **nvm-Unterstützung**: Node Version Manager wird automatisch geladen
- **Intelligenter Reboot**: System startet nur neu wenn Updates installiert wurden
- **Fehler-Logging**: Alle Fehler werden geloggt, Skript macht trotzdem weiter
- **Modul-Isolation**: Jedes Modul läuft in eigener Subshell
- **Lockfile**: Verhindert dass Skript mehrfach gleichzeitig läuft

Beispiel crontab (editiere mit `crontab -e`):
```bash
# Ausführung täglich um 02:50 und 14:50 — nach Updates erfolgt automatischer Neustart
50 2 * * * /home/pi/scripts/update_modules.sh >> /home/pi/update_modules.log 2>&1
50 14 * * * /home/pi/scripts/update_modules.sh >> /home/pi/update_modules.log 2>&1
```

**Wichtig**: 
- Das Skript führt bei Updates automatisch einen **kompletten System-Neustart** durch
- **Kein Neustart** wenn keine Updates gefunden wurden (`REBOOT_ONLY_ON_UPDATES=true`)
- Alle Ausgaben werden nach `~/update_modules.log` geschrieben
- **Log-Rotation** verhindert dass die Log-Datei zu groß wird (Standard: 5MB, behält 5 alte Logs)
- Bei Problemen: Log prüfen mit `cat ~/update_modules.log`

Alternativ: systemd-timer (wenn bevorzugt) — ich kann das für dich erstellen, wenn du möchtest.

Node.js Versions-Management
---------------------------------
**Neu ab Januar 2026:** Das Skript prüft und aktualisiert automatisch Node.js, falls erforderlich.

**MagicMirror 2.34.0+ benötigt:**
- Node.js >= 22.21.1 (nicht v23)
- ODER Node.js >= 24.x

**Automatische Node.js Installation:**
Das Skript nutzt **nvm (Node Version Manager)** für kompatible Installation auf allen Architekturen (inkl. armhf/32-bit):

1. Prüft aktuelle Node.js Version
2. Erkennt Systemarchitektur (x86_64, aarch64, armv7l)
3. Installiert nvm falls nicht vorhanden
4. Installiert Node.js v22 LTS via nvm (stabiler als v24 auf ARM)
5. Setzt v22 als Standard-Version

**Warum v22 statt v24?**
- Node.js v24 ist oft nicht für 32-bit ARM (armv7l/armhf) verfügbar
- v22 LTS bietet bessere Kompatibilität und Stabilität
- Erfüllt MagicMirror Mindestanforderungen (>=22.21.1)

**Manuelle Installation (falls gewünscht):**
```bash
# nvm installieren
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
source ~/.bashrc

# Node.js v22 installieren
nvm install 22
nvm use 22
nvm alias default 22

# Prüfen
node --version  # sollte v22.x.x zeigen
```

**Hinweis für 32-bit ARM (armhf):**
NodeSource unterstützt armhf nicht mehr - daher verwendet das Skript nvm, was auf allen Architekturen funktioniert.

MagicMirror Core Update
---------------------------------
Das Skript aktualisiert **automatisch den MagicMirror Core** vor den Modulen. Dies ist standardmäßig aktiviert.

**Update-Ablauf:**
1. **Node.js Version-Check** und automatisches Update falls erforderlich
2. **Backup der config.js** - Temporär und permanent gesichert
3. Wechsel ins MagicMirror-Hauptverzeichnis (`MAGICMIRROR_DIR`)
4. Prüfung auf lokale Änderungen (werden bei `AUTO_DISCARD_LOCAL=true` verworfen)
5. `git pull` zum Aktualisieren des Core-Codes
6. **Clean Install:** Löscht `node_modules` und `package-lock.json` für saubere Installation
7. `npm install --engine-strict=false` zur Installation aller Abhängigkeiten (inkl. Electron)
8. **Fallback-Mechanismus:** Bei Fehlern werden alternative Installationsmethoden versucht
9. **Electron-Verifikation:** Prüft, ob Electron korrekt installiert wurde
10. **Wiederherstellung der config.js** - Automatisch nach dem Update

Konfiguration in `update_modules.sh`:

```bash
UPDATE_MAGICMIRROR_CORE=true    # MagicMirror Core vor Modulen aktualisieren
MAGICMIRROR_DIR="/home/pi/MagicMirror"  # Pfad zum MagicMirror-Hauptverzeichnis
```

**Wichtig:**
- Das Core-Update erfolgt **vor** den Modul-Updates, um Kompatibilität sicherzustellen
- **config.js wird automatisch gesichert und wiederhergestellt** - sowohl temporär als auch permanent in `~/module_backups/config_backups/`
- Node.js wird automatisch aktualisiert wenn Version nicht kompatibel ist
- Bei lokalen Änderungen im Core wird das Update übersprungen (außer `AUTO_DISCARD_LOCAL=true`)
- Verwendet `--engine-strict=false` um Engine-Version-Konflikte zu umgehen
- Clean Install verhindert "electron: not found" Fehler
- Falls der Core nicht aktualisiert werden soll, setze `UPDATE_MAGICMIRROR_CORE=false`

**config.js & custom.css Schutz:**
Das Skript sichert automatisch deine `config/config.js` und `css/custom.css` vor dem Update:
- **Temporäres Backup:** `/tmp/magicmirror_config_backup_TIMESTAMP.js` und `/tmp/magicmirror_custom_css_backup_TIMESTAMP.css` (werden nach Wiederherstellung gelöscht)
- **Permanentes Backup:** 
  - `~/module_backups/config_backups/config_TIMESTAMP.js` (bleibt erhalten)
  - `~/module_backups/css_backups/custom_TIMESTAMP.css` (bleibt erhalten)
- **Automatische Wiederherstellung:** Nach erfolgreichem Update werden beide Dateien automatisch wiederhergestellt
- **Konflikt-Erkennung:** Wenn config.js oder custom.css während des Updates geändert wurden, wird eine Vergleichskopie erstellt
- **Fehlerfall:** Bei fehlenden Dateien nach Update erfolgt automatische Wiederherstellung aus Backup
- **Hinweis:** custom.css ist optional - fehlende Datei wird nur als Warnung geloggt

**Fehlerbehebung bei "electron: not found":**
Das Skript behebt diesen Fehler automatisch durch:
- Entfernen alter `node_modules` vor Installation
- Mehrfache Fallback-Strategien bei Installationsfehlern
- Verifikation der Electron-Installation nach dem Update

Universelle Modul-Update-Strategie
Das Skript funktioniert **automatisch mit allen MagicMirror-Modulen** ohne manuelle Konfiguration:

- **Intelligente Git-Update-Erkennung (Neu 01/2026)**:
  - **Zählt verfügbare Commits** nach `git fetch` (z.B. "Commits behind origin/main: 1")
  - **Zeigt neue Commits** bevor Update durchgeführt wird
  - **Fallback bei git pull Problemen**: Wenn `git pull --ff-only` keine Updates durchführt obwohl welche verfügbar sind, verwendet das Skript automatisch `git reset --hard origin/branch`
  - **Branch-Erkennung**: Funktioniert automatisch mit `main`, `master` oder jedem anderen Branch
  - **Detailliertes Logging**: Zeigt alte und neue Commit-Hashes bei erfolgreichen Updates

- **Intelligente npm-Strategie**:
  - Nach Git-Updates mit `package-lock.json` → automatisch `npm ci` für saubere, deterministische Installation
  - Ohne Git-Update oder ohne Lockfile → `npm install` für maximale Flexibilität
  - 3-stufiges Fallback-System bei Fehlern:
    1. `npm ci` (wenn Lockfile vorhanden)
    2. `npm install` (Standard-Fallback)
    3. `npm install --only=production` (letzter Ausweg für Kompatibilität)

- **Update-Statistiken am Ende**:
  ```
  === Module Update Summary ===
  Total modules processed: 15
  Modules updated: 3
  Modules failed: 0
  Modules skipped: 1 (default)
  Overall success: 15 / 15
  ```

- **Visuelle Status-Indikatoren**:
  - ✓ Erfolgreiche Updates und Operationen
  - ✗ Fehler und Warnungen
  - Nummerierte Module: `[5] Processing module: MMM-CalendarExt3`

- **Automatische Fehlerbehandlung**: Bei unbekannten npm-Befehlen (alte npm-Versionen) probiert das Skript automatisch kompatible Alternativen
- **Git-Update Handling**: Bei `git fetch`/`git pull` Fehlern ("another git process" oder `index.lock`) wartet das Skript automatisch und versucht mehrmals erneut (exponentielles Backoff)
- **Lokale Änderungen**: Werden automatisch verworfen wenn `AUTO_DISCARD_LOCAL=true` (Standard) via `git reset --hard` + `git clean -fdx`

**Modul-spezifische Overrides** (nur für Sonderfälle):
- **MMM-Webuntis**: Verwendet `npm install --only=production` wegen Kompatibilitätsproblemen mit sehr alten npm-Versionen
- **MMM-RTSPStream**: Spezielle Behandlung bei Git-Updates:
  - **Vollständige Bereinigung**: `node_modules` und `package-lock.json` werden entfernt
  - **ffmpeg-Überprüfung**: Automatische Installation falls ffmpeg fehlt
  - **ffmpeg-Fähigkeiten**: Prüfung auf RTSP-Support und H.264-Codec
  - **npm-Cache**: Wird vor Installation geleert
  - **Native Module**: Installation mit `--build-from-source` Flag
  - **Dependency-Checks**: Automatische Überprüfung kritischer Pakete nach npm install:
    - `datauri` (häufigste Fehlerquelle - wird automatisch nachinstalliert falls fehlend)
    - `node-ffmpeg-stream` (für ffmpeg-Integration)
    - `express` (für Webserver-Funktionalität)
  - **Module-Load-Test**: Verifiziert, dass `datauri` tatsächlich geladen werden kann
  - **Post-Install-Checks**: Überprüfung aller kritischen Dateien und ffmpeg-Zugriff aus Node.js
  - **Prozess-Cleanup**: Beendigung veralteter ffmpeg-Prozesse vor und nach Updates
  - **Pre-Reboot Health-Check**: Umfassende Überprüfung vor System-Neustart
- **MMM-Fuel**: Bei Git-Updates wird `node_modules` vor `npm ci` komplett gelöscht
- Alle anderen Module nutzen die universelle Strategie automatisch
Automatisches Raspbian-Update und System-Neustart
---------------------------------
Das Skript führt nach den Modul-Updates automatisch ein komplettes System-Update durch und startet den Raspberry Pi neu, **aber nur wenn Updates installiert wurden**.

**Update-Ablauf:**
1. **MagicMirror Core Update**: `git pull && node --run install-mm` im MagicMirror-Hauptverzeichnis
2. **Modul-Updates**: Git pull + npm install für alle MagicMirror-Module
3. **Raspbian-Update**: `sudo apt-get update && sudo apt-get full-upgrade` (nicht-interaktiv)
4. **Backup**: Optionales tar.gz-Backup des modules-Ordners vor dem apt-upgrade
5. **System-Neustart**: Kompletter Reboot des Pi **nur wenn Updates installiert wurden**

Konfiguration in `update_modules.sh`:

```bash
RUN_RASPBIAN_UPDATE=true        # apt-get update + full-upgrade ausführen
MAKE_MODULE_BACKUP=true         # Backup vor apt-upgrade erstellen
RESTART_AFTER_UPDATES=true      # System-Neustart nach Updates
AUTO_REBOOT_AFTER_SCRIPT=false  # NICHT bei jedem Lauf neustarten
REBOOT_ONLY_ON_UPDATES=true     # Nur neustarten wenn Updates da sind (empfohlen für Cron)
```

**Details und Hinweise:**
- Das Skript verwendet `DEBIAN_FRONTEND=noninteractive` und `apt-get full-upgrade` mit Dpkg-Optionen, um interaktive Dialoge zu vermeiden.
- Vor dem Upgrade wird (wenn aktiviert) ein komprimiertes Backup deines `modules`-Ordners nach `~/module_backups/` geschrieben.
- `apt-get full-upgrade` ist mächtiger als `upgrade`: es kann Abhängigkeiten anlegen und Pakete entfernen. Daher ist ein Backup empfehlenswert.
- Das Skript behandelt apt/dpkg-Locks mit einem Retry/Backoff-Mechanismus (bis zu 4 Versuche).
- **Intelligenter Reboot**: System startet nur neu wenn `updated_any=true` (Updates wurden installiert)
- Bei `DRY_RUN=true` wird kein Reboot durchgeführt.
- **Cron-freundlich**: Keine unnötigen Neustarts bei Cron-Jobs ohne Updates

**Warum kompletter System-Neustart bei Updates?**
- Stellt sicher, dass alle Module (besonders RTSPStream) komplett frisch starten
- Vermeidet Timing-Probleme bei ffmpeg-Stream-Initialisierung
- Aktiviert Kernel-Updates falls vorhanden
- pm2 startet MagicMirror automatisch via systemd beim Bootvorgang

Bevor du ein automatisches full-upgrade in Produktion nutzt, empfehle ich einen Dry‑Run:

```bash
DRY_RUN=true ~/scripts/update_modules.sh
```or du ein automatisches full-upgrade in Produktion nutzt, empfehle ich einen Dry‑Run:

```
DRY_RUN=true ~/scripts/update_modules.sh
```



Hinweise und Edge-Cases
- **Lokale Änderungen**: Bei `AUTO_DISCARD_LOCAL=true` (Standard) werden lokale Änderungen automatisch verworfen (`git reset --hard` + `git clean -fdx`). Sonst werden Repositories mit lokalen Änderungen übersprungen.
- **Git Pull**: Das Skript verwendet `git pull --ff-only` mit automatischem Fallback zu `git reset --hard origin/branch` falls Updates verfügbar sind aber pull versagt.
- **Update-Erkennung**: Nach `git fetch` wird die Anzahl verfügbarer Commits geprüft - funktioniert zuverlässig mit allen Branches (main/master/etc.).
- **npm**: Universelle Strategie für alle Module - automatische Wahl zwischen `npm ci` und `npm install` basierend auf Git-Update-Status und Lockfile-Vorhandensein.
- **npm Fallbacks**: Bei Fehlern probiert das Skript automatisch alternative npm-Befehle (ci → install → install --only=production) für maximale Kompatibilität.
- **pm2**: Das Skript prüft und konfiguriert pm2-Autostart, bereinigt fehlerhafte Prozesse und stellt sicher, dass der systemd-Service aktiviert ist.
- **npm Warnungen**: Deprecation-Warnungen bei älteren Modulen (z.B. rimraf, eslint) sind normal und unkritisch für lokale MagicMirror-Installation.
- **Security Vulnerabilities**: Low/High Vulnerabilities in Dev-Dependencies (jsdoc, eslint) sind für lokal laufende Module unkritisch und können ignoriert werden.
- **Neue Module**: Funktionieren automatisch ohne Konfiguration - die universelle Strategie passt sich an jedes Modul an.
- **default-Verzeichnis**: Wird automatisch übersprungen (enthält eingebaute MagicMirror-Module).

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

# pm2 Service aktivieren
sudo systemctl enable pm2-pi
sudo systemctl start pm2-pi

# Status prüfen
sudo systemctl status pm2-pi
pm2 list
```

Troubleshooting

**Module Updates werden nicht erkannt (z.B. CalendarExt3)**
- **Problem**: `git pull: already up-to-date` wird gemeldet, obwohl Updates verfügbar sind
- **Ursache**: In seltenen Fällen kann `git pull --ff-only` keine Updates durchführen
- **Lösung (automatisch seit 01/2026)**: 
  - Das Skript zählt verfügbare Commits nach `git fetch`
  - Wenn Commits verfügbar sind aber pull versagt, wird automatisch `git reset --hard origin/branch` verwendet
  - Im Log erscheint: "WARNING: git pull reported up-to-date but X commits are available on remote!"
- **Manuelle Prüfung**:
  ```bash
  cd /home/pi/MagicMirror/modules/MMM-CalendarExt3
  git fetch origin
  git log --oneline HEAD..origin/main  # zeigt verfügbare Updates
  ```

**Module funktionieren nach Update nicht** 
  - Das Skript versucht automatisch 3 Fallback-Strategien
  - Manuelle Reparatur: `rm -rf node_modules package-lock.json && npm install` im Modul-Ordner
  - Log prüfen: `cat ~/update_modules.log` zeigt welche Strategie verwendet wurde

- **RTSPStream zeigt nur "loading" oder funktioniert nach Update nicht**:
  - **Automatische Fixes im Skript**:
    - ✓ Vollständige Bereinigung von `node_modules` und `package-lock.json`
    - ✓ Automatische ffmpeg-Installation falls nicht vorhanden
    - ✓ Überprüfung von ffmpeg-Fähigkeiten (RTSP-Support, H.264-Codec)
    - ✓ npm-Cache wird vor Installation geleert
    - ✓ Installation mit `--build-from-source` für native Module
    - ✓ **Automatische Überprüfung kritischer Abhängigkeiten** (`datauri`, `node-ffmpeg-stream`, `express`)
    - ✓ **Automatische Nachinstallation fehlender Pakete** nach Updates
    - ✓ **Test ob `datauri`-Modul geladen werden kann** (häufigste Fehlerquelle)
    - ✓ Post-Install-Checks: Dateien, Berechtigungen, ffmpeg-Zugriff aus Node.js
    - ✓ Beendigung veralteter ffmpeg-Prozesse (Port 9999)
    - ✓ Pre-Reboot Health-Check mit detailliertem Status (✓/✗)
  - **Log-Überprüfung**: `cat ~/update_modules.log | grep -A 20 "RTSPStream"` zeigt alle Checks
  - **Häufigste Fehlerursache**: Fehlendes `datauri`-Modul
    - **Symptom**: `Cannot find module 'datauri'` in pm2 logs
    - **Automatische Lösung**: Skript erkennt und installiert fehlende Abhängigkeiten
    - **Manuelle Lösung**:
      ```bash
      cd /home/pi/MagicMirror/modules/MMM-RTSPStream
      sudo npm install datauri --save
      sudo chown -R pi:pi .
      pm2 restart MagicMirror
      ```
  
  - **Häufige Probleme und Lösungen**:
    
    1. **ffmpeg-Prozesse blockieren**: `pkill -KILL -f "ffmpeg" && pm2 restart MagicMirror`
    
    2. **ffmpeg fehlt/defekt**: `sudo apt-get install --reinstall -y ffmpeg`
    
    3. **Dependencies fehlen**: 
       ```bash
       cd /home/pi/MagicMirror/modules/MMM-RTSPStream
       rm -rf node_modules package-lock.json
       npm cache clean --force
       npm install
       sudo chown -R pi:pi .
       ```
    
    4. **RTSP-URL nicht erreichbar**: `ffmpeg -i 'rtsp://ihre-kamera-ip:554/stream' -f null -`
    
    5. **Port 9999 belegt**: `netstat -tuln | grep 9999`
  
  - **Manuelle Komplettprüfung**:
    ```bash
    # ffmpeg testen
    ffmpeg -version
    ffmpeg -formats 2>&1 | grep rtsp
    ffmpeg -codecs 2>&1 | grep h264
    
    # Dependencies prüfen
    cd /home/pi/MagicMirror/modules/MMM-RTSPStream
    ls -la node_modules/ | grep -E "datauri|node-ffmpeg-stream|express"
    
    # Komplett neu installieren
    rm -rf node_modules package-lock.json
    npm cache clean --force
    npm install
    sudo chown -R pi:pi .
    
    # ffmpeg-Prozesse beenden
    pkill -KILL -f "ffmpeg"
    
    # MagicMirror neu starten
    pm2 restart MagicMirror
    pm2 logs MagicMirror --lines 50
    ```

- **Fuel-Modul zeigt keine Daten nach Update**: 
  - Gleiche Behandlung wie RTSPStream - automatische Bereinigung bei Git-Updates
  - Manuelle Fix: `cd /home/pi/MagicMirror/modules/MMM-Fuel && rm -rf node_modules && npm install`

- **npm-Befehl schlägt fehl**: Skript probiert automatisch Alternativen (ci → install → install --only=production)

- **pm2 startet nicht automatisch**: Prüfe `sudo systemctl status pm2-pi` und ob `pm2 save` ausgeführt wurde

- **npm Deprecation Warnings**: Normal bei älteren Modulen, funktionieren meist trotzdem

- **Security Vulnerabilities**: Bei Dev-Dependencies in lokalen Modulen unkritisch, können ignoriert werden

- **Neues Modul aktualisieren**: Keine Konfiguration nötig - läuft automatisch mit der universellen Strategie

- **ffmpeg fehlt oder funktioniert nicht**:
  - Das Skript installiert ffmpeg automatisch falls nicht vorhanden
  - Manuelle Installation: `sudo apt-get update && sudo apt-get install -y ffmpeg`
  - Überprüfung: `which ffmpeg && ffmpeg -version`

Automatische Electron-Prüfung & Selbstheilung (ab Februar 2026)
--------------------------------------------------------------
**Neu:** Das Skript prüft vor jedem Update-Lauf, ob Electron im MagicMirror-Hauptverzeichnis installiert ist. Falls nicht, wird automatisch `npm install` im MagicMirror-Ordner ausgeführt.

**Vorteile:**
- Verhindert zuverlässig den Fehler `./node_modules/.bin/electron: not found` nach Updates oder gelöschten node_modules
- Keine manuellen Reparaturen mehr nötig – das Skript erkennt und behebt fehlende Electron-Installation selbst
- Funktioniert auch nach Node.js- oder MagicMirror-Core-Updates automatisch

**Ablauf:**
1. Nach dem Node.js-Check prüft das Skript, ob `node_modules/.bin/electron` im MagicMirror-Ordner existiert
2. Falls nicht, wird automatisch `npm install` im MagicMirror-Hauptverzeichnis ausgeführt
3. Erst danach werden MagicMirror und die Module wie gewohnt aktualisiert und gestartet

**Hinweis:**
- Diese Prüfung läuft immer automatisch – kein Eingriff nötig
- Im Log erscheint z.B.:
  - `Electron nicht gefunden – führe npm install im MagicMirror-Ordner aus...`
  - `✓ npm install im MagicMirror-Ordner erfolgreich (electron installiert)`
  - `✓ Electron ist im MagicMirror-Ordner installiert`

**Manuelle Reparatur ist damit nicht mehr nötig!**

Log als E-Mail-Anhang (ab Februar 2026)
---------------------------------------
**Neu:** Das Skript kann die Log-Datei automatisch als E-Mail-Anhang versenden.

**Konfiguration:**
- `EMAIL_ATTACH_LOG=true` (Standard: true) – aktiviert das Versenden der Log-Datei als Anhang
- Unterstützte Mail-Tools: `mail`, `msmtp`, `sendmail` (automatische Erkennung)

**Vorteile:**
- Die vollständige Log-Datei wird als Anhang an die E-Mail gehängt (bei Erfolg oder Fehler)
- Erleichtert die Fehleranalyse und Nachverfolgung von Updates
- Funktioniert mit allen unterstützten E-Mail-Tools automatisch

**Ablauf:**
1. Nach jedem Update-Lauf prüft das Skript, ob E-Mail-Benachrichtigungen aktiviert sind
2. Ist `EMAIL_ATTACH_LOG=true` und ein unterstütztes Mail-Tool vorhanden, wird die Log-Datei als Anhang versendet
3. Im Log erscheint z.B.:
   - `E-Mail mit Log-Anhang gesendet an ... (via mail/msmtp/sendmail)`
   - `WARNING: Kein Mail-Tool mit Anhang-Unterstützung gefunden, sende E-Mail ohne Anhang.`

**Hinweis:**
- Die Option funktioniert nur, wenn ein unterstütztes Mail-Tool installiert und konfiguriert ist
- Bei Problemen erscheint eine Warnung im Log
- Die Log-Datei wird nur als Anhang versendet, wenn sie existiert und E-Mail-Benachrichtigungen aktiviert sind
- Die Option kann in der Konfiguration oder direkt im Skript gesetzt werden

Automatische Log-Fehlerprüfung & Selbstheilung (ab Februar 2026)
--------------------------------------------------------------
**Neu:** Das Skript prüft nach jedem Lauf automatisch die Log-Datei auf typische Fehler und versucht, diese direkt zu beheben.

**Erkannte & automatisch behandelte Fehler (Beispiele):**
- **electron: not found / electron fehlt**: Automatisches `npm install` im MagicMirror-Ordner
- **Cannot find module 'datauri'**: Automatisches `npm install datauri` im RTSPStream-Modul
- **Git-Lock-Fehler (index.lock/Another git process)**: Entfernt alle `index.lock`-Dateien in allen Repos
- **Berechtigungsfehler (chown/permission denied)**: Setzt Besitzrechte auf `$CHOWN_USER` für MagicMirror und alle Module
- **npm cache Fehler**: Leert den npm cache automatisch
- **Fehlende package-lock.json**: Führt `npm install` in allen betroffenen Modulen aus
- **npm audit Schwachstellen**: Führt automatisch `npm audit fix` im MagicMirror-Hauptverzeichnis aus

**Ablauf:**
1. Nach jedem Update-Lauf wird die Log-Datei nach bekannten Fehlermustern durchsucht
2. Für jeden erkannten Fehler wird eine passende Korrektur automatisch ausgeführt
3. Nach Korrekturversuchen wird eine E-Mail-Benachrichtigung versendet (wenn aktiviert)
4. Alle Aktionen werden im Log dokumentiert

**Hinweise:**
- Die Fehlerprüfung erkennt nur bekannte Muster – neue Fehler können ergänzt werden
- Kritische oder nicht automatisch behebbare Fehler erfordern weiterhin manuelles Eingreifen
- Die Funktion kann leicht um weitere Fehler/Korrekturen erweitert werden
- Nach Änderungen empfiehlt sich ein Testlauf mit absichtlich erzeugten Fehlern
