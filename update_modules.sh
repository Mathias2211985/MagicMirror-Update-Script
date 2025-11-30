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
PM2_PROCESS_NAME="MagicMirror"               # Name des pm2 Prozesses (z. B. 'MagicMirror')
RESTART_AFTER_UPDATES=true                   # true = restart pm2 process wenn Updates vorhanden
DRY_RUN=false                                # true = nur berichten, nichts verändern
AUTO_DISCARD_LOCAL=true                       # true = automatisch lokale Änderungen verwerfen (reset --hard + clean) - DESTRUKTIV
LOG_FILE="$HOME/update_modules.log"
RUN_RASPBIAN_UPDATE=true                      # true = run apt-get full-upgrade on the Raspberry Pi after module updates (requires sudo or root)
MAKE_MODULE_BACKUP=true                       # true = create a tar.gz backup of the modules directory before apt upgrade
AUTO_REBOOT_AFTER_UPGRADE=false               # true = reboot automatically after apt full-upgrade if required (we keep false by default)
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
    # Always invoke npm via sudo when sudo exists (user requested this)
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

for mod in "$MODULES_DIR"/*; do
  [ -d "$mod" ] || continue
  name=$(basename "$mod")
  log "--- Processing module: $name ---"

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

  # 2) npm update/install if package.json exists
  if [ -f "$mod/package.json" ]; then
    log "package.json found — running npm (mode depends on module)"
    
    # Universal npm strategy: use npm ci for clean install if lockfile exists and module was git-updated
    # Otherwise use npm install for flexibility
    npm_special_cmd=""
    
    # If module was just updated via git, prefer clean install to avoid dependency conflicts
    if [ "${module_git_updated:-false}" = "true" ] && [ -f "$mod/package-lock.json" ]; then
      npm_special_cmd="ci"
      log "Module was git-updated and has lockfile - using npm ci for clean install"
      
      # For modules that need extra cleanup after git updates, remove node_modules first
      case "$name" in
        MMM-RTSPStream|MMM-Fuel)
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
            
            # Strategy 1: Try npm ci if lockfile exists
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

  log "--- Done: $name ---"
done

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
    log "Restarting pm2 process: $PM2_PROCESS_NAME"
    if command -v pm2 >/dev/null 2>&1; then
      if pm2 restart "$PM2_PROCESS_NAME" 2>&1 | tee -a "$LOG_FILE"; then
        log "pm2 restart succeeded"
      else
        log "pm2 restart FAILED — capturing 'pm2 list' for debugging"
        pm2 list 2>&1 | tee -a "$LOG_FILE"
        log "If the process name is different, set PM2_PROCESS_NAME in the script to the correct name. To see processes run: pm2 ls"
      fi
    else
      log "pm2 not found in PATH — skipping restart"
    fi
  else
    log "RESTART_AFTER_UPDATES is false — not restarting pm2"
  fi
else
  log "No updates were applied — no restart necessary"
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
    # Verify the startup script exists
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
          
          # Check if MagicMirror process exists and is healthy
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
