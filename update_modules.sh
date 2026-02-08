#!/usr/bin/env bash
# update_modules.sh
# Durchsucht das modules-Verzeichnis und führt für jedes Modul:
# - git pull (wenn .git vorhanden & keine lokalen Änderungen)
# - npm install (wenn package.json vorhanden)
# Optional: Neustart des pm2-Prozesses wenn Updates erfolgten

# Only exit on undefined variables, but allow commands to fail
# This makes the script robust for cron jobs - individual module failures won't stop the whole script
set -u
IFS=$'\n\t'

# Set PATH for cron compatibility - ensures git, node, npm are found
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin:$PATH"

# Set TMPDIR if not set (required by nvm and some npm operations)
export TMPDIR="${TMPDIR:-/tmp}"

# Lockfile to prevent parallel execution
LOCKFILE="/tmp/update_modules.lock"
if [ -f "$LOCKFILE" ]; then
  lock_pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
  if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
    echo "Another instance is already running (PID: $lock_pid). Exiting."
    exit 1
  else
    echo "Removing stale lockfile"
    rm -f "$LOCKFILE"
  fi
fi
echo $$ > "$LOCKFILE"

# Temporary file to track updates from subshells (created early)
MODULE_UPDATE_TRACKER=$(mktemp)
echo "0" > "$MODULE_UPDATE_TRACKER"

# Cleanup function for lockfile and temp files
cleanup_temp_files() {
  rm -f "$LOCKFILE" "$MODULE_UPDATE_TRACKER" 2>/dev/null || true
}

# Load nvm if available (needed for cron jobs)
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  source "$NVM_DIR/nvm.sh" || true
fi

# --- Konfiguration (anpassen) ---
# Diese Werte können auch in einer externen Konfigurationsdatei überschrieben werden:
# $HOME/.config/magicmirror-update/config.sh oder /etc/magicmirror-update.conf

MODULES_DIR="/home/pi/MagicMirror/modules"   # Pfad zum modules-Ordner (z. B. /home/pi/MagicMirror/modules)
MAGICMIRROR_DIR="/home/pi/MagicMirror"       # Pfad zum MagicMirror-Hauptverzeichnis
PM2_PROCESS_NAME="MagicMirror"               # Name des pm2 Prozesses (z. B. 'MagicMirror')
UPDATE_MAGICMIRROR_CORE=true                 # true = update MagicMirror core before updating modules
RESTART_AFTER_UPDATES=true                   # true = restart pm2 process wenn Updates vorhanden
DRY_RUN=false                                # true = nur berichten, nichts verändern
AUTO_DISCARD_LOCAL=true                       # true = automatisch lokale Änderungen verwerfen (reset --hard + clean) - DESTRUKTIV
LOG_FILE="$HOME/update_modules.log"
RUN_RASPBIAN_UPDATE=true                      # true = run apt-get full-upgrade on the Raspberry Pi after module updates (requires sudo or root)
MAKE_MODULE_BACKUP=true                       # true = create a tar.gz backup of the modules directory before apt upgrade
AUTO_REBOOT_AFTER_UPGRADE=true               # true = reboot automatically after apt full-upgrade if required
AUTO_REBOOT_AFTER_SCRIPT=true               # true = reboot the Pi after EVERY script run. false = only reboot when updates were installed. DRY_RUN overrides this.
APT_UPDATE_MAX_ATTEMPTS=4                      # how many times to retry apt when dpkg/apt lock is present
BACKUP_DIR="$HOME/module_backups"            # where to store module backups
REBOOT_ONLY_ON_UPDATES=true                  # true = only reboot if updates were actually installed (more intelligent than AUTO_REBOOT_AFTER_SCRIPT)

# --- E-Mail Benachrichtigungen ---
EMAIL_ENABLED=true                          # true = E-Mail bei kritischen Fehlern senden
EMAIL_RECIPIENT="mathiasbusch@live.de"                            # E-Mail-Adresse für Benachrichtigungen (z.B. "user@example.com")
EMAIL_SUBJECT_PREFIX="[MagicMirror Update]"  # Betreff-Präfix für E-Mails
EMAIL_ON_SUCCESS=true                       # true = auch bei erfolgreichen Updates E-Mail senden
EMAIL_ON_ERROR=true                          # true = bei Fehlern E-Mail senden

# --- E-Mail Log-Anhang ---
EMAIL_ATTACH_LOG=true                      # true = Log-Datei als Anhang senden (mail/msmtp/sendmail erforderlich)

# --- Log-Rotation ---
LOG_ROTATION_ENABLED=true                    # true = alte Logs automatisch rotieren
LOG_MAX_SIZE_KB=5120                         # maximale Log-Größe in KB bevor rotiert wird (5MB)
LOG_KEEP_COUNT=5                             # Anzahl der alten Logs die behalten werden

# --- Healthcheck ---
HEALTHCHECK_BEFORE_REBOOT=true              # true = MagicMirror testen bevor Reboot
HEALTHCHECK_TIMEOUT=30                       # Sekunden warten auf MagicMirror-Start
HEALTHCHECK_URL="http://localhost:8080"      # URL zum Testen ob MagicMirror läuft

# --- Externe Konfigurationsdatei laden (überschreibt obige Werte) ---
CONFIG_FILE_USER="$HOME/.config/magicmirror-update/config.sh"
CONFIG_FILE_SYSTEM="/etc/magicmirror-update.conf"

if [ -f "$CONFIG_FILE_USER" ]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE_USER"
  echo "Loaded user config from $CONFIG_FILE_USER"
elif [ -f "$CONFIG_FILE_SYSTEM" ]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE_SYSTEM"
  echo "Loaded system config from $CONFIG_FILE_SYSTEM"
fi

# -- Spezialfälle: manche Module sollen mit anderem npm-Befehl aktualisiert werden.
# Hier per Modulname anpassen. Beispiel: MMM-Webuntis braucht `npm ci --omit=dev`.
# Ein einfacher case-Block wird pro Modul verwendet.
# Wenn kein Eintrag vorhanden, nutzt das Skript das Standardverhalten (npm ci wenn lockfile, sonst npm install).
# ---------------------------------

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }
log() { echo "$(timestamp) - $*" | tee -a "$LOG_FILE"; }

# --- Log-Rotation Funktion ---
rotate_logs() {
  if [ "$LOG_ROTATION_ENABLED" != true ]; then
    return 0
  fi
  
  if [ ! -f "$LOG_FILE" ]; then
    return 0
  fi
  
  # Prüfe Log-Größe in KB
  local log_size_kb
  log_size_kb=$(du -k "$LOG_FILE" 2>/dev/null | cut -f1 || echo "0")
  
  if [ "$log_size_kb" -ge "$LOG_MAX_SIZE_KB" ]; then
    echo "$(timestamp) - Log rotation triggered (size: ${log_size_kb}KB >= ${LOG_MAX_SIZE_KB}KB)"
    
    # Alte Logs verschieben
    for i in $(seq $((LOG_KEEP_COUNT - 1)) -1 1); do
      if [ -f "${LOG_FILE}.$i" ]; then
        mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i + 1))" 2>/dev/null || true
      fi
    done
    
    # Aktuelles Log archivieren
    if [ -f "$LOG_FILE" ]; then
      cp "$LOG_FILE" "${LOG_FILE}.1"
      # Log-Datei leeren aber behalten
      : > "$LOG_FILE"
      echo "$(timestamp) - Log rotated (previous log: ${LOG_FILE}.1)" >> "$LOG_FILE"
    fi
    
    # Überzählige Logs löschen
    local count=$((LOG_KEEP_COUNT + 1))
    while [ -f "${LOG_FILE}.$count" ]; do
      rm -f "${LOG_FILE}.$count"
      count=$((count + 1))
    done
    
    # Auch komprimierte alte Logs aufräumen
    find "$(dirname "$LOG_FILE")" -name "$(basename "$LOG_FILE").*" -type f 2>/dev/null | \
      sort -t. -k2 -n -r | tail -n +$((LOG_KEEP_COUNT + 1)) | xargs -r rm -f 2>/dev/null || true
  fi
}

# --- E-Mail Benachrichtigungs-Funktion ---
send_email() {
  local subject="$1"
  local body="$2"
  local priority="${3:-normal}"  # normal, error, success
  
  if [ "$EMAIL_ENABLED" != true ]; then
    return 0
  fi
  
  if [ -z "$EMAIL_RECIPIENT" ]; then
      if [ "$EMAIL_ATTACH_LOG" = true ] && [ -f "$LOG_FILE" ]; then
        if command -v mail >/dev/null 2>&1; then
          echo "$full_body" | mail -s "$full_subject" -a "$LOG_FILE" "$EMAIL_RECIPIENT" 2>/dev/null
          log "E-Mail mit Log-Anhang gesendet an $EMAIL_RECIPIENT (via mail)"
          return 0
        elif command -v msmtp >/dev/null 2>&1; then
          {
            echo "To: $EMAIL_RECIPIENT"
            echo "Subject: $full_subject"
            echo "Content-Type: text/plain; charset=utf-8"
            echo ""
            echo "$full_body"
          } | msmtp --attach="$LOG_FILE" "$EMAIL_RECIPIENT" 2>/dev/null
          log "E-Mail mit Log-Anhang gesendet an $EMAIL_RECIPIENT (via msmtp)"
          return 0
        elif command -v sendmail >/dev/null 2>&1; then
          {
            echo "To: $EMAIL_RECIPIENT"
            echo "Subject: $full_subject"
            echo "MIME-Version: 1.0"
            echo "Content-Type: multipart/mixed; boundary=\"LOGBOUNDARY\""
            echo ""
            echo "--LOGBOUNDARY"
            echo "Content-Type: text/plain; charset=utf-8"
            echo ""
            echo "$full_body"
            echo "--LOGBOUNDARY"
            echo "Content-Type: text/plain; name=update_modules.log"
            echo "Content-Disposition: attachment; filename=update_modules.log"
            echo ""
            cat "$LOG_FILE"
            echo "--LOGBOUNDARY--"
          } | sendmail -t 2>/dev/null
          log "E-Mail mit Log-Anhang gesendet an $EMAIL_RECIPIENT (via sendmail)"
          return 0
        fi
        # Fallback: Wenn kein Tool mit Anhang, sende wie bisher
        log "WARNING: Kein Mail-Tool mit Anhang-Unterstützung gefunden, sende E-Mail ohne Anhang."
      fi
    log "WARNING: EMAIL_ENABLED=true but EMAIL_RECIPIENT is empty"
    return 1
  fi
  
  # Skip success emails if not enabled
  if [ "$priority" = "success" ] && [ "$EMAIL_ON_SUCCESS" != true ]; then
    return 0
  fi
  
  # Skip error emails if not enabled
  if [ "$priority" = "error" ] && [ "$EMAIL_ON_ERROR" != true ]; then
    return 0
  fi
  
  local full_subject="$EMAIL_SUBJECT_PREFIX $subject"
  local hostname
  hostname=$(hostname 2>/dev/null || echo "unknown")
  
  # Zusätzliche Infos zum Body hinzufügen
  local full_body="$body

---
Host: $hostname
Zeit: $(timestamp)
Log: $LOG_FILE"
  
  # Versuche verschiedene Mail-Tools
  if command -v mail >/dev/null 2>&1; then
    echo "$full_body" | mail -s "$full_subject" "$EMAIL_RECIPIENT" 2>/dev/null
    log "E-Mail gesendet an $EMAIL_RECIPIENT (via mail)"
    return 0
  elif command -v sendmail >/dev/null 2>&1; then
    {
      echo "To: $EMAIL_RECIPIENT"
      echo "Subject: $full_subject"
      echo "Content-Type: text/plain; charset=utf-8"
      echo ""
      echo "$full_body"
    } | sendmail -t 2>/dev/null
    log "E-Mail gesendet an $EMAIL_RECIPIENT (via sendmail)"
    return 0
  elif command -v msmtp >/dev/null 2>&1; then
    {
      echo "To: $EMAIL_RECIPIENT"
      echo "Subject: $full_subject"
      echo ""
      echo "$full_body"
    } | msmtp "$EMAIL_RECIPIENT" 2>/dev/null
    log "E-Mail gesendet an $EMAIL_RECIPIENT (via msmtp)"
    return 0
  elif command -v ssmtp >/dev/null 2>&1; then
    {
      echo "To: $EMAIL_RECIPIENT"
      echo "Subject: $full_subject"
      echo ""
      echo "$full_body"
    } | ssmtp "$EMAIL_RECIPIENT" 2>/dev/null
    log "E-Mail gesendet an $EMAIL_RECIPIENT (via ssmtp)"
    return 0
  else
    log "WARNING: Kein Mail-Tool gefunden (mail, sendmail, msmtp, ssmtp). E-Mail nicht gesendet."
    return 1
  fi
}

# Kritische Fehler-Funktion mit E-Mail
log_error() {
  local message="$*"
  log "ERROR: $message"
  send_email "Fehler beim Update" "$message" "error"
}

# Log-Rotation beim Start ausführen
rotate_logs

# detect if sudo is available; we'll prefer to call npm with sudo if present
SUDO_CMD=""
if command -v sudo >/dev/null 2>&1; then
  SUDO_CMD="sudo"
fi
# user to own module files after npm (change if you use different user)
CHOWN_USER="pi"

# Check and install/update Node.js version if needed for MagicMirror
check_and_update_nodejs() {
  log "Checking Node.js version..."
  
  if ! command -v node >/dev/null 2>&1; then
    log "ERROR: Node.js not found - cannot continue"
    return 1
  fi
  
  current_node_version=$(node --version | sed 's/v//')
  log "Current Node.js version: v$current_node_version"
  
  # Check if version meets minimum requirements (>=22.21.1 or >=24)
  # Extract major and minor version with safe defaults
  node_major=$(echo "$current_node_version" | cut -d. -f1 | grep -oE '[0-9]+' || echo "0")
  node_minor=$(echo "$current_node_version" | cut -d. -f2 | grep -oE '[0-9]+' || echo "0")
  node_patch=$(echo "$current_node_version" | cut -d. -f3 | grep -oE '[0-9]+' || echo "0")
  
  # Ensure variables are numeric
  node_major=${node_major:-0}
  node_minor=${node_minor:-0}
  node_patch=${node_patch:-0}
  
  needs_update=false
  
  if [ "$node_major" -lt 22 ]; then
    needs_update=true
    log "Node.js version too old (v$current_node_version < v22.21.1)"
  elif [ "$node_major" -eq 22 ] && [ "$node_minor" -lt 21 ]; then
    needs_update=true
    log "Node.js v22 but version too old (v$current_node_version < v22.21.1)"
  elif [ "$node_major" -eq 22 ] && [ "$node_minor" -eq 21 ] && [ "$node_patch" -lt 1 ]; then
    needs_update=true
    log "Node.js v22.21 but patch version too old (v$current_node_version < v22.21.1)"
  elif [ "$node_major" -eq 23 ]; then
    needs_update=true
    log "Node.js v23 is not supported - need v22.21.1+ or v24+"
  fi
  
  if [ "$needs_update" = true ]; then
    log "Node.js update required for MagicMirror 2.34.0+"
    
    # Detect architecture for appropriate Node.js version
    arch=$(uname -m)
    node_target_version="22"  # Default to v22 LTS (more compatible)
    
    # Node.js v24 might not be available for all architectures (especially armv7l/armhf)
    if [ "$arch" = "x86_64" ] || [ "$arch" = "aarch64" ]; then
      node_target_version="22"  # Use v22 for stability, v24 can have compatibility issues
    else
      log "Detected 32-bit ARM architecture ($arch) - using Node.js v22 LTS for best compatibility"
      node_target_version="22"
    fi
    
    # Check if nvm is available
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
      log "nvm detected - using nvm to install Node.js v$node_target_version (LTS)"
      if [ "$DRY_RUN" = true ]; then
        log "(dry) would run: nvm install $node_target_version && nvm use $node_target_version && nvm alias default $node_target_version"
        return 0
      fi
      # shellcheck disable=SC1091
      source "$HOME/.nvm/nvm.sh"
      
      # Try to install the target version
      if nvm install "$node_target_version" 2>&1 | tee -a "$LOG_FILE"; then
        nvm use "$node_target_version" 2>&1 | tee -a "$LOG_FILE"
        nvm alias default "$node_target_version" 2>&1 | tee -a "$LOG_FILE"
        log "✓ Node.js updated to $(node --version) via nvm"
      else
        log "✗ Failed to install Node.js v$node_target_version - trying v22 as fallback"
        if nvm install 22 2>&1 | tee -a "$LOG_FILE"; then
          nvm use 22 2>&1 | tee -a "$LOG_FILE"
          nvm alias default 22 2>&1 | tee -a "$LOG_FILE"
          log "✓ Node.js updated to $(node --version) via nvm (fallback)"
        else
          log "✗ ERROR: Could not install Node.js - manual intervention required"
          return 1
        fi
      fi
    else
      log "nvm not found - installing nvm first"
      if [ "$DRY_RUN" = true ]; then
        log "(dry) would install nvm and Node.js v$node_target_version"
        return 0
      fi
      
      # Install nvm
      log "Installing nvm..."
      curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash 2>&1 | tee -a "$LOG_FILE"
      
      # Load nvm into current shell
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
      [ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
      
      if command -v nvm >/dev/null 2>&1; then
        log "✓ nvm installed successfully"
        if nvm install "$node_target_version" 2>&1 | tee -a "$LOG_FILE"; then
          nvm use "$node_target_version" 2>&1 | tee -a "$LOG_FILE"
          nvm alias default "$node_target_version" 2>&1 | tee -a "$LOG_FILE"
          log "✓ Node.js updated to $(node --version)"
        else
          log "✗ Failed to install Node.js v$node_target_version - trying v22 as fallback"
          nvm install 22 2>&1 | tee -a "$LOG_FILE"
          nvm use 22 2>&1 | tee -a "$LOG_FILE"
          nvm alias default 22 2>&1 | tee -a "$LOG_FILE"
          log "✓ Node.js updated to $(node --version) (fallback)"
        fi
      else
        log "ERROR: nvm installation failed - please install manually:"
        log "  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash"
        log "  source ~/.bashrc"
        log "  nvm install 22"
        log "  nvm use 22"
        log "  nvm alias default 22"
        return 1
      fi
    fi
  else
    log "✓ Node.js version is compatible (v$current_node_version)"
  fi
  
  return 0
}

# chown helper: set ownership of a module directory back to $CHOWN_USER
chown_module() {
  local target="$1"
  if [ "$DRY_RUN" = true ]; then
    log "(dry) would chown -R $CHOWN_USER:$CHOWN_USER $target"
    return 0
  fi
  if [ "$(id -u)" -eq 0 ]; then
    chown -R "$CHOWN_USER":"$CHOWN_USER" "$target" 2>&1 | tee -a "$LOG_FILE" || log "chown failed for $target"
  else
    if [ -n "$SUDO_CMD" ]; then
      $SUDO_CMD chown -R "$CHOWN_USER":"$CHOWN_USER" "$target" 2>&1 | tee -a "$LOG_FILE" || log "sudo chown failed for $target"
    else
      chown -R "$CHOWN_USER":"$CHOWN_USER" "$target" 2>&1 | tee -a "$LOG_FILE" || log "chown failed for $target"
    fi
  fi
}

# Log npm version for troubleshooting
if command -v npm >/dev/null 2>&1; then
  # prefer running npm with sudo when appropriate (some setups require sudo for global modules)
  npm_exec() {
    # Always invoke npm via sudo when sudo L (user requested this)
    if [ -n "$SUDO_CMD" ]; then
      $SUDO_CMD npm "$@"
    else
      npm "$@"
    fi
  }

  npm_ver=$(npm_exec --version 2>/dev/null || echo "unknown")
  log "npm version: $npm_ver"
else
  log "npm not found in PATH"
fi

# Optionally update raspbian packages before module updates (may take long)
apt_get_prefix() {
  # return command prefix for apt-get (may include sudo)
  if [ "$(id -u)" -eq 0 ]; then
    echo ""
  elif command -v sudo >/dev/null 2>&1; then
    echo "sudo"
  else
    echo ""  # will likely fail without privileges
  fi
}

apt_update_with_retry() {
  local attempts=1
  local sleep_for=10
  local max=$APT_UPDATE_MAX_ATTEMPTS
  local sudo_prefix
  sudo_prefix=$(apt_get_prefix)
  log "Starting apt-get full-upgrade via: ${sudo_prefix:+$sudo_prefix }apt-get full-upgrade (attempts up to $max)"
  while [ $attempts -le $max ]; do
    if [ "$DRY_RUN" = true ]; then
      if [ -n "$sudo_prefix" ]; then
        log "(dry) would run: DEBIAN_FRONTEND=noninteractive sudo apt-get update && DEBIAN_FRONTEND=noninteractive sudo apt-get -y -o Dpkg::Options::=\"--force-confdef\" -o Dpkg::Options::=\"--force-confold\" full-upgrade"
      else
        log "(dry) would run: DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=\"--force-confdef\" -o Dpkg::Options::=\"--force-confold\" full-upgrade"
      fi
      return 0
    fi
    # run update then full-upgrade in non-interactive mode, call sudo as separate word if needed
    if [ -n "$sudo_prefix" ]; then
      DEBIAN_FRONTEND=noninteractive sudo apt-get update 2>&1 | tee -a "$LOG_FILE" && \
      DEBIAN_FRONTEND=noninteractive sudo apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" full-upgrade 2>&1 | tee -a "$LOG_FILE";
      rc=$?
    else
      DEBIAN_FRONTEND=noninteractive apt-get update 2>&1 | tee -a "$LOG_FILE" && \
      DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" full-upgrade 2>&1 | tee -a "$LOG_FILE";
      rc=$?
    fi
    if [ $rc -eq 0 ]; then
      log "apt-get full-upgrade completed"
      # autoremove
      if [ -n "$sudo_prefix" ]; then
        sudo apt-get -y autoremove 2>&1 | tee -a "$LOG_FILE" || true
      else
        apt-get -y autoremove 2>&1 | tee -a "$LOG_FILE" || true
      fi
      return 0
    else
      # Check if lock error occurred
      tailout=$(tail -n 60 "$LOG_FILE" 2>/dev/null || true)
      if echo "$tailout" | grep -qi "Could not get lock" || echo "$tailout" | grep -qi "Unable to acquire the dpkg"; then
        log "apt/dpkg lock detected, waiting $sleep_for seconds before retrying (attempt $attempts/$max)"
        sleep $sleep_for
        attempts=$((attempts+1))
        sleep_for=$((sleep_for*2))
        continue
      else
        log "apt-get full-upgrade failed (non-lock error), see log"
        return 2
      fi
    fi
  done
  log "Exceeded apt retry attempts"
  return 2
}

# --- Healthcheck Funktion ---
# Prüft ob MagicMirror nach Updates korrekt startet
perform_healthcheck() {
  log "=== MagicMirror Healthcheck ==="
  
  # Starte/Restarte MagicMirror für Healthcheck
  log "Restarting $PM2_PROCESS_NAME for healthcheck..."
  if pm2 restart "$PM2_PROCESS_NAME" 2>&1 | tee -a "$LOG_FILE"; then
    log "pm2 restart command sent"
  else
    log "WARNING: pm2 restart failed"
    return 1
  fi

  # Warte und prüfe Status
  log "Waiting ${HEALTHCHECK_TIMEOUT}s for MagicMirror to start..."
  local waited check_interval mm_running pm2_status http_success http_attempts http_max_attempts http_tool
  http_tool=""
  waited=0
  check_interval=5
  mm_running=false

  while [ $waited -lt "$HEALTHCHECK_TIMEOUT" ]; do
    sleep $check_interval
    waited=$((waited + check_interval))

    pm2_status=$(pm2 show "$PM2_PROCESS_NAME" 2>/dev/null | grep -E "status" | awk '{print $4}' || echo "unknown")

    if [ "$pm2_status" = "online" ]; then
      log "✓ pm2 process is online (after ${waited}s)"
      mm_running=true
      break
    elif [ "$pm2_status" = "errored" ] || [ "$pm2_status" = "stopped" ]; then
      log "✗ pm2 process is $pm2_status after ${waited}s"
      # Zeige Logs für Debugging
      log "Last 20 lines of pm2 logs:"
      pm2 logs "$PM2_PROCESS_NAME" --lines 20 --nostream 2>&1 | tee -a "$LOG_FILE" || true
      return 1
    fi
    log "Waiting... ($waited/${HEALTHCHECK_TIMEOUT}s) - status: $pm2_status"
  done

  if [ "$mm_running" != true ]; then
    log "✗ MagicMirror did not start within ${HEALTHCHECK_TIMEOUT}s"
    log_error "MagicMirror Healthcheck fehlgeschlagen - Prozess startete nicht innerhalb von ${HEALTHCHECK_TIMEOUT}s"
    return 1
  fi

  # HTTP Healthcheck wenn möglich
  if [ -n "$http_tool" ]; then
    log "Performing HTTP healthcheck on $HEALTHCHECK_URL..."
    sleep 5  # Kurz warten bis Server bereit

    http_success=false
    http_attempts=0
    http_max_attempts=3

    while [ $http_attempts -lt $http_max_attempts ]; do
      http_attempts=$((http_attempts + 1))

      if [ "$http_tool" = "curl" ]; then
        if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$HEALTHCHECK_URL" 2>/dev/null | grep -qE "^(200|302)$"; then
          http_success=true
          break
        fi
      else
        if wget -q --spider --timeout=10 "$HEALTHCHECK_URL" 2>/dev/null; then
          http_success=true
          break
        fi
      fi

      log "HTTP check attempt $http_attempts failed, retrying..."
      sleep 3
    done

    if [ "$http_success" = true ]; then
      log "✓ HTTP healthcheck passed - MagicMirror is responding"
    else
      log "✗ HTTP healthcheck failed - MagicMirror not responding on $HEALTHCHECK_URL"
      log "  (This might be normal if MagicMirror is configured for local display only)"
    fi
  fi

  log "=== Healthcheck Complete ==="
  send_email "Healthcheck erfolgreich" "MagicMirror läuft nach dem Update korrekt." "success"
  return 0
}

# System-Cleanup: Cache leeren, RAM freigeben, unnötige Pakete entfernen
# Wird automatisch am Ende des Skripts ausgeführt
cleanup_system() {
  log "=== System-Cleanup wird gestartet ==="

  if [ "$DRY_RUN" = true ]; then
    log "(dry) würde System-Cleanup durchführen"
    return 0
  fi

  # APT Cache leeren
  log "Leere APT Cache..."
  sudo_prefix=$(apt_get_prefix)
  if [ -n "$sudo_prefix" ]; then
    $sudo_prefix apt-get clean 2>&1 | tee -a "$LOG_FILE" || log "apt-get clean fehlgeschlagen"
    $sudo_prefix apt-get autoclean 2>&1 | tee -a "$LOG_FILE" || log "apt-get autoclean fehlgeschlagen"
    $sudo_prefix apt-get autoremove --purge -y 2>&1 | tee -a "$LOG_FILE" || log "apt-get autoremove fehlgeschlagen"
  else
    apt-get clean 2>&1 | tee -a "$LOG_FILE" || log "apt-get clean fehlgeschlagen"
    apt-get autoclean 2>&1 | tee -a "$LOG_FILE" || log "apt-get autoclean fehlgeschlagen"
    apt-get autoremove --purge -y 2>&1 | tee -a "$LOG_FILE" || log "apt-get autoremove fehlgeschlagen"
  fi

  # Alte Log-Dateien bereinigen (journalctl)
  log "Bereinige alte Systemlogs..."
  if [ -n "$sudo_prefix" ]; then
    $sudo_prefix journalctl --vacuum-time=7d 2>&1 | tee -a "$LOG_FILE" || log "journalctl vacuum fehlgeschlagen"
  else
    journalctl --vacuum-time=7d 2>&1 | tee -a "$LOG_FILE" || log "journalctl vacuum fehlgeschlagen"
  fi

  # User Cache leeren (nur wenn sicher)
  if [ -d "$HOME/.cache" ]; then
    log "Leere User-Cache..."
    rm -rf "$HOME/.cache"/* 2>&1 | tee -a "$LOG_FILE" || log "User-Cache leeren teilweise fehlgeschlagen"
  fi

  # RAM Cache freigeben (Page Cache, dentries, inodes)
  log "Gebe RAM-Cache frei..."
  if [ -n "$sudo_prefix" ]; then
    sync
    $sudo_prefix sysctl -w vm.drop_caches=3 2>&1 | tee -a "$LOG_FILE" || log "RAM-Cache freigeben fehlgeschlagen"
  else
    sync
    sysctl -w vm.drop_caches=3 2>&1 | tee -a "$LOG_FILE" || log "RAM-Cache freigeben fehlgeschlagen"
  fi

  # Zeige freien Speicher nach Cleanup
  log "Speichernutzung nach Cleanup:"
  free -h 2>&1 | tee -a "$LOG_FILE"

  log "=== System-Cleanup abgeschlossen ==="
  return 0
}

# Final-exit handler: if requested, reboot the Pi after the script finishes.
# This runs on EXIT (normal or due to error). We skip the reboot when DRY_RUN=true.
on_exit_handler() {
  rc=$?
  
  # Always clean up temp files first
  cleanup_temp_files

  # Perform system cleanup (cache, RAM, old packages)
  cleanup_system

  # Do not reboot in dry-run mode
  if [ "${DRY_RUN:-false}" = true ]; then
    log "DRY_RUN=true — skipping final reboot (exit code $rc)"
    return 0
  fi

  # Check if we should reboot
  local should_reboot=false
  
  if [ "${AUTO_REBOOT_AFTER_SCRIPT:-false}" = true ]; then
    log "AUTO_REBOOT_AFTER_SCRIPT=true — reboot will occur regardless of updates"
    should_reboot=true
  elif [ "${REBOOT_ONLY_ON_UPDATES:-true}" = true ] && [ "${updated_any:-false}" = true ]; then
    log "REBOOT_ONLY_ON_UPDATES=true and updates were installed — reboot will occur"
    should_reboot=true
  fi
  
  if [ "$should_reboot" = true ]; then
    # Healthcheck vor dem Reboot durchführen
    if ! perform_healthcheck; then
      log "WARNING: Healthcheck failed - reboot will still proceed"
      log_error "Healthcheck vor Reboot fehlgeschlagen! System wird trotzdem neu gestartet."
    fi
    
    log "Performing reboot now (script exit code $rc)"
    sudo_prefix=$(apt_get_prefix)
    # call reboot via sudo if necessary; ignore any failure to avoid masking original exit status
    if [ -n "$sudo_prefix" ]; then
      $sudo_prefix reboot || log "reboot command failed (attempted: $sudo_prefix reboot)"
    else
      reboot || log "reboot command failed (attempted: reboot)"
    fi
  else
    log "No reboot necessary (no updates installed or AUTO_REBOOT_AFTER_SCRIPT=false)"
  fi
}

# Install trap so on_exit_handler runs when the script exits for any reason
trap on_exit_handler EXIT

if [ "$DRY_RUN" = true ]; then
  log "DRY RUN enabled — no changes will be made"
fi

if [ ! -d "$MODULES_DIR" ]; then
  log "ERROR: modules directory '$MODULES_DIR' does not exist"
  exit 1
fi

# Check available disk space before proceeding (minimum 200MB required)
check_disk_space() {
  local min_space_kb=204800  # 200MB in KB
  local available_kb
  available_kb=$(df -k "$MODULES_DIR" 2>/dev/null | awk 'NR==2 {print $4}')

  if [ -z "$available_kb" ] || [ "$available_kb" -eq 0 ] 2>/dev/null; then
    log "WARNING: Could not determine available disk space"
    return 0
  fi

  local available_mb=$((available_kb / 1024))
  log "Available disk space: ${available_mb}MB"

  if [ "$available_kb" -lt "$min_space_kb" ]; then
    log "ERROR: Not enough disk space! ${available_mb}MB available, minimum 200MB required."
    log "Please free up disk space before running updates."
    log "Suggestions: rm -rf ~/module_backups/*.tar.gz; sudo apt-get clean; npm cache clean --force"
    log_error "Update abgebrochen: Nur ${available_mb}MB Speicherplatz frei (mindestens 200MB benötigt)."
    exit 1
  fi
}

check_disk_space

# Check Node.js version before proceeding
check_and_update_nodejs

# Prüft, ob electron im MagicMirror-Ordner installiert ist, und führt ggf. npm install aus
ensure_electron_installed() {
  local mm_dir="$MAGICMIRROR_DIR"
  if [ ! -d "$mm_dir/node_modules/.bin" ] || [ ! -f "$mm_dir/node_modules/.bin/electron" ]; then
    log "Electron nicht gefunden – führe npm install im MagicMirror-Ordner aus..."
    if [ "$DRY_RUN" = true ]; then
      log "(dry) würde im $mm_dir: npm install ausführen"
    else
      pushd "$mm_dir" >/dev/null
      if npm install 2>&1 | tee -a "$LOG_FILE"; then
        log "✓ npm install im MagicMirror-Ordner erfolgreich (electron installiert)"
      else
        log "✗ npm install im MagicMirror-Ordner fehlgeschlagen – electron fehlt weiterhin!"
      fi
      popd >/dev/null
    fi
  else
    log "✓ Electron ist im MagicMirror-Ordner installiert"
  fi
}

# Sicherstellen, dass electron installiert ist, bevor MagicMirror gestartet wird
ensure_electron_installed

updated_any=false

# Update MagicMirror core before updating modules
update_magicmirror_core() {
  if [ "$UPDATE_MAGICMIRROR_CORE" != true ]; then
    log "MagicMirror core update disabled (UPDATE_MAGICMIRROR_CORE != true)"
    return 0
  fi
  
  if [ ! -d "$MAGICMIRROR_DIR" ]; then
    log "ERROR: MagicMirror directory '$MAGICMIRROR_DIR' does not exist - skipping core update"
    return 1
  fi
  
  log "=== Updating MagicMirror Core ==="
  
  if [ ! -d "$MAGICMIRROR_DIR/.git" ]; then
    log "WARNING: '$MAGICMIRROR_DIR' is not a git repository - skipping core update"
    return 1
  fi
  
  # Backup config.js and custom.css before update
  local config_file="$MAGICMIRROR_DIR/config/config.js"
  local config_backup="/tmp/magicmirror_config_backup_$(date +%Y%m%d_%H%M%S).js"
  local config_restored=false
  
  local css_file="$MAGICMIRROR_DIR/css/custom.css"
  local css_backup="/tmp/magicmirror_custom_css_backup_$(date +%Y%m%d_%H%M%S).css"
  local css_restored=false
  
  if [ -f "$config_file" ]; then
    log "Backing up config.js to $config_backup"
    if [ "$DRY_RUN" = true ]; then
      log "(dry) would backup $config_file to $config_backup"
    else
      cp -p "$config_file" "$config_backup" 2>&1 | tee -a "$LOG_FILE"
      if [ $? -eq 0 ]; then
        log "✓ config.js backed up successfully"
        # Also create a permanent backup in backup directory
        mkdir -p "$BACKUP_DIR/config_backups" || true
        cp -p "$config_file" "$BACKUP_DIR/config_backups/config_$(date +%Y%m%d_%H%M%S).js" 2>&1 | tee -a "$LOG_FILE" || log "Warning: Could not create permanent config backup"
      else
        log "Warning: Could not backup config.js"
      fi
    fi
  else
    log "Warning: config.js not found at $config_file - skipping backup"
  fi
  
  # Backup custom.css before update
  if [ -f "$css_file" ]; then
    log "Backing up custom.css to $css_backup"
    if [ "$DRY_RUN" = true ]; then
      log "(dry) would backup $css_file to $css_backup"
    else
      cp -p "$css_file" "$css_backup" 2>&1 | tee -a "$LOG_FILE"
      if [ $? -eq 0 ]; then
        log "✓ custom.css backed up successfully"
        # Also create a permanent backup in backup directory
        mkdir -p "$BACKUP_DIR/css_backups" || true
        cp -p "$css_file" "$BACKUP_DIR/css_backups/custom_$(date +%Y%m%d_%H%M%S).css" 2>&1 | tee -a "$LOG_FILE" || log "Warning: Could not create permanent css backup"
      else
        log "Warning: Could not backup custom.css"
      fi
    fi
  else
    log "Warning: custom.css not found at $css_file - skipping backup"
  fi
  
  pushd "$MAGICMIRROR_DIR" >/dev/null
  
  # Check for local changes in MagicMirror core
  if [ -n "$(git status --porcelain)" ]; then
    log "Local changes detected in MagicMirror core"
    if [ "$AUTO_DISCARD_LOCAL" = true ]; then
      log "AUTO_DISCARD_LOCAL=true — discarding local changes in MagicMirror core"
      if [ "$DRY_RUN" = true ]; then
        log "(dry) would run: git fetch origin && git reset --hard origin/master && git clean -fdx"
      else
        git fetch origin --prune 2>&1 | tee -a "$LOG_FILE" || log "git fetch failed for MagicMirror core"
        git reset --hard origin/master 2>&1 | tee -a "$LOG_FILE" || log "git reset failed for MagicMirror core"
        git clean -fdx 2>&1 | tee -a "$LOG_FILE" || true
      fi
    else
      log "Skipping MagicMirror core update due to local changes (set AUTO_DISCARD_LOCAL=true to overwrite)"
      popd >/dev/null
      return 1
    fi
  fi
  
  # Run git pull
  if [ "$DRY_RUN" = true ]; then
    log "(dry) would run: git pull && node --run install-mm"
  else
    log "Running: git pull"
    local old_head new_head
    old_head=$(git rev-parse --verify HEAD 2>/dev/null || echo "none")
    
    if git pull 2>&1 | tee -a "$LOG_FILE"; then
      new_head=$(git rev-parse --verify HEAD 2>/dev/null || echo "none")
      
      if [ "$old_head" != "$new_head" ]; then
        log "✓ MagicMirror core updated ($old_head -> $new_head)"
        updated_any=true
        
        # Clean install to ensure all dependencies (especially electron) are properly installed
        log "Cleaning old node_modules and package-lock.json to ensure clean install"
        if [ "$DRY_RUN" = false ]; then
          rm -rf node_modules package-lock.json 2>&1 | tee -a "$LOG_FILE" || log "Warning: Could not remove node_modules/package-lock.json"
        else
          log "(dry) would remove node_modules and package-lock.json"
        fi
        
        # Run node --run install-mm to install dependencies
        log "Running: node --run install-mm (with --engine-strict=false to bypass version checks)"
        if command -v node >/dev/null 2>&1; then
          if npm install --engine-strict=false 2>&1 | tee -a "$LOG_FILE" || node --run install-mm 2>&1 | tee -a "$LOG_FILE"; then
            log "✓ MagicMirror dependencies installed successfully"
            
            # Verify that electron was installed correctly
            if [ -f "./node_modules/.bin/electron" ]; then
              log "✓ Electron binary verified at ./node_modules/.bin/electron"
            else
              log "WARNING: Electron binary not found, attempting fallback installation"
              if npm install 2>&1 | tee -a "$LOG_FILE"; then
                log "✓ Fallback npm install completed"
                if [ -f "./node_modules/.bin/electron" ]; then
                  log "✓ Electron now available after fallback"
                else
                  log "ERROR: Electron still missing after fallback - manual fix may be required"
                fi
              else
                log "ERROR: Fallback npm install failed"
              fi
            fi
            
            chown_module "$MAGICMIRROR_DIR"
          else
            log "ERROR: node --run install-mm failed, trying fallback npm install"
            if npm install 2>&1 | tee -a "$LOG_FILE"; then
              log "✓ Fallback npm install completed successfully"
              chown_module "$MAGICMIRROR_DIR"
            else
              log "ERROR: Both node --run install-mm and npm install failed for MagicMirror core"
              popd >/dev/null
              return 2
            fi
          fi
        else
          log "ERROR: node not found in PATH - cannot install MagicMirror dependencies"
          popd >/dev/null
          return 2
        fi
      else
        log "MagicMirror core is already up-to-date"
      fi
    else
      log "ERROR: git pull failed for MagicMirror core"
      popd >/dev/null
      return 2
    fi
  fi
  
  # Restore config.js after update if it was backed up
  if [ -f "$config_backup" ] && [ "$DRY_RUN" = false ]; then
    log "Restoring config.js from backup"
    if [ -f "$config_file" ]; then
      # config.js exists after update - check if it's different from backup
      if ! diff -q "$config_file" "$config_backup" >/dev/null 2>&1; then
        log "Warning: config.js was modified during update - creating comparison backup"
        cp -p "$config_file" "${config_file}.updated_$(date +%Y%m%d_%H%M%S)" 2>&1 | tee -a "$LOG_FILE" || true
      fi
    fi
    
    # Restore original config
    cp -p "$config_backup" "$config_file" 2>&1 | tee -a "$LOG_FILE"
    if [ $? -eq 0 ]; then
      log "✓ config.js restored successfully"
      config_restored=true
      # Clean up temp backup after successful restore
      rm -f "$config_backup" 2>&1 | tee -a "$LOG_FILE" || true
    else
      log "ERROR: Could not restore config.js from $config_backup - please restore manually!"
    fi
  elif [ ! -f "$config_file" ] && [ -f "$config_backup" ] && [ "$DRY_RUN" = false ]; then
    # config.js missing after update but we have backup
    log "Warning: config.js missing after update - restoring from backup"
    mkdir -p "$(dirname "$config_file")" || true
    cp -p "$config_backup" "$config_file" 2>&1 | tee -a "$LOG_FILE"
    if [ $? -eq 0 ]; then
      log "✓ config.js restored successfully"
      config_restored=true
      rm -f "$config_backup" 2>&1 | tee -a "$LOG_FILE" || true
    else
      log "ERROR: Could not restore config.js - backup is at $config_backup"
    fi
  fi
  
  # Restore custom.css after update if it was backed up
  if [ -f "$css_backup" ] && [ "$DRY_RUN" = false ]; then
    log "Restoring custom.css from backup"
    if [ -f "$css_file" ]; then
      # custom.css exists after update - check if it's different from backup
      if ! diff -q "$css_file" "$css_backup" >/dev/null 2>&1; then
        log "Warning: custom.css was modified during update - creating comparison backup"
        cp -p "$css_file" "${css_file}.updated_$(date +%Y%m%d_%H%M%S)" 2>&1 | tee -a "$LOG_FILE" || true
      fi
    fi
    
    # Restore original custom.css
    cp -p "$css_backup" "$css_file" 2>&1 | tee -a "$LOG_FILE"
    if [ $? -eq 0 ]; then
      log "✓ custom.css restored successfully"
      css_restored=true
      # Clean up temp backup after successful restore
      rm -f "$css_backup" 2>&1 | tee -a "$LOG_FILE" || true
    else
      log "ERROR: Could not restore custom.css from $css_backup - please restore manually!"
    fi
  elif [ ! -f "$css_file" ] && [ -f "$css_backup" ] && [ "$DRY_RUN" = false ]; then
    # custom.css missing after update but we have backup
    log "Warning: custom.css missing after update - restoring from backup"
    mkdir -p "$(dirname "$css_file")" || true
    cp -p "$css_backup" "$css_file" 2>&1 | tee -a "$LOG_FILE"
    if [ $? -eq 0 ]; then
      log "✓ custom.css restored successfully"
      css_restored=true
      rm -f "$css_backup" 2>&1 | tee -a "$LOG_FILE" || true
    else
      log "ERROR: Could not restore custom.css - backup is at $css_backup"
    fi
  fi
  
  popd >/dev/null
  log "=== MagicMirror Core Update Complete ==="
  
  # Final check for config.js
  if [ ! -f "$config_file" ]; then
    log "ERROR: config.js is missing after update! Check $BACKUP_DIR/config_backups/ for backups"
    return 2
  fi
  
  # Note: custom.css is optional, so we don't fail if it's missing
  if [ ! -f "$css_file" ] && [ "$css_restored" = true ]; then
    log "WARNING: custom.css could not be restored! Check $BACKUP_DIR/css_backups/ for backups"
  fi
  
  return 0
}

# Update MagicMirror core before processing modules
update_magicmirror_core

# Backup modules directory before apt-upgrade
backup_modules() {
  if [ "$MAKE_MODULE_BACKUP" != true ]; then
    log "Module backup disabled (MAKE_MODULE_BACKUP != true)"
    return 0
  fi
  mkdir -p "$BACKUP_DIR" || true
  ts=$(date +"%Y%m%d_%H%M%S")
  archive="$BACKUP_DIR/magicmirror_modules_backup_$ts.tar.gz"
  if [ "$DRY_RUN" = true ]; then
    log "(dry) would create backup: $archive from $MODULES_DIR"
    return 0
  fi
  log "Creating modules backup: $archive"
  if tar -czf "$archive" -C "$(dirname "$MODULES_DIR")" "$(basename "$MODULES_DIR")" 2>&1 | tee -a "$LOG_FILE"; then
    log "Backup created: $archive"
    
    # Clean up old backups - keep only the last 4
    log "Cleaning up old backups (keeping last 4)..."
    backup_count=$(find "$BACKUP_DIR" -name "magicmirror_modules_backup_*.tar.gz" -type f 2>/dev/null | wc -l)
    if [ "$backup_count" -gt 4 ]; then
      find "$BACKUP_DIR" -name "magicmirror_modules_backup_*.tar.gz" -type f -printf '%T+ %p\n' 2>/dev/null | \
        sort | head -n -4 | cut -d' ' -f2- | while read -r old_backup; do
        log "Removing old backup: $old_backup"
        rm -f "$old_backup" 2>&1 | tee -a "$LOG_FILE" || true
      done
      log "Old module backups cleaned up"
    fi

    # Clean up old config backups - keep only the last 4
    if [ -d "$BACKUP_DIR/config_backups" ]; then
      config_backup_count=$(find "$BACKUP_DIR/config_backups" -name "config_*.js" -type f 2>/dev/null | wc -l)
      if [ "$config_backup_count" -gt 4 ]; then
        find "$BACKUP_DIR/config_backups" -name "config_*.js" -type f -printf '%T+ %p\n' 2>/dev/null | \
          sort | head -n -4 | cut -d' ' -f2- | while read -r old_backup; do
          log "Removing old config backup: $old_backup"
          rm -f "$old_backup" 2>&1 | tee -a "$LOG_FILE" || true
        done
        log "Old config backups cleaned up"
      fi
    fi

    # Clean up old CSS backups - keep only the last 4
    if [ -d "$BACKUP_DIR/css_backups" ]; then
      css_backup_count=$(find "$BACKUP_DIR/css_backups" -name "custom_*.css" -type f 2>/dev/null | wc -l)
      if [ "$css_backup_count" -gt 4 ]; then
        find "$BACKUP_DIR/css_backups" -name "custom_*.css" -type f -printf '%T+ %p\n' 2>/dev/null | \
          sort | head -n -4 | cut -d' ' -f2- | while read -r old_backup; do
          log "Removing old CSS backup: $old_backup"
          rm -f "$old_backup" 2>&1 | tee -a "$LOG_FILE" || true
        done
        log "Old CSS backups cleaned up"
      fi
    fi

    return 0
  else
    log "Backup FAILED for $MODULES_DIR"
    return 2
  fi
}

# Kill any running ffmpeg processes for RTSPStream before updates to avoid conflicts
kill_rtsp_ffmpeg_processes() {
  local name="$1"
  if [ "$name" = "MMM-RTSPStream" ]; then
    log "Checking for running ffmpeg processes for RTSPStream..."
    # Check for various ffmpeg process patterns that RTSPStream might use
    ffmpeg_patterns=("ffmpeg.*9999" "ffmpeg.*rtsp" "ffmpeg.*MMM-RTSPStream")
    found_processes=false
    
    for pattern in "${ffmpeg_patterns[@]}"; do
      if pgrep -f "$pattern" >/dev/null 2>&1; then
        found_processes=true
        log "Found running ffmpeg processes matching '$pattern' for RTSPStream - terminating them"
        if [ "$DRY_RUN" = true ]; then
          log "(dry) would kill ffmpeg processes matching '$pattern'"
        else
          pkill -TERM -f "$pattern" 2>&1 | tee -a "$LOG_FILE" || log "No ffmpeg processes to kill or pkill failed for pattern '$pattern'"
          sleep 2
          # Force kill if still running
          if pgrep -f "$pattern" >/dev/null 2>&1; then
            log "ffmpeg processes matching '$pattern' still running - force killing"
            pkill -KILL -f "$pattern" 2>&1 | tee -a "$LOG_FILE" || true
            sleep 1
          fi
        fi
      fi
    done
    
    if [ "$found_processes" = false ]; then
      log "No running ffmpeg processes found for RTSPStream"
    else
      # Give system time to clean up
      sleep 2
      # Verify all are gone
      if pgrep -f "ffmpeg" >/dev/null 2>&1; then
        log "WARNING: Some ffmpeg processes still running after cleanup attempt"
        pgrep -af "ffmpeg" | tee -a "$LOG_FILE" || true
      else
        log "✓ All ffmpeg processes successfully terminated"
      fi
    fi
  fi
}

# Track module processing statistics
modules_processed=0
modules_updated=0
modules_failed=0
modules_skipped=0

log "=== Starting module updates ==="
log "Scanning directory: $MODULES_DIR"

for mod in "$MODULES_DIR"/*; do
  [ -d "$mod" ] || continue
  name=$(basename "$mod")
  
  # Skip default modules directory
  if [ "$name" = "default" ]; then
    log "Skipping default modules directory"
    modules_skipped=$((modules_skipped+1))
    continue
  fi
  
  modules_processed=$((modules_processed+1))
  log ""
  log "=== [$modules_processed] Processing module: $name ==="
  
  # Wrap module processing in a subshell to prevent individual module failures from stopping the script
  # Set -e temporarily disabled in subshell so git/npm failures don't abort
  (
  set +e  # Don't exit on error within this subshell
  # Kill ffmpeg processes before updating RTSPStream
  kill_rtsp_ffmpeg_processes "$name"

  # 1) Git update if repo
  if [ -d "$mod/.git" ]; then
    log "Found git repo"
    pushd "$mod" >/dev/null

    # helper: wait for/remove git lock or retry if another git process is running
    git_pull_with_retry() {
      local max_attempts=6
      local attempt=1
      local sleep_for=2
      local old_head new_head current_branch
      old_head=$(git rev-parse --verify HEAD 2>/dev/null || echo "none")
      current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
      
      while [ $attempt -le $max_attempts ]; do
        log "Attempt $attempt: git fetch --all --prune"
        if ! git fetch --all --prune 2>&1 | tee -a "$LOG_FILE"; then
          tail_output=$(tail -n 50 "$LOG_FILE" 2>/dev/null || true)
          if echo "$tail_output" | grep -q "Another git process" || echo "$tail_output" | grep -q "index.lock"; then
            log "Git lock detected (another git process). Waiting $sleep_for seconds before retrying..."
            sleep $sleep_for
            attempt=$((attempt+1))
            sleep_for=$((sleep_for*2))
            continue
          else
            log "git fetch failed for $name (non-lock error)"
            return 2
          fi
        fi

        # Check if there are updates available after fetch
        local commits_behind=0
        if git rev-parse --verify origin/$current_branch >/dev/null 2>&1; then
          commits_behind=$(git rev-list --count HEAD..origin/$current_branch 2>/dev/null || echo "0")
          log "Commits behind origin/$current_branch: $commits_behind"
          
          if [ "$commits_behind" -gt 0 ]; then
            log "Updates available - showing incoming commits:"
            git log --oneline --graph -n 5 HEAD..origin/$current_branch 2>&1 | tee -a "$LOG_FILE" || true
          fi
        else
          log "Warning: origin/$current_branch not found, will try pull anyway"
        fi

        log "Running: git pull --ff-only"
        if git pull --ff-only 2>&1 | tee -a "$LOG_FILE"; then
          new_head=$(git rev-parse --verify HEAD 2>/dev/null || echo "none")
          if [ "$old_head" != "$new_head" ]; then
            log "✓ git pull updated HEAD for $name ($old_head -> $new_head)"
            return 0
          else
            # Double-check: even if pull says up-to-date, verify against remote
            if [ "$commits_behind" -gt 0 ]; then
              log "WARNING: git pull reported up-to-date but $commits_behind commits are available on remote!"
              log "Trying alternative update method: git reset --hard origin/$current_branch"
              if git reset --hard origin/$current_branch 2>&1 | tee -a "$LOG_FILE"; then
                new_head=$(git rev-parse --verify HEAD 2>/dev/null || echo "none")
                if [ "$old_head" != "$new_head" ]; then
                  log "✓ Alternative update successful ($old_head -> $new_head)"
                  return 0
                fi
              fi
            fi
            log "git pull: already up-to-date for $name"
            return 1
          fi
        else
          tail_output=$(tail -n 50 "$LOG_FILE" 2>/dev/null || true)
          if echo "$tail_output" | grep -q "Another git process" || echo "$tail_output" | grep -q "index.lock"; then
            log "Git lock detected during pull. Waiting $sleep_for seconds before retrying..."
            sleep $sleep_for
            attempt=$((attempt+1))
            sleep_for=$((sleep_for*2))
            continue
          else
            log "git pull failed for $name (non-lock error)"
            return 2
          fi
        fi
      done
      log "Exceeded max git retry attempts for $name — skipping"
      return 2
    }

    # Check for local changes
    if [ -n "$(git status --porcelain)" ]; then
      log "Local changes detected in $name"
      if [ "$AUTO_DISCARD_LOCAL" = true ]; then
        log "AUTO_DISCARD_LOCAL=true — discarding local changes for $name (reset --hard + clean)"
        if [ "$DRY_RUN" = true ]; then
          log "(dry) would run: git fetch origin && git reset --hard origin/<branch> (or git reset --hard) && git clean -fdx"
        else
          git fetch origin --prune 2>&1 | tee -a "$LOG_FILE" || true
          branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
          if git rev-parse --verify origin/$branch >/dev/null 2>&1; then
            log "Resetting to origin/$branch"
            git reset --hard origin/$branch 2>&1 | tee -a "$LOG_FILE" || log "git reset failed for $name"
          else
            log "No origin/$branch — performing local hard reset"
            git reset --hard 2>&1 | tee -a "$LOG_FILE" || log "git reset failed for $name"
          fi
          git clean -fdx 2>&1 | tee -a "$LOG_FILE" || true
          # attempt pull after discarding
          module_git_updated=false
          if git_pull_with_retry; then
            updated_any=true
            module_git_updated=true
            echo "1" >> "$MODULE_UPDATE_TRACKER"
            log "✓ Module $name updated successfully (after discarding local changes)"
          else
            rc=$?
            if [ $rc -eq 1 ]; then
              log "✓ Module $name already up-to-date (after discarding local changes)"
            else
              log "✗ Warning: git update failed for $name after discarding local changes (see logs)"
            fi
          fi
        fi
      else
        log "Skipping git pull due to local changes (set AUTO_DISCARD_LOCAL=true to overwrite local changes)"
      fi
    else
      if [ "$DRY_RUN" = true ]; then
        log "(dry) would run: git fetch --all --prune && git pull --ff-only (with lock/retry handling)"
      else
        module_git_updated=false
        if git_pull_with_retry; then
          updated_any=true
          module_git_updated=true
          echo "1" >> "$MODULE_UPDATE_TRACKER"
          log "✓ Module $name updated successfully"
        else
          # if return code 1 -> up-to-date; 2 -> error/skip
          rc=$?
          if [ $rc -eq 1 ]; then
            log "✓ Module $name already up-to-date"
          else
            log "✗ Warning: git update failed for $name (see logs)"
          fi
        fi
      fi
    fi
    popd >/dev/null
  else
    log "Not a git repo"
  fi

  # 2) npm update/install if package.json exists
  # IMPORTANT: Only run npm if the module was actually updated via git OR node_modules is missing.
  # Running npm ci on unchanged modules is dangerous: it deletes node_modules first,
  # and if npm then fails (e.g. network error), the module is left broken without dependencies.
  if [ -f "$mod/package.json" ] && { [ "${module_git_updated:-false}" = "true" ] || [ ! -d "$mod/node_modules" ]; }; then
    if [ "${module_git_updated:-false}" = "true" ]; then
      log "package.json found and module was updated — running npm"
    else
      log "package.json found and node_modules missing — running npm to restore dependencies"
    fi

    # Universal npm strategy: use npm ci for clean install if lockfile L and module was git-updated
    # Otherwise use npm install for flexibility
    npm_special_cmd=""

    # If module was just updated via git, prefer clean install to avoid dependency conflicts
    if [ "${module_git_updated:-false}" = "true" ] && [ -f "$mod/package-lock.json" ]; then
      npm_special_cmd="ci"
      log "Module was git-updated and has lockfile - using npm ci for clean install"
      
      # For modules that need extra cleanup after git updates, remove node_modules AND package-lock for complete rebuild
      case "$name" in
        MMM-RTSPStream)
          log "Module $name needs COMPLETE clean rebuild after git update - removing node_modules and package-lock.json"
          if [ "$DRY_RUN" = true ]; then
            log "(dry) would run: rm -rf $mod/node_modules $mod/package-lock.json"
          else
            # Double-check and kill any lingering ffmpeg processes
            if pgrep -f "ffmpeg.*9999" >/dev/null 2>&1; then
              log "WARNING: Found lingering ffmpeg processes - forcing termination"
              pkill -KILL -f "ffmpeg.*9999" 2>&1 | tee -a "$LOG_FILE" || true
              sleep 3
            fi
            
            # Remove old installation completely
            rm -rf "$mod/node_modules" 2>&1 | tee -a "$LOG_FILE" || log "Failed to remove node_modules for $name"
            rm -f "$mod/package-lock.json" 2>&1 | tee -a "$LOG_FILE" || log "Failed to remove package-lock.json for $name"
            
            # Verify ffmpeg installation and capabilities before npm install
            log "Verifying ffmpeg installation for RTSPStream..."
            if ! command -v ffmpeg >/dev/null 2>&1; then
              log "ERROR: ffmpeg not found! Installing ffmpeg..."
              sudo_prefix=$(apt_get_prefix)
              if [ -n "$sudo_prefix" ]; then
                $sudo_prefix apt-get update 2>&1 | tee -a "$LOG_FILE" || true
                $sudo_prefix apt-get install -y ffmpeg 2>&1 | tee -a "$LOG_FILE" || log "Failed to install ffmpeg"
              fi
            else
              ffmpeg_ver=$(ffmpeg -version 2>&1 | head -n 1 || echo "unknown")
              log "ffmpeg found: $ffmpeg_ver"
              
              # Check for necessary ffmpeg codecs/formats
              log "Checking ffmpeg capabilities for RTSP..."
              if ! ffmpeg -formats 2>&1 | grep -q "rtsp"; then
                log "WARNING: ffmpeg may not have RTSP support compiled in"
              fi
              if ! ffmpeg -codecs 2>&1 | grep -q "h264"; then
                log "WARNING: ffmpeg may not have H.264 codec support"
              fi
            fi
            
            # Clean npm cache globally and for this module to avoid any cached corruption
            log "Clearing npm cache for RTSPStream..."
            npm_exec cache clean --force 2>&1 | tee -a "$LOG_FILE" || log "npm cache clean failed"
            
            # Remove any npm temporary files
            rm -rf /tmp/npm-* 2>/dev/null || true
            
            log "Forcing fresh npm install for RTSPStream with rebuild flags"
            npm_special_cmd="install --no-save --build-from-source --loglevel=verbose"
          fi
          ;;
        MMM-Fuel)
          log "Module $name needs clean rebuild after git update - removing node_modules"
          if [ "$DRY_RUN" = true ]; then
            log "(dry) would run: rm -rf $mod/node_modules"
          else
            rm -rf "$mod/node_modules" 2>&1 | tee -a "$LOG_FILE" || log "Failed to remove node_modules for $name"
          fi
          ;;
      esac
    fi
    
    # Module-specific overrides (only add if absolutely necessary for specific modules)
    case "$name" in
      MMM-Webuntis)
        # npm 11+ removed --only=production, use --omit=dev instead
        npm_special_cmd="install --omit=dev"
        log "Using module-specific override for $name: $npm_special_cmd"
        ;;
      # Add other module-specific overrides here only if the universal strategy fails
      # MMM-Example)
      #   npm_special_cmd="install --no-audit --no-fund"
      #   log "Using module-specific override for $name: $npm_special_cmd"
      #   ;;
    esac

    if [ "$DRY_RUN" = true ]; then
      if [ -n "$npm_special_cmd" ]; then
        log "(dry) would run: ${SUDO_CMD:+$SUDO_CMD }npm --prefix \"$mod\" $npm_special_cmd"
      else
        if [ -f "$mod/package-lock.json" ]; then
          log "(dry) would run: ${SUDO_CMD:+$SUDO_CMD }npm --prefix \"$mod\" ci --no-audit --no-fund"
        else
          log "(dry) would run: ${SUDO_CMD:+$SUDO_CMD }npm --prefix \"$mod\" install --no-audit --no-fund"
        fi
      fi
    else
      # Universal npm installation with intelligent fallback strategy
      run_npm_with_fallback() {
        local modpath="$1"
        local cmd="$2"
        local rc=0
        log "Running: ${SUDO_CMD:+$SUDO_CMD }npm --prefix \"$modpath\" $cmd"
        tmpout=$(mktemp)
        
        # Try the requested command first
        if npm_exec --prefix "$modpath" $cmd --no-audit --no-fund >"$tmpout" 2>&1; then
          cat "$tmpout" | tee -a "$LOG_FILE"
          rc=0
          chown_module "$modpath"
        else
          cat "$tmpout" | tee -a "$LOG_FILE"
          rc=1
          
          # Intelligent fallback: try different strategies based on error type
          if grep -qi "Unknown command" "$tmpout" || grep -qi "unknown" "$tmpout"; then
            log "npm reported unknown command for '$cmd' - trying fallback strategies"
            
            # Strategy 1: Try npm ci if lockfile L
            if [ -f "$modpath/package-lock.json" ]; then
              log "Fallback 1: Trying npm ci (lockfile present)"
              if npm_exec --prefix "$modpath" ci --no-audit --no-fund >>"$LOG_FILE" 2>&1; then
                log "Fallback npm ci succeeded"
                rc=0
                chown_module "$modpath"
              fi
            fi
            
            # Strategy 2: If ci failed or no lockfile, try regular install
            if [ $rc -ne 0 ]; then
              log "Fallback 2: Trying npm install"
              if npm_exec --prefix "$modpath" install --no-audit --no-fund >>"$LOG_FILE" 2>&1; then
                log "Fallback npm install succeeded"
                rc=0
                chown_module "$modpath"
              fi
            fi
            
            # Strategy 3: Last resort - install with omit=dev flag
            if [ $rc -ne 0 ]; then
              log "Fallback 3: Trying npm install --omit=dev"
              if npm_exec --prefix "$modpath" install --omit=dev --no-audit --no-fund >>"$LOG_FILE" 2>&1; then
                log "Fallback npm install --omit=dev succeeded"
                rc=0
                chown_module "$modpath"
              else
                log "All npm fallback strategies failed for $modpath"
                rc=2
              fi
            fi
          else
            log "npm command failed for $modpath (non-unknown-command error)"
            rc=2
          fi
        fi
        
        rm -f "$tmpout"
        return $rc
      }

      # Execute npm with appropriate command and fallback
      if [ -n "$npm_special_cmd" ]; then
        # Use specified command with fallback support
        if run_npm_with_fallback "$mod" "$npm_special_cmd"; then
          updated_any=true
        else
          log "npm ($npm_special_cmd) ultimately failed for $name"
        fi
      else
        # Universal strategy:
        # - If module was git-updated AND has lockfile: use npm ci for clean install
        # - If node_modules is missing (needs restore): use npm install (safer, no wipe)
        # - Otherwise: use npm install
        if [ "${module_git_updated:-false}" = "true" ] && [ -f "$mod/package-lock.json" ]; then
          log "Universal strategy: Using npm ci (lockfile present, module was updated)"
          if run_npm_with_fallback "$mod" "ci"; then
            updated_any=true
          else
            log "npm ci with fallbacks failed for $name"
          fi
        else
          log "Universal strategy: Using npm install (safe, preserves existing node_modules)"
          if run_npm_with_fallback "$mod" "install"; then
            updated_any=true
          else
            log "npm install with fallbacks failed for $name"
          fi
        fi
      fi
    fi
  elif [ -f "$mod/package.json" ]; then
    log "package.json found but module unchanged and node_modules present — skipping npm"
  else
    log "No package.json — skipping npm"
  fi

  # Post-install fixes for specific modules
  if [ "$name" = "MMM-RTSPStream" ] && [ -d "$mod/node_modules" ]; then
    log "Running post-install verification for RTSPStream..."
    if [ "$DRY_RUN" = true ]; then
      log "(dry) would verify RTSPStream installation"
    else
      # Verify node_helper.js exists and is executable
      if [ -f "$mod/node_helper.js" ]; then
        log "node_helper.js found for RTSPStream"
        
        # Check for critical npm dependencies that RTSPStream needs
        log "Checking critical RTSPStream dependencies..."
        critical_deps_missing=false
        
        # Check for datauri module (commonly missing after updates)
        if [ ! -d "$mod/node_modules/datauri" ]; then
          log "CRITICAL: datauri module missing - installing now..."
          critical_deps_missing=true
        fi
        
        # Check for other critical dependencies (expanded list)
        for dep in "node-ffmpeg-stream" "express" "url" "fs" "path"; do
          if [ ! -d "$mod/node_modules/$dep" ] && ! node -e "require('$dep')" 2>/dev/null; then
            log "WARNING: $dep module missing or not loadable"
            critical_deps_missing=true
          fi
        done
        
        # If critical dependencies are missing, reinstall
        if [ "$critical_deps_missing" = true ]; then
          log "Critical dependencies missing - running npm install to fix..."
          pushd "$mod" >/dev/null
          # First try: regular install
          if npm_exec install 2>&1 | tee -a "$LOG_FILE"; then
            log "Successfully reinstalled RTSPStream dependencies"
            chown_module "$mod"
          else
            log "ERROR: npm install failed - trying with --force flag..."
            # Second try: force install
            if npm_exec install --force 2>&1 | tee -a "$LOG_FILE"; then
              log "Successfully force-installed RTSPStream dependencies"
              chown_module "$mod"
            else
              log "ERROR: Failed to install missing RTSPStream dependencies even with --force"
            fi
          fi
          popd >/dev/null
        else
          log "✓ All critical RTSPStream dependencies present"
        fi
        
        # Check for common RTSPStream issues
        if grep -q "omxplayer" "$mod/node_helper.js" 2>/dev/null; then
          log "WARNING: RTSPStream config may reference omxplayer (deprecated on newer Pi OS)"
        fi
        
        # Ensure proper permissions on the module directory
        chown_module "$mod"
        
        # Test if ffmpeg can be called from Node.js context
        log "Testing ffmpeg accessibility from Node.js..."
        test_cmd="const { spawn } = require('child_process'); const proc = spawn('ffmpeg', ['-version']); proc.on('close', (code) => { process.exit(code); });"
        if $SUDO_CMD -u "$CHOWN_USER" node -e "$test_cmd" 2>&1 | tee -a "$LOG_FILE"; then
          log "✓ ffmpeg is accessible from Node.js context"
        else
          log "✗ WARNING: ffmpeg may not be accessible from Node.js - RTSPStream might fail"
          log "Checking ffmpeg path and permissions..."
          which ffmpeg 2>&1 | tee -a "$LOG_FILE" || log "ffmpeg not in PATH"
          ls -la "$(which ffmpeg 2>/dev/null)" 2>&1 | tee -a "$LOG_FILE" || log "Cannot stat ffmpeg"
        fi
        
        # Verify required Node.js modules can be loaded
        log "Testing if datauri module can be loaded..."
        test_cmd="try { require('datauri'); console.log('datauri OK'); process.exit(0); } catch(e) { console.error('datauri FAIL:', e.message); process.exit(1); }"
        if cd "$mod" && node -e "$test_cmd" 2>&1 | tee -a "$LOG_FILE"; then
          log "✓ datauri module loads successfully"
        else
          log "✗ ERROR: datauri module cannot be loaded - RTSPStream will fail!"
        fi
        cd - >/dev/null
        
        # Kill any stale ffmpeg processes from previous runs
        if pgrep -f "ffmpeg.*9999" >/dev/null 2>&1; then
          log "Cleaning up stale ffmpeg processes..."
          pkill -TERM -f "ffmpeg.*9999" 2>&1 | tee -a "$LOG_FILE" || true
          sleep 1
          pkill -KILL -f "ffmpeg.*9999" 2>&1 | tee -a "$LOG_FILE" || true
        fi
      else
        log "✗ ERROR: node_helper.js not found for RTSPStream after installation!"
      fi
      
      # Verify package.json scripts are intact
      if [ -f "$mod/package.json" ]; then
        if ! grep -q "start" "$mod/package.json" 2>/dev/null; then
          log "WARNING: RTSPStream package.json may be missing start script"
        fi
      fi
      
      log "RTSPStream post-install verification complete"
    fi
  fi
  
  log "✓ Done: $name"
  exit 0  # Explicit success exit from subshell
  ) 
  subshell_rc=$?
  if [ $subshell_rc -ne 0 ]; then
    log "✗ ERROR: Module $name processing failed (exit code $subshell_rc), but continuing with other modules..."
    modules_failed=$((modules_failed+1))
  fi
done

# Read actual update count from tracker file
modules_updated=$(grep -c "1" "$MODULE_UPDATE_TRACKER" 2>/dev/null) || modules_updated=0

log ""
log "=== Module Update Summary ==="
log "Total modules processed: $modules_processed"
log "Modules updated: $modules_updated"
log "Modules failed: $modules_failed"
log "Modules skipped: $modules_skipped"
log "Overall success: $(( modules_processed - modules_failed )) / $modules_processed"

if [ $modules_failed -gt 0 ]; then
  log "WARNING: $modules_failed module(s) had errors - check log for details"
  log_error "$modules_failed Modul(e) hatten Fehler beim Update. Verarbeitet: $modules_processed, Erfolgreich: $(( modules_processed - modules_failed ))"
fi

# Sende Erfolgs-E-Mail wenn alles gut lief
if [ $modules_failed -eq 0 ] && [ "$modules_updated" -gt 0 ]; then
  send_email "Updates erfolgreich" "MagicMirror Module wurden aktualisiert.

Zusammenfassung:
- Module verarbeitet: $modules_processed
- Module aktualisiert: $modules_updated
- Fehler: $modules_failed
- Übersprungen: $modules_skipped" "success"
fi

# Clean npm cache after all module updates to free up disk space
log ""
log "Cleaning npm cache after module updates..."
if [ "$DRY_RUN" = true ]; then
  log "(dry) would run: npm cache clean --force"
else
  if npm_exec cache clean --force 2>&1 | tee -a "$LOG_FILE"; then
    log "npm cache cleaned successfully"
  else
    log "npm cache clean failed (non-critical)"
  fi
fi

# --- Module-specific post-update patches ---
# For modules that are updated from upstream but need a local runtime safety patch
# (because upstream code may call .stop() without guarding), apply an idempotent
# in-place patch after updates. This re-applies each run so updates won't reintroduce
# the crash.
apply_rtsp_stop_guard() {
  local modpath="$1"
  local jf="$modpath/node_helper.js"
  if [ ! -f "$jf" ]; then
    log "apply_rtsp_stop_guard: $jf not found — skipping"
    return 0
  fi
  # Detect whether we've already patched the file by searching for our marker
  if grep -q "// safe-stop-guard-applied" "$jf" 2>/dev/null; then
    log "apply_rtsp_stop_guard: already patched"
    return 0
  fi
  ts=$(date +"%Y%m%d_%H%M%S")
  bak="$jf.bak.$ts"
  if [ "$DRY_RUN" = true ]; then
    log "(dry) would backup $jf -> $bak and inline-guard .stop() calls"
    return 0
  fi
  log "Backing up $jf -> $bak"
  cp -p "$jf" "$bak" || { log "Failed to backup $jf"; return 2; }

  log "Patching $jf: replacing risky this.ffmpegStreams[...].stop() calls with guarded versions"
  # Use perl to replace occurrences of this.ffmpegStreams[<idx>].stop() with guarded code
  perl -0777 -pe '
    s/this\.ffmpegStreams\[([^\]]+)\]\.stop\(\)/if (this.ffmpegStreams[$1] && typeof this.ffmpegStreams[$1].stop === "function") { this.ffmpegStreams[$1].stop(); } else if (this.ffmpegStreams[$1] && typeof this.ffmpegStreams[$1].destroy === "function") { this.ffmpegStreams[$1].destroy(); } else { try { this.ffmpegStreams[$1] && this.ffmpegStreams[$1].close && this.ffmpegStreams[$1].close(); } catch (e) {} }\/\/ safe-stop-guard-applied/g;s/\n\n\n/\n\n/g' "$jf" > "$jf.patched" || { log "perl patch failed"; return 2; }

  mv "$jf.patched" "$jf" || { log "Failed to move patched file into place"; return 2; }
  log "Patch applied to $jf (backup at $bak)"
  return 0
}

# Re-run through modules to apply any post-update patches (idempotent)
# DISABLED: RTSPStream patch was causing stream loading issues
# for mod in "$MODULES_DIR"/*; do
#   [ -d "$mod" ] || continue
#   name=$(basename "$mod")
#   if [ "$name" = "MMM-RTSPStream" ]; then
#     apply_rtsp_stop_guard "$mod"
#   fi
# done

if [ "$DRY_RUN" = true ]; then
  log "DRY RUN finished — no restarts performed"
  exit 0
fi

if [ "$RUN_RASPBIAN_UPDATE" = true ]; then
  log "RUN_RASPBIAN_UPDATE=true — will create backup (if enabled) and run apt-get full-upgrade now"
  if [ "$MAKE_MODULE_BACKUP" = true ]; then
    if ! backup_modules; then
      log "Module backup failed — aborting raspbian update"
    fi
  fi
  if apt_update_with_retry; then
    log "Raspbian packages updated successfully"
    
    # Clean apt cache after successful upgrade
    log "Cleaning apt package cache..."
    sudo_prefix=$(apt_get_prefix)
    if [ -n "$sudo_prefix" ]; then
      $sudo_prefix apt-get clean 2>&1 | tee -a "$LOG_FILE" || log "apt-get clean failed"
      $sudo_prefix apt-get autoclean 2>&1 | tee -a "$LOG_FILE" || log "apt-get autoclean failed"
    else
      apt-get clean 2>&1 | tee -a "$LOG_FILE" || log "apt-get clean failed"
      apt-get autoclean 2>&1 | tee -a "$LOG_FILE" || log "apt-get autoclean failed"
    fi
    log "Apt cache cleaned"
    
    # check for reboot requirement
    if [ -f /var/run/reboot-required ]; then
      log "Reboot required after apt upgrade"
      if [ "$AUTO_REBOOT_AFTER_UPGRADE" = true ]; then
        log "AUTO_REBOOT_AFTER_UPGRADE=true — rebooting now"
        if [ "$DRY_RUN" = true ]; then
          log "(dry) would reboot now"
        else
          sudo_prefix=$(apt_get_prefix)
          if [ -n "$sudo_prefix" ]; then
            $sudo_prefix reboot || true
          else
            reboot || true
          fi
        fi
      else
        log "AUTO_REBOOT_AFTER_UPGRADE=false — not rebooting automatically"
      fi
    fi
  else
    log "Raspbian update failed or skipped — continuing"
  fi
fi

if [ "$updated_any" = true ]; then
  log "Updates detected"
  if [ "$RESTART_AFTER_UPDATES" = true ]; then
    log "Updates applied - system will reboot to ensure all modules (especially RTSPStream) start correctly"
    
    # Comprehensive RTSPStream health check before reboot
    log "=== RTSPStream Pre-Reboot Health Check ==="
    
    # Check ffmpeg availability before reboot (important for RTSPStream)
    if command -v ffmpeg >/dev/null 2>&1; then
      ffmpeg_ver=$(ffmpeg -version 2>&1 | head -n 1 || echo "unknown")
      log "✓ ffmpeg is available: $ffmpeg_ver"
      
      # Check ffmpeg RTSP support
      if ffmpeg -formats 2>&1 | grep -q "rtsp"; then
        log "✓ ffmpeg has RTSP format support"
      else
        log "✗ WARNING: ffmpeg may lack RTSP support!"
      fi
      
      # Check ffmpeg H.264 codec support (commonly used for RTSP streams)
      if ffmpeg -codecs 2>&1 | grep -q "h264"; then
        log "✓ ffmpeg has H.264 codec support"
      else
        log "✗ WARNING: ffmpeg may lack H.264 codec support!"
      fi
    else
      log "✗ CRITICAL: ffmpeg not found in PATH - RTSPStream will NOT work!"
      log "  Installing ffmpeg now..."
      sudo_prefix=$(apt_get_prefix)
      if [ -n "$sudo_prefix" ]; then
        $sudo_prefix apt-get update 2>&1 | tee -a "$LOG_FILE" || true
        $sudo_prefix apt-get install -y ffmpeg 2>&1 | tee -a "$LOG_FILE" || log "Failed to install ffmpeg"
      fi
    fi
    
    # Check if RTSPStream module L and is properly installed
    rtsp_module="$MODULES_DIR/MMM-RTSPStream"
    if [ -d "$rtsp_module" ]; then
      log "✓ RTSPStream module directory exists"
      
      # Check critical files
      if [ -f "$rtsp_module/node_helper.js" ]; then
        log "✓ node_helper.js exists"
      else
        log "✗ CRITICAL: node_helper.js missing for RTSPStream!"
      fi
      
      if [ -f "$rtsp_module/MMM-RTSPStream.js" ]; then
        log "✓ MMM-RTSPStream.js exists"
      else
        log "✗ WARNING: MMM-RTSPStream.js missing!"
      fi
      
      if [ -d "$rtsp_module/node_modules" ]; then
        log "✓ node_modules directory exists"
        # Count installed packages
        pkg_count=$(find "$rtsp_module/node_modules" -maxdepth 1 -type d | wc -l)
        log "  Found $pkg_count packages in node_modules"
      else
        log "✗ CRITICAL: node_modules directory missing for RTSPStream!"
      fi
      
      # Check for stale ffmpeg processes
      if pgrep -f "ffmpeg.*9999" >/dev/null 2>&1; then
        log "✗ WARNING: Stale ffmpeg processes detected - cleaning up..."
        pkill -TERM -f "ffmpeg.*9999" 2>&1 | tee -a "$LOG_FILE" || true
        sleep 2
        pkill -KILL -f "ffmpeg.*9999" 2>&1 | tee -a "$LOG_FILE" || true
        log "  Stale processes cleaned"
      else
        log "✓ No stale ffmpeg processes found"
      fi
    else
      log "  RTSPStream module not installed (skipping checks)"
    fi
    
    log "=== End RTSPStream Health Check ==="
    
    # Save pm2 processes before reboot
    if command -v pm2 >/dev/null 2>&1; then
      log "Saving pm2 process list before reboot"
      pm2 save 2>&1 | tee -a "$LOG_FILE" || log "pm2 save failed"
    fi
    
    # Reboot the system
    sudo_prefix=$(apt_get_prefix)
    log "Rebooting system now..."
    if [ "$DRY_RUN" = true ]; then
      log "(dry) would reboot system now"
    else
      sync  # Ensure all file system writes are completed
      if [ -n "$sudo_prefix" ]; then
        $sudo_prefix reboot || log "Reboot command failed"
      else
        reboot || log "Reboot command failed (no sudo available)"
      fi
    fi
  else
    log "RESTART_AFTER_UPDATES is false — no reboot will be performed"
  fi
else
  log "No updates were applied — no reboot necessary"
fi

# Ensure pm2 autostart is configured after any updates
log "Checking pm2 autostart configuration"
if command -v pm2 >/dev/null 2>&1; then
  # Clean up any errored pm2 processes first
  if [ "$DRY_RUN" = true ]; then
    log "(dry) would clean up errored pm2 processes"
  else
    errored_procs=$(pm2 jlist 2>/dev/null | jq -r '.[] | select(.pm2_env.status == "errored") | .name' 2>/dev/null || echo "")
    if [ -n "$errored_procs" ]; then
      log "Found errored pm2 processes, cleaning up: $errored_procs"
      echo "$errored_procs" | while read -r proc; do
        [ -n "$proc" ] && pm2 delete "$proc" 2>&1 | tee -a "$LOG_FILE" || true
      done
    fi
  fi
  
  # Save current pm2 processes
  if [ "$DRY_RUN" = true ]; then
    log "(dry) would run: pm2 save"
  else
    pm2 save 2>&1 | tee -a "$LOG_FILE" || log "pm2 save failed"
  fi
  
  # Check if startup script is installed
  startup_check=$(pm2 startup 2>&1 | grep -c "sudo env" || echo "0")
  if [ "$startup_check" -gt 0 ]; then
    log "pm2 startup not configured - showing startup command"
    pm2 startup 2>&1 | tee -a "$LOG_FILE"
    log "IMPORTANT: Run the sudo command shown above to enable pm2 autostart"
  else
    log "pm2 startup appears to be configured"
    # Verify the startup script L
    if [ -f /etc/systemd/system/pm2-pi.service ] || [ -f /etc/systemd/system/pm2-$USER.service ]; then
      log "pm2 systemd service found"
      # Ensure service is enabled and running
      if [ "$DRY_RUN" = true ]; then
        log "(dry) would check and enable pm2 systemd service"
      else
        sudo_prefix=$(apt_get_prefix)
        if [ -n "$sudo_prefix" ]; then
          log "Checking pm2-$USER service status:"
          $sudo_prefix systemctl is-enabled pm2-$USER 2>&1 | tee -a "$LOG_FILE" || true
          $sudo_prefix systemctl is-active pm2-$USER 2>&1 | tee -a "$LOG_FILE" || true
          $sudo_prefix systemctl enable pm2-$USER 2>&1 | tee -a "$LOG_FILE" || log "Failed to enable pm2-$USER service"
          
          # Check if pm2 process is actually starting the right app
          log "Current pm2 processes after startup check:"
          pm2 list 2>&1 | tee -a "$LOG_FILE" || true
          
          # Check if MagicMirror process L and is healthy
          mm_status=$(pm2 show "$PM2_PROCESS_NAME" 2>/dev/null | grep -E "(status|pid|uptime)" || echo "Process not found")
          log "MagicMirror process status: $mm_status"
          
          # If process is errored or not found, try to restart
          if pm2 show "$PM2_PROCESS_NAME" 2>/dev/null | grep -q "errored\|stopped"; then
            log "MagicMirror process is errored/stopped, attempting restart"
            pm2 restart "$PM2_PROCESS_NAME" 2>&1 | tee -a "$LOG_FILE" || log "pm2 restart failed"
          fi
        fi
      fi
    else
      log "pm2 systemd service not found - run 'pm2 startup' manually"
    fi
  fi
else
  log "pm2 not found - cannot configure autostart"
fi

# --- Automatische Log-Fehlerprüfung & Korrektur (ab Feb 2026) ---
scan_and_fix_log_errors() {
  local logfile="$LOG_FILE"
  local error_found=false
  local fix_attempted=false
  if [ ! -f "$logfile" ]; then
    return 0
  fi
  # Prüfe typische Fehler im Log
  if grep -qiE "electron.*not found|electron fehlt|npm install im MagicMirror-Ordner fehlgeschlagen" "$logfile"; then
    error_found=true
    log "Automatische Korrektur: electron-Fehler erkannt im Log. Versuche npm install im MagicMirror-Ordner..."
    pushd "$MAGICMIRROR_DIR" >/dev/null
    if npm install 2>&1 | tee -a "$LOG_FILE"; then
      log "Automatische Korrektur: npm install erfolgreich ausgeführt (electron installiert)"
      fix_attempted=true
    else
      log "Automatische Korrektur: npm install fehlgeschlagen! Bitte manuell prüfen."
    fi
    popd >/dev/null
  fi
  # Git-Lock-Fehler erkennen und beheben
  if grep -qiE "index.lock|Another git process" "$logfile"; then
    error_found=true
    log "Automatische Korrektur: Git-Lock-Fehler erkannt. Entferne index.lock Dateien in allen Modulen..."
    find "$MODULES_DIR" -type f -name "index.lock" -exec rm -f {} \; 2>/dev/null
    find "$MAGICMIRROR_DIR" -type f -name "index.lock" -exec rm -f {} \; 2>/dev/null
    log "Automatische Korrektur: Alle index.lock Dateien entfernt."
    fix_attempted=true
  fi
  # Fehlende Berechtigungen (chown)
  if grep -qiE "chown failed|sudo chown failed|permission denied" "$logfile"; then
    error_found=true
    log "Automatische Korrektur: Berechtigungsfehler erkannt. Setze Besitzrechte auf $CHOWN_USER..."
    chown -R "$CHOWN_USER":"$CHOWN_USER" "$MAGICMIRROR_DIR" 2>&1 | tee -a "$LOG_FILE"
    chown -R "$CHOWN_USER":"$CHOWN_USER" "$MODULES_DIR" 2>&1 | tee -a "$LOG_FILE"
    log "Automatische Korrektur: Besitzrechte gesetzt."
    fix_attempted=true
  fi
  # npm cache Fehler
  if grep -qiE "npm cache.*corrupt|npm ERR! cache" "$logfile"; then
    error_found=true
    log "Automatische Korrektur: npm cache Fehler erkannt. Leere npm cache..."
    npm cache clean --force 2>&1 | tee -a "$LOG_FILE"
    log "Automatische Korrektur: npm cache geleert."
    fix_attempted=true
  fi
  # Fehlende package-lock.json
  if grep -qiE "ENOENT.*package-lock.json" "$logfile"; then
    error_found=true
    log "Automatische Korrektur: Fehlende package-lock.json erkannt. Führe npm install in allen Modulen aus..."
    for mod in "$MODULES_DIR"/*; do
      [ -d "$mod" ] || continue
      if [ -f "$mod/package.json" ] && [ ! -f "$mod/package-lock.json" ]; then
        pushd "$mod" >/dev/null
        npm install 2>&1 | tee -a "$LOG_FILE"
        popd >/dev/null
      fi
    done
    log "Automatische Korrektur: npm install für fehlende package-lock.json durchgeführt."
    fix_attempted=true
  fi
  # npm audit fix bei bekannten Schwachstellen
  if grep -qiE "npm audit report|found [0-9]+ vulnerabilities" "$logfile"; then
    error_found=true
    log "Automatische Korrektur: npm audit Schwachstellen erkannt. Versuche npm audit fix in MagicMirror..."
    pushd "$MAGICMIRROR_DIR" >/dev/null
    npm audit fix --force 2>&1 | tee -a "$LOG_FILE"
    popd >/dev/null
    log "Automatische Korrektur: npm audit fix durchgeführt."
    fix_attempted=true
  fi
  # Weitere typische Fehler prüfen und ggf. korrigieren
  if grep -qiE "Cannot find module 'datauri'|datauri FAIL" "$logfile"; then
    error_found=true
    log "Automatische Korrektur: datauri-Fehler erkannt im Log. Versuche npm install datauri..."
    pushd "$MODULES_DIR/MMM-RTSPStream" >/dev/null
    if npm install datauri 2>&1 | tee -a "$LOG_FILE"; then
      log "Automatische Korrektur: datauri erfolgreich installiert."
      fix_attempted=true
    else
      log "Automatische Korrektur: Installation von datauri fehlgeschlagen! Bitte manuell prüfen."
    fi
    popd >/dev/null
  fi
  # Bei Fehlern E-Mail senden
  if [ "$error_found" = true ]; then
    send_email "Automatische Log-Fehlerkorrektur" "Fehler wurden im Log erkannt und Korrekturversuche durchgeführt. Details siehe Log." "error"
  fi
  return 0
}

# Am Ende des Skripts ausführen
scan_and_fix_log_errors

log "Update run finished"
exit 0
