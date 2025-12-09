# RTSPStream Update-Fix - Changelog

## Datum: 9. Dezember 2024

### Problem
RTSPStream wird nach automatischen Updates nicht mehr angezeigt. Das Modul schlägt beim Laden fehl oder ffmpeg-Prozesse können nicht gestartet werden.

### Implementierte Lösungen

#### 1. Verbesserungen in `update_modules.sh`

**Erweiterte ffmpeg-Prozess-Beendigung:**
- Prüft mehrere Prozessmuster: `ffmpeg.*9999`, `ffmpeg.*rtsp`, `ffmpeg.*MMM-RTSPStream`
- Doppelte Überprüfung vor und nach der Installation
- Wartet nach Beendigung und verifiziert erfolgreiche Terminierung
- Detailliertes Logging aller laufenden ffmpeg-Prozesse

**Verbesserte RTSPStream-Installation:**
- Zusätzliche Bereinigung von `/tmp/npm-*` temporären Dateien
- Doppelte Überprüfung und Beendigung von Zombie-Prozessen vor Löschung
- Erweiterte npm-Cache-Bereinigung (global)
- Längere Wartezeiten nach Prozess-Beendigung

**Erweiterte Post-Install-Verifikation:**
- Prüft zusätzliche Dependencies: `url`, `fs`, `path` (neben datauri, node-ffmpeg-stream, express)
- Fallback npm install --force wenn normale Installation fehlschlägt
- Erweiterte ffmpeg-Diagnose mit PATH und Berechtigungsprüfung
- Detailliertere Fehlermeldungen bei Problemen

#### 2. Neues Reparatur-Skript: `fix_rtspstream.sh`

Automatisches Reparatur-Skript mit 8 Schritten:

1. **Stoppt MagicMirror** (pm2 stop)
2. **Beendet alle ffmpeg-Prozesse** (mehrere Muster, SIGKILL)
3. **Prüft/installiert ffmpeg** (mit RTSP und H.264 Support-Check)
4. **Erstellt Backup** (tar.gz in ~/rtspstream_backups)
5. **Löscht alte Installation** (node_modules, package-lock.json, /tmp/npm-*)
6. **Bereinigt npm Cache** (npm cache clean --force)
7. **Neuinstallation mit Fallback-Strategien**:
   - Versuch 1: npm install
   - Versuch 2: npm ci (falls lockfile vorhanden)
   - Versuch 3: npm install --force
8. **Verifiziert Installation**:
   - Prüft node_helper.js
   - Prüft kritische Dependencies
   - Testet ffmpeg-Zugriff von Node.js
   - Testet datauri-Modul-Laden

Features:
- Farbige Konsolen-Ausgabe (rot/grün/gelb)
- Detailliertes Logging in ~/rtspstream_fix.log
- Automatischer MagicMirror-Neustart
- Backup vor jeder Änderung

#### 3. Neues Diagnose-Skript: `diagnose_rtspstream.sh`

Umfassende Diagnose in 8 Kategorien:

1. **Modul-Installation**: Dateien, Version, Git-Status, lokale Änderungen
2. **Node Dependencies**: Installierte Pakete, kritische Dependencies, package-lock.json
3. **ffmpeg**: Installation, Version, RTSP/H.264 Support, Berechtigungen, Node.js-Zugriff
4. **Laufende Prozesse**: MagicMirror, ffmpeg, pm2
5. **Konfiguration**: config.js, RTSPStream-Einstellungen
6. **Netzwerk**: Port 9999, Netzwerk-Interfaces
7. **System**: Node.js/npm Version, OS, Hardware, Speicher
8. **Logs**: Letzte pm2 und update_modules.log Einträge (RTSPStream-relevant)

Features:
- Keine Änderungen am System
- Farbige, übersichtliche Ausgabe
- Zusammenfassung mit erkannten Problemen
- Lösungsvorschläge am Ende

#### 4. Erweiterte README-Dokumentation

Neue Abschnitte:
- **RTSPStream Spezial-Skripte**: Beschreibung und Verwendung der neuen Skripte
- **Häufige Probleme und Lösungen**: 7 häufigste RTSPStream-Probleme mit konkreten Lösungen
- **Schnelllösungen**: Kurze Kommandos für sofortige Problemlösung
- **Schritt-für-Schritt Anleitungen**: Für Diagnose und Reparatur

### Verwendung auf dem Raspberry Pi

```bash
# 1. Neue Skripte auf den Pi kopieren
scp update_modules.sh fix_rtspstream.sh diagnose_rtspstream.sh pi@raspberrypi:~/scripts/

# 2. Ausführbar machen
ssh pi@raspberrypi
chmod +x ~/scripts/*.sh

# 3. Bei Problemen: Diagnose durchführen
~/scripts/diagnose_rtspstream.sh

# 4. Automatische Reparatur
~/scripts/fix_rtspstream.sh

# 5. Reguläres Update (mit verbesserten Checks)
~/scripts/update_modules.sh
```

### Warum diese Verbesserungen helfen

**Problem 1: Zombie ffmpeg-Prozesse**
- Alte ffmpeg-Prozesse blockieren Port 9999 oder halten Ressourcen
- Lösung: Mehrfache Überprüfung mit verschiedenen Mustern, SIGKILL statt SIGTERM

**Problem 2: Korrupte npm-Installation**
- Alte node_modules oder Cache-Dateien verursachen Inkonsistenzen
- Lösung: Komplette Bereinigung inkl. /tmp/npm-*, package-lock.json

**Problem 3: Fehlende Dependencies**
- datauri oder andere Module werden nicht korrekt installiert
- Lösung: Post-Install-Checks und automatische Nachinstallation mit --force

**Problem 4: ffmpeg nicht erreichbar**
- Node.js findet ffmpeg nicht im PATH oder hat keine Berechtigungen
- Lösung: Explizite Tests, PATH-Überprüfung, Berechtigungscheck

**Problem 5: Schwer zu diagnostizieren**
- Viele mögliche Fehlerquellen, unklare Logs
- Lösung: Diagnose-Skript zeigt alle relevanten Informationen übersichtlich

### Nächste Schritte für Sie

1. **Aktualisieren Sie die Skripte auf dem Pi**
2. **Führen Sie einmal die Diagnose aus**: `~/scripts/diagnose_rtspstream.sh`
3. **Wenn Probleme erkannt werden**: `~/scripts/fix_rtspstream.sh`
4. **Testen Sie das reguläre Update**: `~/scripts/update_modules.sh`
5. **Prüfen Sie die Logs**: `pm2 logs MagicMirror --lines 50`

### Backup-Strategie

Alle Skripte erstellen Backups vor Änderungen:
- `fix_rtspstream.sh`: ~/rtspstream_backups/MMM-RTSPStream_backup_TIMESTAMP.tar.gz
- `update_modules.sh`: ~/module_backups/magicmirror_modules_backup_TIMESTAMP.tar.gz

Wiederherstellung bei Bedarf:
```bash
cd ~/MagicMirror/modules
rm -rf MMM-RTSPStream
tar -xzf ~/rtspstream_backups/MMM-RTSPStream_backup_TIMESTAMP.tar.gz
pm2 restart MagicMirror
```

### Testing Empfehlungen

Nach der Reparatur testen Sie:
1. Stream wird im MagicMirror angezeigt
2. Keine Fehler in pm2 logs: `pm2 logs MagicMirror | grep -i error`
3. ffmpeg läuft: `ps aux | grep ffmpeg`
4. Port 9999 gebunden: `netstat -tuln | grep 9999`
5. RTSP-URL erreichbar: `ffmpeg -i 'rtsp://...' -f null - 2>&1 | head -n 20`

Bei weiteren Problemen konsultieren Sie die erweiterte Troubleshooting-Sektion in der README.
