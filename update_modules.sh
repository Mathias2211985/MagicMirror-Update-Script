#!/usr/bin/env bash
# update_modules.sh
# Durchsucht das modules-Verzeichnis und führt für jedes Modul:
# - git pull (wenn .git vorhanden & keine lokalen Änderungen)
# - npm install (wenn package.json vorhanden)
# Optional: Neustart des pm2-Prozesses wenn Updates erfolgten

set -euo pipefail
IFS=$'\n\t'

# --- Konfiguration (anpassen) ---
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
AUTO_REBOOT_AFTER_UPGRADE=true               # true = reboot automatically after apt full-upgrade if required (we keep false by default)
AUTO_REBOOT_AFTER_SCRIPT=true                # true = reboot the Pi after the script finishes (regardless of success/failure). DRY_RUN overrides this.
APT_UPDATE_MAX_ATTEMPTS=4                      # how many times to retry apt when dpkg/apt lock is present
BACKUP_DIR="$HOME/module_backups"            # where to store module backups

# -- Spezialfälle: manche Module sollen mit anderem npm-Befehl aktualisiert werden.
# Hier per Modulname anpassen. Beispiel: MMM-Webuntis braucht `npm ci --omit=dev`.
# Ein einfacher case-Block wird pro Modul verwendet.
# Wenn kein Eintrag vorhanden, nutzt das Skript das Standardverhalten (npm ci wenn lockfile, sonst npm install).
# ---------------------------------

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }
log() { echo "$(timestamp) - $*" | tee -a "$LOG_FILE"; }

# detect if sudo is available; we'll prefer to call npm with sudo if present
SUDO_CMD=""
if command -v sudo >/dev/null 2>&1; then
  SUDO_CMD="sudo"
fi
# user to own module files after npm (change if you use different user)
CHOWN_USER="pi"

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

# Final-exit handler: if requested, reboot the Pi after the script finishes.
# This runs on EXIT (normal or due to error). We skip the reboot when DRY_RUN=true.
on_exit_reboot() {
  rc=$?
  # Do not reboot in dry-run mode
  if [ "${DRY_RUN:-false}" = true ]; then
    log "DRY_RUN=true — skipping final reboot (exit code $rc)"
    return 0
  fi

  if [ "${AUTO_REBOOT_AFTER_SCRIPT:-false}" != true ]; then
    return 0
  fi

  log "AUTO_REBOOT_AFTER_SCRIPT=true — performing final reboot now (script exit code $rc)"
  sudo_prefix=$(apt_get_prefix)
  # call reboot via sudo if necessary; ignore any failure to avoid masking original exit status
  if [ -n "$sudo_prefix" ]; then
    $sudo_prefix reboot || log "reboot command failed (attempted: $sudo_prefix reboot)"
  else
    reboot || log "reboot command failed (attempted: reboot)"
  fi
}

# Install trap so on_exit_reboot runs when the script exits for any reason
trap on_exit_reboot EXIT

if [ "$DRY_RUN" = true ]; then
  log "DRY RUN enabled — no changes will be made"
fi

if [ ! -d "$MODULES_DIR" ]; then
  log "ERROR: modules directory '$MODULES_DIR' does not exist"
  exit 1
fi

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
        
        # Run node --run install-mm to install dependencies
        log "Running: node --run install-mm"
        if command -v node >/dev/null 2>&1; then
          if node --run install-mm 2>&1 | tee -a "$LOG_FILE"; then
            log "✓ MagicMirror dependencies installed successfully"
            chown_module "$MAGICMIRROR_DIR"
          else
            log "ERROR: node --run install-mm failed for MagicMirror core"
            popd >/dev/null
            return 2
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
  
  popd >/dev/null
  log "=== MagicMirror Core Update Complete ==="
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

for mod in "$MODULES_DIR"/*; do
  [ -d "$mod" ] || continue
  name=$(basename "$mod")
  log "--- Processing module: $name ---"
  
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
      local old_head new_head
      old_head=$(git rev-parse --verify HEAD 2>/dev/null || echo "none")
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

        log "Running: git pull --ff-only"
        if git pull --ff-only 2>&1 | tee -a "$LOG_FILE"; then
          new_head=$(git rev-parse --verify HEAD 2>/dev/null || echo "none")
          if [ "$old_head" != "$new_head" ]; then
            log "git pull updated HEAD for $name ($old_head -> $new_head)"
            return 0
          else
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
          else
            rc=$?
            if [ $rc -eq 1 ]; then
              :
            else
              log "Warning: git update failed for $name after discarding local changes (see logs)"
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
        else
          # if return code 1 -> up-to-date; 2 -> error/skip
          rc=$?
          if [ $rc -eq 1 ]; then
            : # up-to-date
          else
            log "Warning: git update failed for $name (see logs)"
          fi
        fi
      fi
    fi
    popd >/dev/null
  else
    log "Not a git repo"
  fi

  # 2) npm update/install if package.json L
  if [ -f "$mod/package.json" ]; then
    log "package.json found — running npm (mode depends on module)"
    
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
        # Some npm versions do not support `--omit=dev`. Use a broader install to be compatible.
        npm_special_cmd="install --only=production"
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
            
            # Strategy 3: Last resort - install with production-only flag
            if [ $rc -ne 0 ]; then
              log "Fallback 3: Trying npm install --only=production"
              if npm_exec --prefix "$modpath" install --only=production --no-audit --no-fund >>"$LOG_FILE" 2>&1; then
                log "Fallback npm install --only=production succeeded"
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
        # Universal strategy: prefer npm ci with lockfile, otherwise install
        if [ -f "$mod/package-lock.json" ]; then
          log "Universal strategy: Using npm ci (lockfile present)"
          if run_npm_with_fallback "$mod" "ci"; then
            updated_any=true
          else
            log "npm ci with fallbacks failed for $name"
          fi
        else
          log "Universal strategy: Using npm install (no lockfile)"
          if run_npm_with_fallback "$mod" "install"; then
            updated_any=true
          else
            log "npm install with fallbacks failed for $name"
          fi
        fi
      fi
    fi
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
  
  log "--- Done: $name ---"
done

# Clean npm cache after all module updates to free up disk space
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

log "Update run finished"
exit 0
