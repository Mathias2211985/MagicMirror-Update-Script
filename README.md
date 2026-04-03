Update Modules Script for Raspberry Pi

This folder contains a script to automatically update MagicMirror modules (git + npm) and optionally restart the system. Unterstützt sowohl **Wayland (labwc)** als auch **X11 (pm2)** Display-Server — Auto-Detection erkennt die richtige Konfiguration automatisch.

**🆕 Self-Update, Wayland/labwc-Support & Auto-Detection (April 2026)**
- ✓ **Self-Update**: Script aktualisiert sich automatisch von GitHub bevor es startet — neue Features und Bugfixes werden automatisch eingespielt
- ✓ **Wayland/labwc-Support**: MagicMirror v2.35+ nutzt Wayland statt X11 — Script erkennt und konfiguriert das automatisch
- ✓ **Auto-Detection**: Alle Pfade, User, Wayland-Socket, Display-Server und Port werden automatisch erkannt (`"auto"` als Default)
- ✓ **Flexibles start-mm.sh**: Wird automatisch erstellt mit korrekten Wayland-Variablen, NVM-Pfad und MagicMirror-Verzeichnis
- ✓ **Doppelstart-Schutz**: Verhindert dass MagicMirror sowohl über PM2-resurrect als auch labwc-autostart gestartet wird
- ✓ **CLI-Argumente**: `--help`, `--dry-run`, `--config FILE`, `--status`, `--verbose`, `--no-self-update`
- ✓ **Zusammenfassungs-Report**: Am Ende jedes Laufs: Dauer, Anzahl Updates, MM-Status, Speicherplatz
- ✓ **Electron-Schutz vor Reboot**: Prüft ob Electron installiert ist bevor ein Reboot durchgeführt wird — installiert es automatisch nach falls fehlend
- ✓ **custom.css Backup-Fix**: custom.css wird jetzt in `config/` UND `css/` gesucht (vorher nur `css/` — falsch bei vielen Setups)
- ✓ **git clean schützt User-Dateien**: `git clean -fdx` im Core-Update schließt jetzt `config/`, `css/` und `node_modules/` aus — verhindert Datenverlust
- ✓ **Atomares Lockfile**: Race Condition behoben — nutzt jetzt `mkdir` statt File-Check
- ✓ **npm audit fix --force entfernt**: Konnte Module durch Major-Version-Upgrades zerstören — jetzt nur Warnung + E-Mail
- ✓ **Backup-Sicherheit**: Speicherplatz-Check (min. 100MB) vor Backup, Validierung nach Erstellung
- ✓ **Portables Backup-Cleanup**: Funktioniert jetzt auch auf nicht-GNU-Systemen (kein `find -printf` mehr)
- ✓ **E-Mail-Bug gefixt**: `send_email` hatte umgekehrte Logik — E-Mails mit leerer Adresse krachten statt abzubrechen
- ✓ **Wayland-Fehlererkennung**: Erkennt automatisch Wayland-Verbindungsfehler im Log und gibt Empfehlungen

**🆕 Bugfixes & Verbesserungen (Februar 2026)**
- ✓ **Speicherplatz-Check**: Prüft vor dem Start ob mindestens 200MB frei sind — verhindert kaputte Module durch volle Festplatte
- ✓ **npm nur bei Änderungen**: `npm ci`/`npm install` wird nur noch ausgeführt wenn das Modul tatsächlich aktualisiert wurde oder `node_modules` fehlt. Verhindert, dass `npm ci` bei Netzwerkfehlern funktionierende Module zerstört
- ✓ **Netzwerk-Retry für npm**: Bei Netzwerkfehlern (`ECONNRESET`, `ETIMEDOUT`) werden npm-Befehle automatisch bis zu 3x mit 5 Sekunden Pause wiederholt — verhindert fehlgeschlagene Installationen durch temporäre Netzwerkprobleme
- ✓ **Kritische Fehler-Tracking**: npm install Fehler werden jetzt getrackt und führen zu "⚠ Done with ERRORS" statt "✓ Done" — fehlgeschlagene Module werden in der Update-Summary als "failed" gezählt
- ✓ **E-Mail bei kritischen Modul-Fehlern**: Bei fehlgeschlagenem npm install für wichtige Module (RTSPStream, Remote-Control, Camera, etc.) wird automatisch eine E-Mail mit Reparatur-Anleitung versendet
- ✓ **Automatisches System-Cleanup**: Cache leeren (APT, User-Cache), RAM freigeben, alte Pakete entfernen und Systemlogs bereinigen — läuft automatisch bei jedem Update vor dem Neustart
- ✓ **npm 11 Kompatibilität**: `--only=production` durch `--omit=dev` ersetzt (npm 11+ unterstützt den alten Flag nicht mehr)
- ✓ **Zähler-Bug behoben**: Update-Zähler enthielt Zeilenumbruch, was zu `integer expression expected`-Fehlern führte
- ✓ **Backup-Cleanup erweitert**: Config- und CSS-Backups werden jetzt auch automatisch aufgeräumt (max. 4 behalten)
- ✓ **Log-Fehlerprüfung erreichbar**: `scan_and_fix_log_errors` wurde vor `exit 0` verschoben (war vorher unerreichbar)
- ✓ **MediaMTX-Schutz**: Das `mediamtx/`-Verzeichnis in MMM-RTSPStream wird vor Updates gesichert und danach wiederhergestellt — WebRTC-Proxy überlebt Modul-Updates

**🆕 Neue Features (Januar 2026)**
- ✓ **E-Mail-Benachrichtigungen**: Optional bei Fehlern oder erfolgreichen Updates
- ✓ **Log-Rotation**: Automatische Rotation wenn Log zu groß wird (Standard: 5MB)
- ✓ **Externe Konfiguration**: Config-Datei statt Skript editieren
- ✓ **Healthcheck vor Reboot**: Prüft ob MagicMirror läuft bevor Neustart
- ✓ **Lockfile**: Verhindert parallele Ausführungen
- ✓ **Backup-Cleanup**: Alte Backups werden automatisch gelöscht (behält 4)

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
- `update_modules.sh` — Hauptskript. Erkennt alle Einstellungen automatisch, keine manuelle Konfiguration nötig. Aktualisiert sich selbst von GitHub.
- `config.example.sh` — Beispiel-Konfigurationsdatei (optional — kopieren und anpassen falls gewünscht).

Installation
1) Klone das Repository auf den Raspberry Pi (empfohlen für automatische Self-Updates):

```bash
# auf dem Pi — Git-Clone ermöglicht automatische Script-Updates
git clone https://github.com/Mathias2211985/MagicMirror-Update-Script.git ~/scripts
chmod +x ~/scripts/update_modules.sh
```

Alternativ: Einzelne Datei kopieren (Self-Update nutzt dann Download statt Git):

```bash
mkdir -p ~/scripts
scp update_modules.sh config.example.sh pi@raspberrypi:~/scripts/
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

2) **Option B**: Variablen direkt im Skript anpassen (oder `"auto"` für Auto-Detection):
- `MAGICMIRROR_DIR` — `"auto"` (Standard) erkennt automatisch, oder Pfad angeben (z. B. `/home/pi/MagicMirror`).
- `MODULES_DIR` — `"auto"` (Standard) = `$MAGICMIRROR_DIR/modules`, oder Pfad angeben.
- `MM_START_METHOD` — `"auto"` (Standard) erkennt ob Wayland (labwc) oder X11 (pm2), oder `"labwc"` / `"pm2"` manuell setzen.
- `MM_START_SCRIPT` — `"auto"` (Standard) = `$HOME/start-mm.sh`, oder Pfad angeben. Wird automatisch erstellt falls fehlend.
- `UPDATE_MAGICMIRROR_CORE` — `true` (Standard) aktualisiert MagicMirror Core vor den Modulen.
- `PM2_PROCESS_NAME` — Name des pm2-Prozesses (z. B. `MagicMirror`). Nur relevant bei `MM_START_METHOD="pm2"`.
- `RESTART_AFTER_UPDATES` — `true` oder `false` (ob der Pi nach Updates neu gestartet werden soll).
- `DRY_RUN` — `true` um eine Simulation zu fahren (keine Änderungen, kein Reboot). Auch per CLI: `--dry-run`.
- `AUTO_DISCARD_LOCAL` — `true` (Standard) verwirft automatisch lokale Änderungen in Git-Repos.
- `RUN_RASPBIAN_UPDATE` — `true` (Standard) führt `apt-get update` und `apt-get full-upgrade` nach Modul-Updates aus.
- `AUTO_REBOOT_AFTER_SCRIPT` — `false` (Standard) rebootet **nicht** nach jedem Lauf (nur bei Updates).
- `REBOOT_ONLY_ON_UPDATES` — `true` (Standard) rebootet **nur** wenn Updates installiert wurden.
- `HEALTHCHECK_URL` — `"auto"` (Standard) liest den Port aus `config.js`, oder URL manuell angeben.
- `LOG_FILE` — Pfad zur Log-Datei (Standard: `$HOME/update_modules.log`).

3) **Branch-Check für Module** (wichtig vor dem ersten Lauf):

Viele MagicMirror-Module haben ihren Default-Branch von `master` auf `main` umgestellt (z.B. MMM-CalendarExt3). Wenn dein lokaler Clone noch auf `master` ist, kann das Script keine Updates finden. Prüfe und korrigiere das **einmalig** auf dem Pi:

```bash
cd /home/pi/MagicMirror/modules
for mod in */; do
  if [ -d "$mod/.git" ]; then
    branch=$(git -C "$mod" rev-parse --abbrev-ref HEAD)
    remote_main=$(git -C "$mod" remote show origin 2>/dev/null | grep "HEAD branch" | awk '{print $NF}')
    if [ "$branch" != "$remote_main" ] && [ -n "$remote_main" ]; then
      echo "⚠ $mod: lokal=$branch, remote=$remote_main — wechsle Branch..."
      git -C "$mod" fetch origin
      git -C "$mod" checkout "$remote_main"
      git -C "$mod" branch -D "$branch" 2>/dev/null || true
    fi
  fi
done
```

Dieses Kommando prüft alle Module und stellt sie automatisch auf den richtigen Remote-Branch um.

4) Dry-run testen:

```bash
# auf dem Pi (per CLI-Argument — empfohlen)
~/scripts/update_modules.sh --dry-run

# oder per Umgebungsvariable:
DRY_RUN=true ~/scripts/update_modules.sh
```

5) Status prüfen (ohne Änderungen):

```bash
~/scripts/update_modules.sh --status
```

6) Wenn alles in Ordnung ist, echten Lauf starten:

```bash
~/scripts/update_modules.sh
```

7) Eigene Konfigurationsdatei verwenden:

```bash
~/scripts/update_modules.sh --config /pfad/zu/meiner/config.sh
```

Automatisches Script-Update (Self-Update)
---------------------------------
Das Skript aktualisiert sich **automatisch** bei jedem Start von GitHub — neue Features und Bugfixes werden ohne manuelles Eingreifen eingespielt.

**Wie es funktioniert:**
1. Vor jedem Lauf prüft das Script ob eine neuere Version auf GitHub verfügbar ist
2. **Git-Methode** (wenn Script in einem Git-Repo liegt): `git fetch` + Vergleich mit `origin/master`
3. **Download-Methode** (wenn Script standalone liegt): Download via `curl`/`wget` + SHA256-Vergleich
4. Bei Update: Script wird ersetzt und startet sich automatisch mit den gleichen Argumenten neu
5. **Endlos-Schleifen-Schutz**: Nach einem Self-Update wird kein zweites Update geprüft

**Konfiguration:**
```bash
SELF_UPDATE_ENABLED=true              # true = automatisch updaten (Standard)
SELF_UPDATE_BRANCH="master"           # Branch von dem Updates gezogen werden
```

**Deaktivieren:**
```bash
# Per CLI-Argument (einmalig)
~/scripts/update_modules.sh --no-self-update

# Permanent in der Config-Datei
echo 'SELF_UPDATE_ENABLED=false' >> ~/.config/magicmirror-update/config.sh
```

**Hinweise:**
- Self-Update läuft VOR dem Lockfile — blockiert keine parallele Ausführung
- Bei Netzwerkproblemen wird das Update übersprungen und die aktuelle Version verwendet
- Heruntergeladene Dateien werden auf Gültigkeit geprüft (Shebang-Check)
- Datei-Berechtigungen bleiben beim Update erhalten

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
HEALTHCHECK_URL="auto"              # erkennt Port aus config.js, oder manuell z.B. "http://localhost:8080"
```

Das Skript erkennt automatisch die Start-Methode und passt den Healthcheck an:

**Wayland/labwc-Modus** (`MM_START_METHOD="labwc"`):
1. Prüft ob ein Electron-Prozess (`electron.*js/electron.js`) läuft
2. Wartet bis zu 30 Sekunden auf den Prozess
3. Führt HTTP-Check durch (wenn curl/wget verfügbar)
4. Sendet E-Mail bei Problemen (wenn aktiviert)

**Legacy PM2-Modus** (`MM_START_METHOD="pm2"`):
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
MAGICMIRROR_DIR="auto"          # "auto" = automatisch erkennen (Standard)
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
Das Skript sichert automatisch deine `config/config.js` und `custom.css` vor dem Update:
- **custom.css Auto-Detection**: Wird automatisch in `config/custom.css` und `css/custom.css` gesucht — funktioniert mit beiden Pfaden
- **git clean Schutz (Neu 04/2026)**: `git clean -fdx` im Core-Update schließt `config/`, `css/` und `node_modules/` aus — User-Dateien werden nicht mehr gelöscht
- **Temporäres Backup:** `/tmp/magicmirror_config_backup_TIMESTAMP.js` und `/tmp/magicmirror_custom_css_backup_TIMESTAMP.css` (werden nach Wiederherstellung gelöscht)
- **Permanentes Backup:** 
  - `~/module_backups/config_backups/config_TIMESTAMP.js` (bleibt erhalten)
  - `~/module_backups/css_backups/custom_TIMESTAMP.css` (bleibt erhalten)
- **Automatische Wiederherstellung:** Nach erfolgreichem Update werden beide Dateien automatisch wiederhergestellt
- **Konflikt-Erkennung:** Wenn config.js oder custom.css während des Updates geändert wurden, wird eine Vergleichskopie erstellt
- **Fehlerfall:** Bei fehlenden Dateien nach Update erfolgt automatische Wiederherstellung aus Backup
- **Hinweis:** custom.css ist optional - fehlende Datei wird nur als Warnung geloggt

**Electron-Schutz (Neu 04/2026):**
Das Skript stellt sicher, dass Electron nach Updates vorhanden ist:
- **Vor jedem Reboot**: Prüft ob `node_modules/.bin/electron` existiert — installiert es automatisch nach falls fehlend
- **git clean schützt node_modules**: `git clean -fdx -e "node_modules/"` verhindert versehentliches Löschen
- **Fallback-Strategien**: `npm install --engine-strict=false` mit mehreren Versuchen
- **Fehlermeldung**: CRITICAL-Warnung + E-Mail falls Electron nach npm install immer noch fehlt

Universelle Modul-Update-Strategie
Das Skript funktioniert **automatisch mit allen MagicMirror-Modulen** ohne manuelle Konfiguration:

- **Intelligente Git-Update-Erkennung (Neu 01/2026)**:
  - **Zählt verfügbare Commits** nach `git fetch` (z.B. "Commits behind origin/main: 1")
  - **Zeigt neue Commits** bevor Update durchgeführt wird
  - **Fallback bei git pull Problemen**: Wenn `git pull --ff-only` keine Updates durchführt obwohl welche verfügbar sind, verwendet das Skript automatisch `git reset --hard origin/branch`
  - **Branch-Erkennung**: Funktioniert automatisch mit `main`, `master` oder jedem anderen Branch
  - **Detailliertes Logging**: Zeigt alte und neue Commit-Hashes bei erfolgreichen Updates

- **Intelligente npm-Strategie (verbessert 02/2026)**:
  - npm wird **nur ausgeführt** wenn das Modul tatsächlich aktualisiert wurde oder `node_modules` fehlt
  - Unveränderte Module mit vorhandenen `node_modules` werden übersprungen — verhindert, dass `npm ci` bei Netzwerkfehlern funktionierende Module zerstört
  - Nach Git-Updates mit `package-lock.json` → automatisch `npm ci` für saubere, deterministische Installation
  - Ohne Git-Update oder ohne Lockfile → `npm install` für maximale Flexibilität (sicherer, löscht node_modules nicht)
  - **Automatisches Retry bei Netzwerkfehlern**: Bei `ECONNRESET`, `ETIMEDOUT`, `ENOTFOUND` wird npm bis zu 3x mit 5 Sekunden Pause wiederholt
  - **Fehler-Tracking**: Fehlgeschlagene npm installs werden getrackt und führen zu "⚠ Done with ERRORS" Status
  - **E-Mail-Benachrichtigung**: Bei kritischen Modulen (RTSPStream, Remote-Control, etc.) wird automatisch eine E-Mail mit Reparatur-Anleitung versendet
  - 3-stufiges Fallback-System bei Fehlern:
    1. `npm ci` (wenn Lockfile vorhanden)
    2. `npm install` (Standard-Fallback)
    3. `npm install --omit=dev` (letzter Ausweg für Kompatibilität)

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
- **MMM-Webuntis**: Verwendet `npm install --omit=dev` (dev-Dependencies werden übersprungen)
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
  - **MediaMTX-Schutz** (Neu 02/2026): Das `mediamtx/`-Verzeichnis (WebRTC-Proxy) wird bei Updates automatisch geschützt:
    - Backup des `mediamtx/`-Verzeichnisses vor Git-Operationen nach `/tmp/`
    - `git clean -fdx -e "mediamtx/"` schließt das Verzeichnis vom Löschen aus
    - Automatische Wiederherstellung nach npm-Operationen
    - MediaMTX-Binary und `mediamtx.yml`-Konfiguration bleiben erhalten
- **MMM-Fuel**: Bei Git-Updates wird `node_modules` vor `npm ci` komplett gelöscht
- Alle anderen Module nutzen die universelle Strategie automatisch
Automatisches Raspbian-Update und System-Neustart
---------------------------------
Das Skript führt nach den Modul-Updates automatisch ein komplettes System-Update durch und startet den Raspberry Pi neu, **aber nur wenn Updates installiert wurden**.

**Update-Ablauf:**
1. **Speicherplatz-Check**: Prüft ob mindestens 200MB frei sind (bricht bei zu wenig Platz ab)
2. **MagicMirror Core Update**: `git pull && node --run install-mm` im MagicMirror-Hauptverzeichnis
3. **Modul-Updates**: Git pull + npm install für alle MagicMirror-Module (npm nur bei tatsächlichen Änderungen)
4. **Raspbian-Update**: `sudo apt-get update && sudo apt-get full-upgrade` (nicht-interaktiv)
5. **Backup**: Optionales tar.gz-Backup des modules-Ordners vor dem apt-upgrade (max. 4 Backups)
6. **System-Cleanup**: Automatisches Aufräumen (Cache, RAM, alte Pakete) vor dem Neustart
7. **System-Neustart**: Kompletter Reboot des Pi **nur wenn Updates installiert wurden**

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
- Vor dem Upgrade wird (wenn aktiviert) ein komprimiertes Backup deines `modules`-Ordners nach `~/module_backups/` geschrieben (max. 4 Backups, ältere werden automatisch gelöscht).
- `apt-get full-upgrade` ist mächtiger als `upgrade`: es kann Abhängigkeiten anlegen und Pakete entfernen. Daher ist ein Backup empfehlenswert.
- Das Skript behandelt apt/dpkg-Locks mit einem Retry/Backoff-Mechanismus (bis zu 4 Versuche).
- **Intelligenter Reboot**: System startet nur neu wenn `updated_any=true` (Updates wurden installiert)
- Bei `DRY_RUN=true` wird kein Reboot durchgeführt.
- **Cron-freundlich**: Keine unnötigen Neustarts bei Cron-Jobs ohne Updates

**Warum kompletter System-Neustart bei Updates?**
- Stellt sicher, dass alle Module (besonders RTSPStream) komplett frisch starten
- Vermeidet Timing-Probleme bei ffmpeg-Stream-Initialisierung
- Aktiviert Kernel-Updates falls vorhanden
- MagicMirror startet automatisch beim Boot (via labwc-autostart oder pm2-systemd, je nach Konfiguration)

Bevor du ein automatisches full-upgrade in Produktion nutzt, empfehle ich einen Dry‑Run:

```bash
~/scripts/update_modules.sh --dry-run
```

Automatisches System-Cleanup (ab Februar 2026)
---------------------------------
**Neu:** Das Skript führt bei jedem Update automatisch ein System-Cleanup durch, um Speicherplatz freizugeben und die Performance zu verbessern.

**Was wird aufgeräumt:**
- ✓ **APT Cache**: `apt-get clean`, `autoclean` und `autoremove --purge` entfernen unnötige Pakete und Cache-Dateien
- ✓ **Systemlogs**: `journalctl --vacuum-time=7d` behält nur die letzten 7 Tage an Logs
- ✓ **User-Cache**: `~/.cache/*` wird geleert (Browser-Cache, Thumbnails, etc.)
- ✓ **RAM-Cache**: Page Cache, dentries und inodes werden freigegeben (`sysctl -w vm.drop_caches=3`)
- ✓ **Speichernutzung**: Nach dem Cleanup wird die aktuelle RAM-Nutzung ins Log geschrieben

**Ablauf:**
1. Das Cleanup läuft automatisch am Ende jedes Update-Durchlaufs
2. Es wird **vor** einem eventuellen System-Neustart ausgeführt
3. Bei `DRY_RUN=true` wird nur simuliert, was gemacht werden würde
4. Alle Aktionen werden ins Log geschrieben
5. Fehler beim Cleanup führen nicht zum Abbruch des Skripts

**Vorteile:**
- Verhindert, dass die SD-Karte mit der Zeit vollläuft
- Verbessert die Systemperformance durch RAM-Freigabe
- Entfernt automatisch alte, nicht mehr benötigte Pakete
- Reduziert Log-Größe für schnellere Fehlersuche

**Hinweis:**
- Das Cleanup respektiert Benutzer-Daten und Konfigurationen
- Nur Cache und temporäre Dateien werden gelöscht
- Die Aktion ist sicher und kann nicht zu Datenverlust führen



Hinweise und Edge-Cases
- **Lokale Änderungen**: Bei `AUTO_DISCARD_LOCAL=true` (Standard) werden lokale Änderungen automatisch verworfen (`git reset --hard` + `git clean -fdx`). Sonst werden Repositories mit lokalen Änderungen übersprungen.
- **Git Pull**: Das Skript verwendet `git pull --ff-only` mit automatischem Fallback zu `git reset --hard origin/branch` falls Updates verfügbar sind aber pull versagt.
- **Update-Erkennung**: Nach `git fetch` wird die Anzahl verfügbarer Commits geprüft - funktioniert zuverlässig mit allen Branches (main/master/etc.).
- **npm**: Universelle Strategie für alle Module - automatische Wahl zwischen `npm ci` und `npm install` basierend auf Git-Update-Status und Lockfile-Vorhandensein.
- **npm Fallbacks**: Bei Fehlern probiert das Skript automatisch alternative npm-Befehle (ci → install → install --omit=dev) für maximale Kompatibilität.
- **Autostart**: Das Skript erkennt automatisch ob Wayland (labwc) oder X11 (pm2) verwendet wird und konfiguriert den Autostart entsprechend. Bei labwc wird `start-mm.sh` + `~/.config/labwc/autostart` genutzt, bei X11 pm2 mit systemd.
- **npm Warnungen**: Deprecation-Warnungen bei älteren Modulen (z.B. rimraf, eslint) sind normal und unkritisch für lokale MagicMirror-Installation.
- **Security Vulnerabilities**: Low/High Vulnerabilities in Dev-Dependencies (jsdoc, eslint) sind für lokal laufende Module unkritisch und können ignoriert werden.
- **Neue Module**: Funktionieren automatisch ohne Konfiguration - die universelle Strategie passt sich an jedes Modul an.
- **default-Verzeichnis**: Wird automatisch übersprungen (enthält eingebaute MagicMirror-Module).

MagicMirror Autostart
---------------------------------
Das Skript unterstützt zwei Start-Methoden und erkennt automatisch welche benötigt wird:

**Wayland/labwc (Standard ab MagicMirror v2.35+ / Raspberry Pi OS Bookworm)**

MagicMirror wird über ein Start-Script (`start-mm.sh`) gestartet, das automatisch erstellt wird:
- Setzt NVM, Wayland-Display, XDG-Variablen
- Wird von `~/.config/labwc/autostart` aufgerufen
- Kein PM2 für den Start nötig (PM2 bleibt als Daemon verfügbar)
- **Doppelstart-Schutz**: Script entfernt MagicMirror automatisch aus PM2-dump falls vorhanden

```bash
# start-mm.sh wird automatisch erstellt, enthält z.B.:
#!/bin/bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
export WAYLAND_DISPLAY=wayland-0    # auto-detected
export XDG_RUNTIME_DIR=/run/user/1000
export XDG_SESSION_TYPE=wayland
cd ~/MagicMirror
npm start
```

**Legacy PM2 (X11 / ältere Systeme)**

Falls `MM_START_METHOD="pm2"` gesetzt oder auto-detected:
- Bereinigt fehlerhafte pm2-Prozesse automatisch
- Speichert die aktuelle pm2-Konfiguration mit `pm2 save`
- Prüft und aktiviert den systemd-Service

```bash
# Manuelle pm2-Setup-Schritte (falls noch nicht erfolgt):
pm2 startup
# Dann den angezeigten sudo-Befehl ausführen
pm2 save
sudo systemctl enable pm2-$(whoami)
```

Troubleshooting

**MagicMirror startet nicht nach Update auf v2.35+ (Wayland-Fehler)**
- **Problem**: `Failed to connect to Wayland display`, `Failed to initialize Wayland platform`, `SIGSEGV`
- **Ursache**: MagicMirror v2.35+ nutzt Wayland statt X11. Wenn MagicMirror aus einer TTY/SSH-Session gestartet wird, fehlt der Zugriff auf den Wayland-Display-Socket.
- **Lösung (automatisch)**: Das Update-Script erkennt Wayland-Fehler und konfiguriert den Start automatisch über `start-mm.sh` + labwc-autostart.
- **Manuelle Prüfung**:
  ```bash
  # Prüfe ob labwc läuft
  pgrep -x labwc
  
  # Prüfe Wayland-Socket
  ls /run/user/$(id -u)/wayland-*
  
  # Prüfe start-mm.sh
  cat ~/start-mm.sh
  
  # Prüfe labwc autostart
  cat ~/.config/labwc/autostart
  
  # Status prüfen
  ~/scripts/update_modules.sh --status
  ```
- **Manuelle Reparatur**:
  ```bash
  # start-mm.sh neu erstellen lassen
  rm ~/start-mm.sh
  ~/scripts/update_modules.sh --dry-run  # erstellt start-mm.sh automatisch
  sudo reboot
  ```

**Speicherplatz voll / Module kaputt nach Update**
- **Problem**: `No space left on device`-Fehler, Module ohne `node_modules`, PM2 kann nicht speichern
- **Ursache**: SD-Karte voll — `npm ci` löscht `node_modules` vor der Neuinstallation, bei Netzwerkfehler bleiben Module dann ohne Dependencies
- **Lösung (automatisch seit 02/2026)**:
  - Das Skript prüft vor dem Start ob mindestens 200MB frei sind und bricht bei zu wenig Platz ab
  - npm wird nur noch ausgeführt wenn sich ein Modul tatsächlich geändert hat oder `node_modules` fehlt
  - Alte Backups (Module, Config, CSS) werden automatisch aufgeräumt (max. 4 behalten)
- **Manuelle Reparatur bei vollem Speicher**:
  ```bash
  # Speicher prüfen
  df -h
  # Alte Backups löschen
  rm -rf ~/module_backups/*.tar.gz
  # npm Cache löschen
  sudo npm cache clean --force
  # apt Cache löschen
  sudo apt-get clean
  # Alte Logs löschen
  sudo journalctl --vacuum-size=50M
  # Dann kaputte Module reparieren
  cd /home/pi/MagicMirror/modules/MODULNAME && npm install
  ```

**Module Updates werden nicht erkannt (z.B. CalendarExt3)**
- **Problem**: `git pull: already up-to-date` wird gemeldet, obwohl Updates verfügbar sind
- **Häufigste Ursache**: Das Modul hat seinen Default-Branch umbenannt (z.B. `master` → `main`). Der lokale Clone ist noch auf dem alten Branch, der remote nicht mehr existiert. `git pull` findet dann keine Updates.
- **Lösung**: Branch auf dem Pi umstellen (siehe Installation Schritt 3) oder manuell:
  ```bash
  cd /home/pi/MagicMirror/modules/MMM-CalendarExt3
  git fetch origin
  git checkout main
  git branch -D master
  ```
- **Weitere Ursache**: In seltenen Fällen kann `git pull --ff-only` keine Updates durchführen
- **Lösung (automatisch seit 01/2026)**:
  - Das Skript zählt verfügbare Commits nach `git fetch`
  - Wenn Commits verfügbar sind aber pull versagt, wird automatisch `git reset --hard origin/branch` verwendet
  - Im Log erscheint: "WARNING: git pull reported up-to-date but X commits are available on remote!"
- **Manuelle Prüfung**:
  ```bash
  cd /home/pi/MagicMirror/modules/MMM-CalendarExt3
  git fetch origin
  # Aktuellen Branch und Remote-Default prüfen:
  git rev-parse --abbrev-ref HEAD
  git remote show origin | grep "HEAD branch"
  git log --oneline HEAD..origin/main  # zeigt verfügbare Updates
  ```

**npm install schlägt fehl wegen Netzwerkproblemen**
- **Problem**: `npm error network read ECONNRESET` oder `ETIMEDOUT` während npm install
- **Ursache**: Temporäre Netzwerkprobleme, Internet-Verbindung unterbrochen
- **Lösung (automatisch seit 02/2026)**:
  - Das Skript wiederholt npm install automatisch bis zu 3x mit 5 Sekunden Pause bei Netzwerkfehlern
  - Bei kritischen Modulen (RTSPStream, etc.) wird eine E-Mail mit Reparatur-Anleitung versendet
  - Im Status erscheint "⚠ Done with ERRORS" statt "✓ Done" bei Fehlschlag
  - Fehlgeschlagene Module werden in der Update-Summary gezählt
- **Manuelle Reparatur falls nötig**:
  ```bash
  cd ~/MagicMirror/modules/MODULNAME
  npm install
  sudo reboot  # oder: pm2 restart MagicMirror (bei PM2-Modus)
  ```

**Module funktionieren nach Update nicht**
  - Das Skript versucht automatisch 3 Fallback-Strategien (npm ci → install → install --omit=dev)
  - Bei Netzwerkfehlern werden bis zu 3 Retry-Versuche mit 5 Sekunden Pause unternommen
  - Manuelle Reparatur: `rm -rf node_modules package-lock.json && npm install` im Modul-Ordner
  - Log prüfen: `cat ~/update_modules.log` zeigt welche Strategie verwendet wurde und ob Retries stattfanden

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
      cd ~/MagicMirror/modules/MMM-RTSPStream
      npm install datauri --save
      sudo reboot
      ```
  
  - **Häufige Probleme und Lösungen**:
    
    1. **ffmpeg-Prozesse blockieren**: `pkill -KILL -f "ffmpeg" && sudo reboot`
    
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
    cd ~/MagicMirror/modules/MMM-RTSPStream
    ls -la node_modules/ | grep -E "datauri|node-ffmpeg-stream|express"
    
    # Komplett neu installieren
    rm -rf node_modules package-lock.json
    npm cache clean --force
    npm install
    
    # ffmpeg-Prozesse beenden und MagicMirror neu starten
    pkill -KILL -f "ffmpeg"
    sudo reboot
    ```

- **RTSPStream WebRTC/MediaMTX Setup**:
  - MMM-RTSPStream nutzt MediaMTX als RTSP-zu-WebRTC-Proxy (installiert im Modul-Ordner unter `mediamtx/`)
  - **Installation**:
    ```bash
    cd ~/MagicMirror/modules/MMM-RTSPStream/scripts
    # Für Raspberry Pi 3 (ARMv7): ARCH im Skript auf "linux_armv7" ändern
    # Für Raspberry Pi 4/5 (ARM64): ARCH auf "linux_arm64v8" ändern
    nano setup_mediamtx.sh
    chmod +x setup_mediamtx.sh && ./setup_mediamtx.sh
    ```
  - **Stream konfigurieren** in `mediamtx/mediamtx.yml`:
    ```yaml
    paths:
      my_camera:
        source: rtsp://user:pass@192.168.1.100:554/stream1
    ```
  - **Systemd-Service** für Autostart:
    ```bash
    sudo nano /etc/systemd/system/mediamtx.service
    # ExecStart=/home/pi/MagicMirror/modules/MMM-RTSPStream/mediamtx/mediamtx /home/pi/MagicMirror/modules/MMM-RTSPStream/mediamtx/mediamtx.yml
    sudo systemctl enable mediamtx && sudo systemctl start mediamtx
    ```
  - **MagicMirror config.js** — `whepUrl` muss zum Pfadnamen in `mediamtx.yml` passen:
    ```js
    stream1: {
        name: "Kamera",
        url: "rtsp://user:pass@192.168.1.100:554/stream1",
        whepUrl: "http://localhost:8889/my_camera/whep"
    }
    ```
  - **Hinweis**: Das Update-Skript schützt das `mediamtx/`-Verzeichnis automatisch bei Modul-Updates (Backup + Restore)
  - **MediaMTX Status prüfen**: `sudo systemctl status mediamtx`
  - **MediaMTX Logs**: `sudo journalctl -u mediamtx -f`

- **Fuel-Modul zeigt keine Daten nach Update**: 
  - Gleiche Behandlung wie RTSPStream - automatische Bereinigung bei Git-Updates
  - Manuelle Fix: `cd /home/pi/MagicMirror/modules/MMM-Fuel && rm -rf node_modules && npm install`

- **npm-Befehl schlägt fehl**: Skript probiert automatisch Alternativen (ci → install → install --omit=dev)

- **MagicMirror startet nicht nach Reboot**: Prüfe `~/scripts/update_modules.sh --status` für eine Übersicht. Bei labwc: `cat ~/.config/labwc/autostart` und `cat ~/start-mm.sh`. Bei PM2: `sudo systemctl status pm2-$(whoami)` und `pm2 list`

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
- **npm audit Schwachstellen**: Meldet Schwachstellen und sendet E-Mail-Warnung (kein automatisches `npm audit fix --force` mehr — zu gefährlich)

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
