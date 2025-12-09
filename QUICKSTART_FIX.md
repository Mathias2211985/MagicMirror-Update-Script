# Schnellanleitung: RTSPStream-Problem beheben

## Schritt 1: Aktualisierte Skripte auf den Pi kopieren

Öffnen Sie auf Ihrem Windows-PC PowerShell und führen Sie aus:

```powershell
# Navigieren Sie zum Skript-Verzeichnis
cd "C:\Users\mathi\OneDrive\Dokumente\GitHub\MagicMirror-Update-Script"

# Kopieren Sie alle Skripte auf den Raspberry Pi
scp update_modules.sh fix_rtspstream.sh diagnose_rtspstream.sh pi@raspberrypi:/home/pi/scripts/
```

Falls das scripts-Verzeichnis noch nicht existiert:
```powershell
ssh pi@raspberrypi "mkdir -p /home/pi/scripts"
```

## Schritt 2: Verbinden Sie sich mit dem Raspberry Pi

```powershell
ssh pi@raspberrypi
```

## Schritt 3: Skripte ausführbar machen

```bash
chmod +x ~/scripts/update_modules.sh
chmod +x ~/scripts/fix_rtspstream.sh
chmod +x ~/scripts/diagnose_rtspstream.sh
```

## Schritt 4: Diagnose durchführen

Führen Sie das Diagnose-Skript aus, um den aktuellen Zustand zu prüfen:

```bash
~/scripts/diagnose_rtspstream.sh
```

Das Skript zeigt Ihnen:
- ✓ = Alles OK (grün)
- ⚠ = Warnung (gelb)
- ✗ = Problem gefunden (rot)

## Schritt 5: Reparatur durchführen

Wenn Probleme gefunden wurden, führen Sie die automatische Reparatur aus:

```bash
~/scripts/fix_rtspstream.sh
```

Das Skript wird:
1. MagicMirror stoppen
2. Alle ffmpeg-Prozesse beenden
3. ffmpeg prüfen/installieren
4. Ein Backup erstellen
5. RTSPStream komplett neu installieren
6. Die Installation verifizieren
7. MagicMirror neu starten

## Schritt 6: Ergebnis überprüfen

Nach der Reparatur prüfen Sie:

```bash
# Logs anzeigen (letzte 50 Zeilen)
pm2 logs MagicMirror --lines 50

# Speziell nach RTSPStream suchen
pm2 logs MagicMirror --lines 100 | grep -i rtsp

# Status prüfen
pm2 status
```

Öffnen Sie MagicMirror im Browser und prüfen Sie, ob der Stream angezeigt wird.

## Alternative: Manuelle Schnell-Reparatur

Falls Sie die Skripte nicht verwenden möchten, können Sie auch manuell reparieren:

```bash
# MagicMirror stoppen
pm2 stop MagicMirror

# Alle ffmpeg-Prozesse beenden
pkill -KILL -f "ffmpeg"

# RTSPStream neu installieren
cd /home/pi/MagicMirror/modules/MMM-RTSPStream
rm -rf node_modules package-lock.json
npm cache clean --force
rm -rf /tmp/npm-*
npm install
sudo chown -R pi:pi .

# MagicMirror neu starten
pm2 restart MagicMirror
pm2 logs MagicMirror --lines 50
```

## Wichtige Hinweise

1. **Backup**: Das Reparatur-Skript erstellt automatisch ein Backup in `~/rtspstream_backups/`

2. **Logs**: Alle Aktionen werden geloggt:
   - Reparatur: `~/rtspstream_fix.log`
   - Updates: `~/update_modules.log`

3. **RTSP-URL prüfen**: Stellen Sie sicher, dass Ihre RTSP-URL in der `config.js` korrekt ist

4. **Cron-Job**: Wenn Sie Cron verwenden, wird das verbesserte update_modules.sh automatisch die neuen Checks ausführen

## Bei weiteren Problemen

Falls der Stream immer noch nicht funktioniert:

1. **ffmpeg manuell testen**:
   ```bash
   ffmpeg -i 'rtsp://ihre-kamera-ip:554/stream' -f null -
   ```

2. **Kamera erreichbar prüfen**:
   ```bash
   ping ihre-kamera-ip
   ```

3. **Port 9999 prüfen**:
   ```bash
   netstat -tuln | grep 9999
   ```

4. **Komplette Neuinstallation des Moduls**:
   ```bash
   cd /home/pi/MagicMirror/modules
   rm -rf MMM-RTSPStream
   git clone https://github.com/shbatm/MMM-RTSPStream.git
   cd MMM-RTSPStream
   npm install
   pm2 restart MagicMirror
   ```

5. **Konsultieren Sie die erweiterte README**: Alle Dateien enthalten nun detaillierte Troubleshooting-Informationen

## Fragen?

Alle Details zu den Änderungen finden Sie in:
- `README.md` - Hauptdokumentation mit Troubleshooting
- `CHANGELOG_RTSPSTREAM.md` - Detaillierte Beschreibung aller Verbesserungen
- Inline-Kommentare in den Skripten

Viel Erfolg! 🎉
