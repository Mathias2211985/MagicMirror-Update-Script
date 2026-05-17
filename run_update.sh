#!/usr/bin/env bash
# run_update.sh
# Wrapper um update_modules.sh:
# Sichert custom-Moduldateien, führt Update durch, stellt sie danach wieder her.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MM_DIR="$HOME/MagicMirror"
BACKUP_DIR="$HOME/scripts/custom_overrides"

# --- Liste der zu schützenden Dateien (Pfad relativ zu MM_DIR) ---
PROTECTED_FILES=(
  "modules/MMM-WetterOnline-other-Color/node_helper.js"
  "modules/MMM-WetterOnline-other-Color/MMM-WetterOnline-other-Color.js"
)

echo "=== MagicMirror Update-Wrapper ==="
echo "$(date)"

# 1) Custom-Dateien sichern
echo ""
echo "[1/4] Sichere custom Dateien nach $BACKUP_DIR ..."
mkdir -p "$BACKUP_DIR"
for rel_path in "${PROTECTED_FILES[@]}"; do
  src="$MM_DIR/$rel_path"
  dst="$BACKUP_DIR/$(echo "$rel_path" | tr '/' '__')"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    echo "  ✓ Gesichert: $rel_path"
  else
    echo "  ! Nicht gefunden: $src"
  fi
done

# 2) Update-Script ausführen
# Temporäre Config: internen Neustart deaktivieren, damit nur WIR neu starten
# (nach dem Restore der custom Dateien – sonst läuft MM kurz mit falschen Modulen)
TEMP_CONF=$(mktemp /tmp/mm_update_XXXX.conf)
cat > "$TEMP_CONF" <<'EOF'
RESTART_AFTER_UPDATES=false
AUTO_REBOOT_AFTER_SCRIPT=false
AUTO_REBOOT_AFTER_UPGRADE=false
EOF

echo ""
echo "[2/4] Starte update_modules.sh (interner Neustart deaktiviert) ..."
bash "$SCRIPT_DIR/update_modules.sh" --config "$TEMP_CONF" || true
rm -f "$TEMP_CONF"

# 3) Custom-Dateien zurückkopieren
echo ""
echo "[3/4] Stelle custom Dateien wieder her ..."
for rel_path in "${PROTECTED_FILES[@]}"; do
  src="$BACKUP_DIR/$(echo "$rel_path" | tr '/' '__')"
  dst="$MM_DIR/$rel_path"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    echo "  ✓ Wiederhergestellt: $rel_path"
  else
    echo "  ! Backup nicht gefunden: $src"
  fi
done

# 4) MagicMirror neu starten
echo ""
echo "[4/4] Starte MagicMirror neu ..."
pkill -f "electron js/electron" 2>/dev/null || true
sleep 2
nohup bash "$HOME/start-mm.sh" > /tmp/mm.log 2>&1 &
echo "  ✓ MagicMirror gestartet (PID: $!)"

echo ""
echo "=== Fertig ==="
