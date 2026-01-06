#!/usr/bin/env bash
# MagicMirror Update Script - Beispiel-Konfigurationsdatei
# 
# Diese Datei kopieren nach:
#   $HOME/.config/magicmirror-update/config.sh (für Benutzer-Konfiguration)
# oder:
#   /etc/magicmirror-update.conf (für systemweite Konfiguration)
#
# Die Benutzer-Konfiguration hat Vorrang vor der System-Konfiguration.
# Nur die Werte eintragen die vom Standard abweichen sollen.

# === Pfade ===
# MODULES_DIR="/home/pi/MagicMirror/modules"
# MAGICMIRROR_DIR="/home/pi/MagicMirror"
# BACKUP_DIR="$HOME/module_backups"
# LOG_FILE="$HOME/update_modules.log"

# === PM2 Konfiguration ===
# PM2_PROCESS_NAME="MagicMirror"

# === Update-Verhalten ===
# UPDATE_MAGICMIRROR_CORE=true          # MagicMirror Core aktualisieren
# RESTART_AFTER_UPDATES=true            # Nach Updates neustarten
# DRY_RUN=false                         # Trockenlauf ohne Änderungen
# AUTO_DISCARD_LOCAL=true               # Lokale Änderungen verwerfen (DESTRUKTIV!)

# === Raspbian/Debian Updates ===
# RUN_RASPBIAN_UPDATE=true              # apt full-upgrade ausführen
# APT_UPDATE_MAX_ATTEMPTS=4             # Wiederholungsversuche bei Lock

# === Backup ===
# MAKE_MODULE_BACKUP=true               # Backup vor Updates erstellen

# === Reboot-Verhalten ===
# AUTO_REBOOT_AFTER_UPGRADE=true        # Nach apt-upgrade neustarten wenn nötig
# AUTO_REBOOT_AFTER_SCRIPT=false        # Nach jedem Skript-Lauf neustarten
# REBOOT_ONLY_ON_UPDATES=true           # Nur neustarten wenn Updates installiert wurden

# === E-Mail Benachrichtigungen ===
# Benötigt ein konfiguriertes Mail-Tool (mail, sendmail, msmtp, oder ssmtp)
EMAIL_ENABLED=false                     # E-Mail aktivieren
EMAIL_RECIPIENT=""                      # Empfänger-Adresse
EMAIL_SUBJECT_PREFIX="[MagicMirror Update]"
EMAIL_ON_SUCCESS=false                  # Bei Erfolg benachrichtigen
EMAIL_ON_ERROR=true                     # Bei Fehlern benachrichtigen

# === Log-Rotation ===
LOG_ROTATION_ENABLED=true               # Log-Rotation aktivieren
LOG_MAX_SIZE_KB=5120                    # Max. Log-Größe (5MB)
LOG_KEEP_COUNT=5                        # Anzahl alter Logs behalten

# === Healthcheck ===
HEALTHCHECK_BEFORE_REBOOT=true          # MagicMirror vor Reboot testen
HEALTHCHECK_TIMEOUT=30                  # Timeout in Sekunden
HEALTHCHECK_URL="http://localhost:8080" # URL zum Testen

# === Benutzer für Datei-Berechtigungen ===
# CHOWN_USER="pi"
