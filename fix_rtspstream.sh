#!/usr/bin/env bash
# fix_rtspstream.sh
# Spezielles Reparaturskript für MMM-RTSPStream Probleme
# Dieses Skript behebt die häufigsten Probleme mit dem RTSPStream Modul

set -euo pipefail

# Konfiguration
MAGICMIRROR_DIR="/home/pi/MagicMirror"
RTSPSTREAM_DIR="$MAGICMIRROR_DIR/modules/MMM-RTSPStream"
PM2_PROCESS_NAME="MagicMirror"
LOG_FILE="$HOME/rtspstream_fix.log"

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }
log() { echo "$(timestamp) - $*" | tee -a "$LOG_FILE"; }

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log "=========================================="
log "RTSPStream Reparatur-Skript gestartet"
log "=========================================="

# Prüfe ob Modul existiert
if [ ! -d "$RTSPSTREAM_DIR" ]; then
  echo -e "${RED}ERROR: RTSPStream Modul nicht gefunden in $RTSPSTREAM_DIR${NC}"
  log "ERROR: RTSPStream directory does not exist"
  exit 1
fi

echo -e "${GREEN}✓ RTSPStream Modul gefunden${NC}"
log "RTSPStream module found at $RTSPSTREAM_DIR"

# Schritt 1: Stoppe MagicMirror
echo ""
echo -e "${YELLOW}[1/8] Stoppe MagicMirror...${NC}"
log "Stopping MagicMirror process..."
if pm2 list | grep -q "$PM2_PROCESS_NAME"; then
  pm2 stop "$PM2_PROCESS_NAME" 2>&1 | tee -a "$LOG_FILE" || log "pm2 stop failed or process not running"
  echo -e "${GREEN}✓ MagicMirror gestoppt${NC}"
else
  echo -e "${YELLOW}⚠ MagicMirror läuft nicht${NC}"
fi
sleep 2

# Schritt 2: Beende alle ffmpeg Prozesse
echo ""
echo -e "${YELLOW}[2/8] Beende alle ffmpeg Prozesse...${NC}"
log "Killing all ffmpeg processes..."

ffmpeg_killed=false
for pattern in "ffmpeg.*9999" "ffmpeg.*rtsp" "ffmpeg.*MMM-RTSPStream" "ffmpeg"; do
  if pgrep -f "$pattern" >/dev/null 2>&1; then
    ffmpeg_killed=true
    echo "  Beende ffmpeg Prozesse: $pattern"
    pkill -KILL -f "$pattern" 2>&1 | tee -a "$LOG_FILE" || true
  fi
done

if [ "$ffmpeg_killed" = true ]; then
  sleep 2
  echo -e "${GREEN}✓ ffmpeg Prozesse beendet${NC}"
else
  echo -e "${GREEN}✓ Keine ffmpeg Prozesse gefunden${NC}"
fi

# Schritt 3: Prüfe ffmpeg Installation
echo ""
echo -e "${YELLOW}[3/8] Prüfe ffmpeg Installation...${NC}"
log "Checking ffmpeg installation..."

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo -e "${RED}✗ ffmpeg nicht gefunden!${NC}"
  echo "  Installiere ffmpeg..."
  log "ffmpeg not found - installing..."
  sudo apt-get update -qq 2>&1 | tee -a "$LOG_FILE"
  sudo apt-get install -y ffmpeg 2>&1 | tee -a "$LOG_FILE"
  
  if command -v ffmpeg >/dev/null 2>&1; then
    echo -e "${GREEN}✓ ffmpeg erfolgreich installiert${NC}"
  else
    echo -e "${RED}✗ ffmpeg Installation fehlgeschlagen${NC}"
    log "ERROR: Failed to install ffmpeg"
    exit 1
  fi
else
  ffmpeg_version=$(ffmpeg -version 2>&1 | head -n 1)
  echo -e "${GREEN}✓ ffmpeg gefunden: $ffmpeg_version${NC}"
  log "ffmpeg found: $ffmpeg_version"
  
  # Prüfe RTSP Support
  if ffmpeg -formats 2>&1 | grep -q "rtsp"; then
    echo -e "${GREEN}  ✓ RTSP Support vorhanden${NC}"
  else
    echo -e "${YELLOW}  ⚠ RTSP Support möglicherweise nicht verfügbar${NC}"
    log "WARNING: ffmpeg may not have RTSP support"
  fi
  
  # Prüfe H.264 Support
  if ffmpeg -codecs 2>&1 | grep -q "h264"; then
    echo -e "${GREEN}  ✓ H.264 Codec vorhanden${NC}"
  else
    echo -e "${YELLOW}  ⚠ H.264 Codec möglicherweise nicht verfügbar${NC}"
    log "WARNING: ffmpeg may not have H.264 codec"
  fi
fi

# Schritt 4: Backup erstellen
echo ""
echo -e "${YELLOW}[4/8] Erstelle Backup...${NC}"
log "Creating backup of current installation..."

backup_dir="$HOME/rtspstream_backups"
mkdir -p "$backup_dir"
backup_file="$backup_dir/MMM-RTSPStream_backup_$(date +%Y%m%d_%H%M%S).tar.gz"

if tar -czf "$backup_file" -C "$MAGICMIRROR_DIR/modules" "MMM-RTSPStream" 2>&1 | tee -a "$LOG_FILE"; then
  echo -e "${GREEN}✓ Backup erstellt: $backup_file${NC}"
  log "Backup created: $backup_file"
else
  echo -e "${YELLOW}⚠ Backup fehlgeschlagen (fortfahren...)${NC}"
  log "WARNING: Backup failed, continuing anyway"
fi

# Schritt 5: Lösche alte Installation
echo ""
echo -e "${YELLOW}[5/8] Lösche alte Installation...${NC}"
log "Removing old installation..."

cd "$RTSPSTREAM_DIR"
rm -rf node_modules 2>&1 | tee -a "$LOG_FILE" || log "Failed to remove node_modules"
rm -f package-lock.json 2>&1 | tee -a "$LOG_FILE" || log "Failed to remove package-lock.json"
rm -rf /tmp/npm-* 2>/dev/null || true

echo -e "${GREEN}✓ Alte Installation entfernt${NC}"
log "Old installation removed"

# Schritt 6: Bereinige npm Cache
echo ""
echo -e "${YELLOW}[6/8] Bereinige npm Cache...${NC}"
log "Cleaning npm cache..."

if npm cache clean --force 2>&1 | tee -a "$LOG_FILE"; then
  echo -e "${GREEN}✓ npm Cache bereinigt${NC}"
else
  echo -e "${YELLOW}⚠ npm Cache Bereinigung fehlgeschlagen${NC}"
fi

# Schritt 7: Neuinstallation
echo ""
echo -e "${YELLOW}[7/8] Installiere RTSPStream neu...${NC}"
log "Reinstalling RTSPStream..."

cd "$RTSPSTREAM_DIR"

# Versuche verschiedene Installationsmethoden
install_success=false

echo "  Versuch 1: npm install"
if npm install 2>&1 | tee -a "$LOG_FILE"; then
  echo -e "${GREEN}✓ npm install erfolgreich${NC}"
  install_success=true
else
  echo -e "${YELLOW}✗ npm install fehlgeschlagen, versuche Alternative...${NC}"
  
  echo "  Versuch 2: npm ci"
  if [ -f "package-lock.json" ] && npm ci 2>&1 | tee -a "$LOG_FILE"; then
    echo -e "${GREEN}✓ npm ci erfolgreich${NC}"
    install_success=true
  else
    echo -e "${YELLOW}✗ npm ci fehlgeschlagen, versuche mit --force...${NC}"
    
    echo "  Versuch 3: npm install --force"
    if npm install --force 2>&1 | tee -a "$LOG_FILE"; then
      echo -e "${GREEN}✓ npm install --force erfolgreich${NC}"
      install_success=true
    else
      echo -e "${RED}✗ Alle Installationsversuche fehlgeschlagen${NC}"
      log "ERROR: All installation attempts failed"
    fi
  fi
fi

if [ "$install_success" = false ]; then
  echo ""
  echo -e "${RED}Installation fehlgeschlagen!${NC}"
  echo "Prüfe das Log: $LOG_FILE"
  exit 1
fi

# Setze Berechtigungen
echo "  Setze Berechtigungen..."
sudo chown -R pi:pi "$RTSPSTREAM_DIR" 2>&1 | tee -a "$LOG_FILE" || log "chown failed"

# Schritt 8: Verifiziere Installation
echo ""
echo -e "${YELLOW}[8/8] Verifiziere Installation...${NC}"
log "Verifying installation..."

verification_ok=true

# Prüfe node_helper.js
if [ -f "$RTSPSTREAM_DIR/node_helper.js" ]; then
  echo -e "${GREEN}  ✓ node_helper.js vorhanden${NC}"
else
  echo -e "${RED}  ✗ node_helper.js fehlt${NC}"
  verification_ok=false
fi

# Prüfe kritische Dependencies
echo "  Prüfe kritische Dependencies..."
for dep in "datauri" "node-ffmpeg-stream" "express"; do
  if [ -d "$RTSPSTREAM_DIR/node_modules/$dep" ] || node -e "require('$dep')" 2>/dev/null; then
    echo -e "${GREEN}    ✓ $dep vorhanden${NC}"
  else
    echo -e "${RED}    ✗ $dep fehlt${NC}"
    verification_ok=false
  fi
done

# Test: ffmpeg von Node.js aus
echo "  Teste ffmpeg Zugriff von Node.js..."
test_cmd="const { spawn } = require('child_process'); const proc = spawn('ffmpeg', ['-version']); proc.on('close', (code) => { process.exit(code); });"
if node -e "$test_cmd" 2>&1 | tee -a "$LOG_FILE"; then
  echo -e "${GREEN}  ✓ ffmpeg von Node.js erreichbar${NC}"
else
  echo -e "${YELLOW}  ⚠ ffmpeg möglicherweise nicht von Node.js erreichbar${NC}"
  log "WARNING: ffmpeg may not be accessible from Node.js context"
  verification_ok=false
fi

# Test: datauri Modul
echo "  Teste datauri Modul..."
test_cmd="try { require('datauri'); console.log('OK'); process.exit(0); } catch(e) { console.error(e.message); process.exit(1); }"
if cd "$RTSPSTREAM_DIR" && node -e "$test_cmd" 2>&1 | tee -a "$LOG_FILE"; then
  echo -e "${GREEN}  ✓ datauri Modul lädt erfolgreich${NC}"
else
  echo -e "${RED}  ✗ datauri Modul kann nicht geladen werden${NC}"
  log "ERROR: datauri module cannot be loaded"
  verification_ok=false
fi

echo ""
echo "=========================================="
if [ "$verification_ok" = true ]; then
  echo -e "${GREEN}✓ RTSPStream erfolgreich repariert!${NC}"
  log "RTSPStream successfully repaired"
  
  # Starte MagicMirror neu
  echo ""
  echo -e "${YELLOW}Starte MagicMirror neu...${NC}"
  pm2 restart "$PM2_PROCESS_NAME" 2>&1 | tee -a "$LOG_FILE"
  sleep 3
  
  echo ""
  echo -e "${GREEN}Fertig! Prüfe den Status mit:${NC}"
  echo "  pm2 logs $PM2_PROCESS_NAME --lines 50"
  echo ""
  echo "Oder öffne MagicMirror im Browser und prüfe ob der Stream angezeigt wird."
else
  echo -e "${YELLOW}⚠ Installation abgeschlossen, aber einige Probleme wurden erkannt${NC}"
  echo "Prüfe das Log für Details: $LOG_FILE"
  log "Installation completed with warnings"
  
  # Starte trotzdem neu
  echo ""
  echo "Starte MagicMirror trotzdem neu..."
  pm2 restart "$PM2_PROCESS_NAME" 2>&1 | tee -a "$LOG_FILE"
fi

echo "=========================================="
echo ""
echo "Log-Datei: $LOG_FILE"
echo "Backup: $backup_file"
echo ""

log "Script finished"
