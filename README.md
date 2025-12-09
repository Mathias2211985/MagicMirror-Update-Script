Update Modules Script for Raspberry Pi

This folder contains a script to automatically update MagicMirror modules (git + npm) and optionally restart the pm2 process.

**🆕 Verbesserte RTSPStream-Unterstützung (Dezember 2024)**
- ✓ Erweiterte ffmpeg-Prozess-Erkennung (mehrere Muster)
- ✓ Doppelte Überprüfung und Beendigung von Zombie-Prozessen
- ✓ Verbesserte npm-Cache-Bereinigung (inkl. /tmp/npm-*)
- ✓ Zusätzliche Dependency-Checks (url, fs, path)
- ✓ Erweiterte ffmpeg-Diagnose (PATH, Berechtigungen)
- ✓ Fallback npm install --force bei Problemen
- ✓ Zwei neue Hilfsskripte: diagnose_rtspstream.sh und fix_rtspstream.sh

Files
- update_modules.sh — main script. Configure the variables at the top before use.
- fix_rtspstream.sh — repair script specifically for MMM-RTSPStream issues
- diagnose_rtspstream.sh — diagnostic script to check RTSPStream installation status

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
- `RESTART_AFTER_UPDATES` — `true` oder `false` (ob der Pi nach Updates neu gestartet werden soll).
- `DRY_RUN` — `true` um zuerst eine Simulation zu fahren (keine Änderungen, kein Reboot).
- `AUTO_DISCARD_LOCAL` — `true` (Standard) verwirft automatisch lokale Änderungen in Git-Repos.
- `RUN_RASPBIAN_UPDATE` — `true` (Standard) führt `apt-get update` und `apt-get full-upgrade` nach Modul-Updates aus.
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

RTSPStream Spezial-Skripte
Das Repository enthält zwei zusätzliche Skripte speziell für MMM-RTSPStream Probleme:

**Diagnose-Skript (diagnose_rtspstream.sh)**
Überprüft den aktuellen Zustand der RTSPStream Installation und zeigt alle relevanten Informationen an.

```bash
# Kopiere Skript auf den Pi und mache es ausführbar
chmod +x ~/scripts/diagnose_rtspstream.sh

# Führe Diagnose aus
~/scripts/diagnose_rtspstream.sh
```

Das Skript prüft:
- Modul-Installation und Dateien
- Node.js Dependencies
- ffmpeg Installation und RTSP/H.264 Support
- Laufende Prozesse (MagicMirror, ffmpeg)
- Konfiguration in config.js
- Netzwerk-Status (Port 9999)
- System-Informationen
- Letzte Log-Einträge

**Reparatur-Skript (fix_rtspstream.sh)**
Behebt automatisch die häufigsten RTSPStream-Probleme durch komplette Neuinstallation.

```bash
# Kopiere Skript auf den Pi und mache es ausführbar
chmod +x ~/scripts/fix_rtspstream.sh

# Führe Reparatur aus
~/scripts/fix_rtspstream.sh
```

Das Skript führt folgende Schritte aus:
1. Stoppt MagicMirror
2. Beendet alle ffmpeg-Prozesse
3. Prüft/installiert ffmpeg mit RTSP-Support
4. Erstellt Backup der aktuellen Installation
5. Löscht alte Installation (node_modules, package-lock.json)
6. Bereinigt npm Cache
7. Installiert RTSPStream komplett neu (mit Fallback-Strategien)
8. Verifiziert Installation und Dependencies
9. Startet MagicMirror neu

Cron / Timer
Das Skript kann automatisch per Cron-Job zweimal täglich ausgeführt werden. Nach erfolgreichen Updates startet der Pi automatisch neu.

Beispiel crontab (editiere mit `crontab -e`):
```bash
# Ausführung täglich um 02:50 und 14:50 — nach Updates erfolgt automatischer Neustart
50 2 * * * /home/pi/scripts/update_modules.sh >> /home/pi/update_modules.log 2>&1
50 14 * * * /home/pi/scripts/update_modules.sh >> /home/pi/update_modules.log 2>&1
```

**Wichtig**: Das Skript führt bei Updates automatisch einen **kompletten System-Neustart** durch, um sicherzustellen, dass alle Module (insbesondere RTSPStream) sauber neu starten.

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
Das Skript führt nach den Modul-Updates automatisch ein komplettes System-Update durch und startet den Raspberry Pi neu. Dieser Workflow ist standardmäßig aktiviert.

**Update-Ablauf:**
1. **Modul-Updates**: Git pull + npm install für alle MagicMirror-Module
2. **Raspbian-Update**: `sudo apt-get update && sudo apt-get full-upgrade` (nicht-interaktiv)
3. **Backup**: Optionales tar.gz-Backup des modules-Ordners vor dem apt-upgrade
4. **System-Neustart**: Kompletter Reboot des Pi nach erfolgreichen Updates

Konfiguration in `update_modules.sh`:

```bash
RUN_RASPBIAN_UPDATE=true        # apt-get update + full-upgrade ausführen
MAKE_MODULE_BACKUP=true         # Backup vor apt-upgrade erstellen
RESTART_AFTER_UPDATES=true      # System-Neustart nach Updates
AUTO_REBOOT_AFTER_SCRIPT=true   # Neustart am Skript-Ende (zusätzlich)
```

**Details und Hinweise:**
- Das Skript verwendet `DEBIAN_FRONTEND=noninteractive` und `apt-get full-upgrade` mit Dpkg-Optionen, um interaktive Dialoge zu vermeiden.
- Vor dem Upgrade wird (wenn aktiviert) ein komprimiertes Backup deines `modules`-Ordners nach `~/module_backups/` geschrieben.
- `apt-get full-upgrade` ist mächtiger als `upgrade`: es kann Abhängigkeiten anlegen und Pakete entfernen. Daher ist ein Backup empfehlenswert.
- Das Skript behandelt apt/dpkg-Locks mit einem Retry/Backoff-Mechanismus (bis zu 4 Versuche).
- Nach erfolgreichen Updates wird der **gesamte Pi neu gestartet** (kein pm2-Restart), damit alle Module inkl. RTSPStream sauber starten.
- Bei `DRY_RUN=true` wird kein Reboot durchgeführt.

**Warum kompletter System-Neustart?**
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

# pm2 Service aktivieren
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
  - **Schnelle Lösung - Reparatur-Skripte verwenden**:
    ```bash
    # Diagnose durchführen (zeigt Status und mögliche Probleme)
    ~/scripts/diagnose_rtspstream.sh
    
    # Automatische Reparatur (behebt häufigste Probleme)
    ~/scripts/fix_rtspstream.sh
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
