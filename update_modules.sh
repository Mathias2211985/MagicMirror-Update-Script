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
          if git_pull_with_retry; then
            updated_any=true
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
        if git_pull_with_retry; then
          updated_any=true
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
    # Determine if this module needs a special npm command (module-specific override)
    npm_special_cmd=""
    case "$name" in
      MMM-Webuntis)
        # Some npm versions do not support `--omit=dev`. Use a broader install to be compatible.
        npm_special_cmd="install --only=production"
        ;;
      # add other module-specific overrides here, e.g.
      # MMM-Example)
      #   npm_special_cmd="install --no-audit --no-fund"
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
      if [ -n "$npm_special_cmd" ]; then
        # run npm with fallback logic: try the special command, if it fails because the npm
        # binary doesn't support that flag/command, fall back to safer alternatives.
        run_npm_with_fallback() {
          local modpath="$1"
          local cmd="$2"
          local rc=0
          log "Running: ${SUDO_CMD:+$SUDO_CMD }npm --prefix \"$modpath\" $cmd"
          tmpout=$(mktemp)
          if npm_exec --prefix "$modpath" $cmd --no-audit --no-fund >"$tmpout" 2>&1; then
            cat "$tmpout" | tee -a "$LOG_FILE"
            rc=0
            # restore ownership so files are usable by the normal user
            chown_module "$modpath"
          else
            cat "$tmpout" | tee -a "$LOG_FILE"
            rc=1
          fi
          if [ $rc -ne 0 ]; then
            # If npm says 'Unknown command' or similar, try fallbacks
            if grep -qi "Unknown command" "$tmpout" || grep -qi "unknown" "$tmpout"; then
              log "npm reported unknown command for '$cmd' - trying fallback 'ci' without extra flags"
              if npm_exec --prefix "$modpath" ci --no-audit --no-fund >>"$LOG_FILE" 2>&1; then
                log "fallback npm ci succeeded for $modpath"
                rc=0
                chown_module "$modpath"
              else
                log "fallback npm ci failed for $modpath — trying 'install --only=production'"
                if npm_exec --prefix "$modpath" install --only=production --no-audit --no-fund >>"$LOG_FILE" 2>&1; then
                  log "fallback npm install --only=production succeeded for $modpath"
                  rc=0
                  chown_module "$modpath"
                else
                  log "all npm fallbacks failed for $modpath"
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

        if run_npm_with_fallback "$mod" "$npm_special_cmd"; then
          updated_any=true
        else
          log "npm ($npm_special_cmd) ultimately failed for $name"
        fi
      else
        # Prefer npm ci if package-lock.json exists for deterministic installs
        if [ -f "$mod/package-lock.json" ]; then
          log "Using npm ci (lockfile present)"
          if npm_exec --prefix "$mod" ci --no-audit --no-fund 2>&1 | tee -a "$LOG_FILE"; then
            log "npm ci succeeded for $name"
            updated_any=true
            chown_module "$mod"
          else
            log "npm ci failed for $name"
          fi
        else
          if npm_exec --prefix "$mod" install --no-audit --no-fund 2>&1 | tee -a "$LOG_FILE"; then
            log "npm install succeeded for $name"
            updated_any=true
            chown_module "$mod"
          else
            log "npm install failed for $name"
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
for mod in "$MODULES_DIR"/*; do
  [ -d "$mod" ] || continue
  name=$(basename "$mod")
  if [ "$name" = "MMM-RTSPStream" ]; then
    apply_rtsp_stop_guard "$mod"
  fi
done

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

log "Update run finished"
exit 0
