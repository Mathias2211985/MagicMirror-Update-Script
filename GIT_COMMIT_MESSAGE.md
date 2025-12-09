# Git Commit Message für die Änderungen

## Empfohlener Commit:

```
Fix: Erweiterte RTSPStream-Unterstützung und Reparatur-Tools

Problem:
- RTSPStream wird nach Updates nicht mehr angezeigt
- ffmpeg-Prozesse blockieren Installation
- Dependencies fehlen nach npm-Installation
- Schwer zu diagnostizieren welches Problem vorliegt

Lösungen:

1. update_modules.sh - Verbesserungen:
   - Erweiterte ffmpeg-Prozess-Erkennung (mehrere Muster)
   - Doppelte Überprüfung vor/nach Installation
   - Verbesserte npm-Cache-Bereinigung inkl. /tmp/npm-*
   - Zusätzliche Dependency-Checks (url, fs, path)
   - npm install --force Fallback bei Fehlern
   - Erweiterte ffmpeg-Diagnose (PATH, Berechtigungen)

2. Neu: fix_rtspstream.sh
   - Automatisches Reparatur-Skript (8 Schritte)
   - Beendet alle ffmpeg-Prozesse (mehrere Muster)
   - Prüft/installiert ffmpeg mit RTSP/H.264 Support
   - Erstellt Backup vor Änderungen
   - Komplette Neuinstallation mit Fallback-Strategien
   - Verifiziert Installation und Dependencies
   - Farbige Konsolen-Ausgabe und detailliertes Logging

3. Neu: diagnose_rtspstream.sh
   - Umfassende Diagnose in 8 Kategorien
   - Keine System-Änderungen (read-only)
   - Prüft Modul, Dependencies, ffmpeg, Prozesse, Config, Netzwerk
   - Zeigt Zusammenfassung mit erkannten Problemen
   - Lösungsvorschläge am Ende

4. README.md Erweiterungen:
   - Neue Sektion: RTSPStream Spezial-Skripte
   - Häufige Probleme und Lösungen (7 Szenarien)
   - Schritt-für-Schritt Anleitungen
   - Verbesserte Troubleshooting-Sektion

5. Neue Dokumentation:
   - CHANGELOG_RTSPSTREAM.md: Detaillierte Beschreibung aller Änderungen
   - QUICKSTART_FIX.md: Schritt-für-Schritt Anleitung für sofortige Problemlösung

Getestet:
- ffmpeg-Prozess-Erkennung und -Beendigung
- npm-Installation mit verschiedenen Fallback-Strategien
- Diagnose-Skript auf System ohne Probleme
- Reparatur-Skript mit simulierten Problemen

Dateien geändert:
- update_modules.sh (erweitert)
- fix_rtspstream.sh (neu)
- diagnose_rtspstream.sh (neu)
- README.md (erweitert)
- CHANGELOG_RTSPSTREAM.md (neu)
- QUICKSTART_FIX.md (neu)
- GIT_COMMIT_MESSAGE.md (neu - diese Datei)
```

## Alternative kürzere Version:

```
Fix: RTSPStream-Probleme nach Updates beheben

- Erweiterte ffmpeg-Prozess-Erkennung und -Beendigung
- Verbesserte npm-Installation mit Fallback-Strategien
- Neue Reparatur-Tools: fix_rtspstream.sh und diagnose_rtspstream.sh
- Erweiterte Dokumentation mit Troubleshooting-Guide

Behebt: RTSPStream zeigt nach automatischen Updates keinen Stream mehr an
```

## Git-Befehle zum Committen:

```bash
# Alle Änderungen stagen
git add update_modules.sh fix_rtspstream.sh diagnose_rtspstream.sh README.md CHANGELOG_RTSPSTREAM.md QUICKSTART_FIX.md GIT_COMMIT_MESSAGE.md

# Commit mit ausführlicher Message
git commit -F GIT_COMMIT_MESSAGE.md

# Oder mit kurzer Message
git commit -m "Fix: RTSPStream-Probleme nach Updates beheben" -m "Erweiterte ffmpeg-Prozess-Erkennung, neue Reparatur-Tools, verbesserte Dokumentation"

# Zum Repository pushen
git push origin master
```

## Hinweis für GitHub Release:

Wenn Sie ein Release erstellen möchten:

**Tag**: v2.1.0 (oder Ihre Versionsnummer)
**Release Title**: Erweiterte RTSPStream-Unterstützung
**Description**: 

```markdown
## 🎉 Neue Features

### RTSPStream Reparatur-Tools
- `fix_rtspstream.sh` - Automatische Reparatur von RTSPStream-Problemen
- `diagnose_rtspstream.sh` - Umfassende Diagnose des RTSPStream-Status

### Verbesserungen
- Erweiterte ffmpeg-Prozess-Erkennung (mehrere Muster)
- Robustere npm-Installation mit automatischen Fallbacks
- Verbesserte Post-Install-Checks für Dependencies
- Detaillierte Fehlermeldungen und Logging

## 📚 Dokumentation
- Neue [Schnellanleitung](QUICKSTART_FIX.md) für sofortige Problemlösung
- Ausführliches [Changelog](CHANGELOG_RTSPSTREAM.md) mit allen Details
- Erweiterte [README](README.md) mit Troubleshooting-Guide

## 🐛 Bug Fixes
- RTSPStream zeigt nach Updates keinen Stream mehr an
- ffmpeg-Zombie-Prozesse blockieren Installation
- Fehlende Dependencies nach npm-Installation

## 🚀 Installation
Siehe [QUICKSTART_FIX.md](QUICKSTART_FIX.md) für detaillierte Anweisungen.
```
