#!/usr/bin/env bash
# diagnose_rtspstream.sh
# Diagnoseskript für MMM-RTSPStream
# Sammelt alle relevanten Informationen über den aktuellen Zustand

set -euo pipefail

# Konfiguration
MAGICMIRROR_DIR="/home/pi/MagicMirror"
RTSPSTREAM_DIR="$MAGICMIRROR_DIR/modules/MMM-RTSPStream"
CONFIG_FILE="$MAGICMIRROR_DIR/config/config.js"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  RTSPStream Diagnose${NC}"
echo -e "${BLUE}  $(date)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. Prüfe Modul-Installation
echo -e "${YELLOW}[1] Modul-Installation${NC}"
echo "---"
if [ -d "$RTSPSTREAM_DIR" ]; then
  echo -e "${GREEN}✓ RTSPStream Verzeichnis existiert${NC}"
  echo "  Pfad: $RTSPSTREAM_DIR"
  
  if [ -f "$RTSPSTREAM_DIR/node_helper.js" ]; then
    echo -e "${GREEN}✓ node_helper.js vorhanden${NC}"
  else
    echo -e "${RED}✗ node_helper.js fehlt!${NC}"
  fi
  
  if [ -f "$RTSPSTREAM_DIR/MMM-RTSPStream.js" ]; then
    echo -e "${GREEN}✓ MMM-RTSPStream.js vorhanden${NC}"
  else
    echo -e "${RED}✗ MMM-RTSPStream.js fehlt!${NC}"
  fi
  
  if [ -f "$RTSPSTREAM_DIR/package.json" ]; then
    echo -e "${GREEN}✓ package.json vorhanden${NC}"
    version=$(grep -oP '"version":\s*"\K[^"]+' "$RTSPSTREAM_DIR/package.json" 2>/dev/null || echo "unbekannt")
    echo "  Version: $version"
  else
    echo -e "${RED}✗ package.json fehlt!${NC}"
  fi
  
  # Git Status
  if [ -d "$RTSPSTREAM_DIR/.git" ]; then
    echo -e "${GREEN}✓ Git Repository${NC}"
    cd "$RTSPSTREAM_DIR"
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unbekannt")
    commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unbekannt")
    echo "  Branch: $branch"
    echo "  Commit: $commit"
    
    # Lokale Änderungen?
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
      echo -e "${YELLOW}  ⚠ Lokale Änderungen vorhanden${NC}"
    else
      echo -e "${GREEN}  ✓ Keine lokalen Änderungen${NC}"
    fi
  else
    echo -e "${YELLOW}⚠ Kein Git Repository${NC}"
  fi
else
  echo -e "${RED}✗ RTSPStream Verzeichnis nicht gefunden!${NC}"
  echo "  Erwartet: $RTSPSTREAM_DIR"
  exit 1
fi

echo ""

# 2. Prüfe node_modules
echo -e "${YELLOW}[2] Node Dependencies${NC}"
echo "---"
if [ -d "$RTSPSTREAM_DIR/node_modules" ]; then
  echo -e "${GREEN}✓ node_modules Verzeichnis vorhanden${NC}"
  
  # Anzahl installierter Pakete
  pkg_count=$(find "$RTSPSTREAM_DIR/node_modules" -maxdepth 1 -type d | wc -l)
  echo "  Installierte Pakete: $((pkg_count - 1))"
  
  # Kritische Dependencies prüfen
  echo ""
  echo "  Kritische Dependencies:"
  critical_deps=("datauri" "node-ffmpeg-stream" "express" "url" "fs" "path")
  all_ok=true
  
  for dep in "${critical_deps[@]}"; do
    if [ -d "$RTSPSTREAM_DIR/node_modules/$dep" ]; then
      echo -e "${GREEN}    ✓ $dep${NC}"
    elif node -e "require('$dep')" 2>/dev/null; then
      echo -e "${GREEN}    ✓ $dep (built-in)${NC}"
    else
      echo -e "${RED}    ✗ $dep fehlt!${NC}"
      all_ok=false
    fi
  done
  
  if [ "$all_ok" = true ]; then
    echo -e "${GREEN}  ✓ Alle kritischen Dependencies vorhanden${NC}"
  else
    echo -e "${RED}  ✗ Einige Dependencies fehlen!${NC}"
  fi
  
  # package-lock.json
  if [ -f "$RTSPSTREAM_DIR/package-lock.json" ]; then
    echo -e "${GREEN}  ✓ package-lock.json vorhanden${NC}"
  else
    echo -e "${YELLOW}  ⚠ package-lock.json fehlt${NC}"
  fi
else
  echo -e "${RED}✗ node_modules Verzeichnis fehlt!${NC}"
  echo "  npm install wurde nicht ausgeführt oder fehlgeschlagen"
fi

echo ""

# 3. Prüfe ffmpeg
echo -e "${YELLOW}[3] ffmpeg${NC}"
echo "---"
if command -v ffmpeg >/dev/null 2>&1; then
  echo -e "${GREEN}✓ ffmpeg gefunden${NC}"
  ffmpeg_path=$(which ffmpeg)
  echo "  Pfad: $ffmpeg_path"
  
  # Version
  ffmpeg_version=$(ffmpeg -version 2>&1 | head -n 1)
  echo "  Version: $ffmpeg_version"
  
  # Berechtigungen
  ls -la "$ffmpeg_path"
  
  # RTSP Support
  if ffmpeg -formats 2>&1 | grep -q "rtsp"; then
    echo -e "${GREEN}  ✓ RTSP Support vorhanden${NC}"
  else
    echo -e "${RED}  ✗ RTSP Support fehlt!${NC}"
  fi
  
  # H.264 Codec
  if ffmpeg -codecs 2>&1 | grep -q "h264"; then
    echo -e "${GREEN}  ✓ H.264 Codec vorhanden${NC}"
  else
    echo -e "${RED}  ✗ H.264 Codec fehlt!${NC}"
  fi
  
  # Test von Node.js aus
  echo ""
  echo "  Test: ffmpeg von Node.js..."
  test_cmd="const { spawn } = require('child_process'); const proc = spawn('ffmpeg', ['-version']); proc.on('exit', (code) => { process.exit(code); });"
  if node -e "$test_cmd" 2>/dev/null; then
    echo -e "${GREEN}  ✓ ffmpeg von Node.js erreichbar${NC}"
  else
    echo -e "${RED}  ✗ ffmpeg nicht von Node.js erreichbar!${NC}"
  fi
else
  echo -e "${RED}✗ ffmpeg nicht gefunden!${NC}"
  echo "  Installiere mit: sudo apt-get install -y ffmpeg"
fi

echo ""

# 4. Prüfe laufende Prozesse
echo -e "${YELLOW}[4] Laufende Prozesse${NC}"
echo "---"

# MagicMirror
if pgrep -f "node.*MagicMirror" >/dev/null 2>&1; then
  echo -e "${GREEN}✓ MagicMirror läuft${NC}"
  pgrep -af "node.*MagicMirror"
else
  echo -e "${YELLOW}⚠ MagicMirror läuft nicht${NC}"
fi

echo ""

# ffmpeg Prozesse
if pgrep -f "ffmpeg" >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠ ffmpeg Prozesse gefunden:${NC}"
  pgrep -af "ffmpeg"
  
  # RTSPStream-spezifische Prozesse
  if pgrep -f "ffmpeg.*9999" >/dev/null 2>&1; then
    echo -e "${GREEN}  ✓ RTSPStream ffmpeg Prozesse (Port 9999) gefunden${NC}"
  fi
else
  echo -e "${YELLOW}⚠ Keine ffmpeg Prozesse gefunden${NC}"
  echo "  (Normal wenn Stream gerade nicht läuft)"
fi

echo ""

# pm2
if command -v pm2 >/dev/null 2>&1; then
  echo "pm2 Status:"
  pm2 list 2>/dev/null || echo "  pm2 list fehlgeschlagen"
else
  echo -e "${YELLOW}⚠ pm2 nicht gefunden${NC}"
fi

echo ""

# 5. Prüfe Config
echo -e "${YELLOW}[5] Konfiguration${NC}"
echo "---"
if [ -f "$CONFIG_FILE" ]; then
  echo -e "${GREEN}✓ config.js gefunden${NC}"
  echo "  Pfad: $CONFIG_FILE"
  
  # Suche RTSPStream Konfiguration
  if grep -q "MMM-RTSPStream" "$CONFIG_FILE"; then
    echo -e "${GREEN}  ✓ RTSPStream in config.js konfiguriert${NC}"
    
    # Zeige Konfiguration (vereinfacht)
    echo ""
    echo "  RTSPStream Konfiguration:"
    grep -A 20 "module:.*MMM-RTSPStream" "$CONFIG_FILE" | head -n 25 || echo "    (Konnte Konfiguration nicht extrahieren)"
  else
    echo -e "${RED}  ✗ RTSPStream nicht in config.js gefunden!${NC}"
    echo "    Modul muss zur Konfiguration hinzugefügt werden"
  fi
else
  echo -e "${RED}✗ config.js nicht gefunden!${NC}"
  echo "  Erwartet: $CONFIG_FILE"
fi

echo ""

# 6. Prüfe Netzwerk
echo -e "${YELLOW}[6] Netzwerk${NC}"
echo "---"

# Port 9999 (RTSPStream Standard)
if netstat -tuln 2>/dev/null | grep -q ":9999"; then
  echo -e "${GREEN}✓ Port 9999 ist gebunden${NC}"
  netstat -tuln | grep ":9999"
else
  echo -e "${YELLOW}⚠ Port 9999 ist nicht gebunden${NC}"
  echo "  (Normal wenn Stream gerade nicht läuft)"
fi

echo ""

# Allgemeine Netzwerk-Info
echo "Netzwerk-Interfaces:"
ip addr show | grep -E "^[0-9]+:|inet " | head -n 10

echo ""

# 7. System-Info
echo -e "${YELLOW}[7] System${NC}"
echo "---"

# Node.js Version
if command -v node >/dev/null 2>&1; then
  node_version=$(node --version)
  echo -e "${GREEN}✓ Node.js: $node_version${NC}"
else
  echo -e "${RED}✗ Node.js nicht gefunden!${NC}"
fi

# npm Version
if command -v npm >/dev/null 2>&1; then
  npm_version=$(npm --version)
  echo -e "${GREEN}✓ npm: $npm_version${NC}"
else
  echo -e "${RED}✗ npm nicht gefunden!${NC}"
fi

# OS Info
if [ -f /etc/os-release ]; then
  . /etc/os-release
  echo "Betriebssystem: $PRETTY_NAME"
fi

# Raspberry Pi Modell
if [ -f /proc/device-tree/model ]; then
  pi_model=$(cat /proc/device-tree/model | tr -d '\0')
  echo "Hardware: $pi_model"
fi

# Speicher
echo ""
echo "Speicher:"
free -h

echo ""

# 8. Letzte Logs
echo -e "${YELLOW}[8] Letzte Log-Einträge${NC}"
echo "---"

# pm2 logs
if command -v pm2 >/dev/null 2>&1 && pm2 list | grep -q "MagicMirror"; then
  echo "Letzte pm2 Logs (RTSPStream relevant):"
  echo "---"
  pm2 logs MagicMirror --nostream --lines 30 2>/dev/null | grep -i -E "rtsp|ffmpeg|stream" | tail -n 15 || echo "  Keine relevanten Logs gefunden"
fi

echo ""

# Update Script Log
if [ -f "$HOME/update_modules.log" ]; then
  echo "Letzte Update-Script Logs (RTSPStream):"
  echo "---"
  grep -i -E "rtspstream|ffmpeg" "$HOME/update_modules.log" | tail -n 10 || echo "  Keine relevanten Logs gefunden"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Diagnose abgeschlossen${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Zusammenfassung
echo -e "${YELLOW}Zusammenfassung:${NC}"
issues_found=false

if [ ! -d "$RTSPSTREAM_DIR/node_modules" ]; then
  echo -e "${RED}✗ node_modules fehlt - npm install ausführen${NC}"
  issues_found=true
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo -e "${RED}✗ ffmpeg fehlt - installieren${NC}"
  issues_found=true
fi

if [ -f "$CONFIG_FILE" ] && ! grep -q "MMM-RTSPStream" "$CONFIG_FILE"; then
  echo -e "${RED}✗ RTSPStream nicht in config.js konfiguriert${NC}"
  issues_found=true
fi

if [ "$issues_found" = false ]; then
  echo -e "${GREEN}✓ Keine offensichtlichen Probleme gefunden${NC}"
  echo ""
  echo "Wenn der Stream trotzdem nicht funktioniert:"
  echo "1. Prüfe die RTSP-URL in der Konfiguration"
  echo "2. Teste die RTSP-URL direkt mit: ffmpeg -i 'rtsp://...' -f null -"
  echo "3. Prüfe die Logs: pm2 logs MagicMirror"
  echo "4. Führe Reparatur aus: ./fix_rtspstream.sh"
fi

echo ""
