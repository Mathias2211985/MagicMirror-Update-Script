Update Modules Script for Raspberry Pi

This folder contains a script to automatically update MagicMirror modules (git + npm) and optionally restart the pm2 process.

Files
- update_modules.sh — main script. Configure the variables at the top before use.

Usage
1) Copy to the Raspberry Pi, for example into `/home/pi/scripts/` and make executable:

```bash
# on the Pi
mkdir -p ~/scripts
scp update_modules.sh pi@raspberrypi:/home/pi/scripts/
ssh pi@raspberrypi
chmod +x ~/scripts/update_modules.sh
```

2) Edit configuration at the top of `update_modules.sh`:
- `MODULES_DIR` — Pfad zu deinem MagicMirror `modules` Ordner (z. B. `/home/pi/MagicMirror/modules`).
- `PM2_PROCESS_NAME` — Name des pm2-Prozesses (z. B. `mm` oder `magicmirror`).
- `RESTART_AFTER_UPDATES` — `true` oder `false`.
- `DRY_RUN` — `true` um zuerst eine Simulation zu fahren.
- `LOG_FILE` — Pfad zur Log-Datei.

3) Dry-run testen:

```bash
# auf dem Pi
DRY_RUN=true ~/scripts/update_modules.sh
# oder: export DRY_RUN=true; ~/scripts/update_modules.sh
```

4) Wenn alles in Ordnung ist, echten Lauf starten:

```bash
~/scripts/update_modules.sh
```

Cron / Timer
Wenn dein Mirror bereits zweimal täglich neu startet und du das Update während der Neustarts ausführen möchtest, plane den Cron-Job so, dass das Update kurz vor dem Restart läuft.

Beispiel crontab (editiere mit `crontab -e`):
# Ausführung täglich um 02:50 und 14:50 — passe Zeiten an deine PM2-Restarts an
50 2 * * * /home/pi/scripts/update_modules.sh >> /home/pi/update_modules.log 2>&1
50 14 * * * /home/pi/scripts/update_modules.sh >> /home/pi/update_modules.log 2>&1

Alternativ: systemd-timer (wenn bevorzugt) — ich kann das für dich erstellen, wenn du möchtest.

Spezialfälle
- Einige Module benötigen spezielle npm-Befehle. Das Skript enthält bereits eine Ausnahme für `MMM-Webuntis` und verwendet dort `npm ci --omit=dev`.
- Wenn beim `git fetch`/`git pull` die Fehlermeldung auftaucht, dass "another git process seems to be running" oder ein `index.lock` existiert, dann wartet das Skript automatisch und versucht mehrmals erneut (exponentielles Backoff). Falls das Problem bestehen bleibt, wird das Modul übersprungen und ein Eintrag ins Log geschrieben.

Du kannst weitere Modul-Ausnahmen in der `case`-Sektion im Skript (`update_modules.sh`) hinzufügen.


Optionales Raspbian-Update (full-upgrade)
---------------------------------
Das Skript kann optional nach den Modul-Updates ein komplettes, nicht-interaktives `apt-get full-upgrade` ausführen (empfohlen, wenn du Systempakete komplett aktuell halten willst). Standardmäßig ist diese Option aktiviert. Konfiguration in `update_modules.sh`:

```
RUN_RASPBIAN_UPDATE=true
MAKE_MODULE_BACKUP=true   # erstellt vorher ein tar.gz Backup des modules-Ordners
AUTO_REBOOT_AFTER_UPGRADE=false
```

Details und Hinweise:
- Das Skript verwendet `DEBIAN_FRONTEND=noninteractive` und `apt-get full-upgrade` mit Dpkg-Optionen, um interaktive Dialoge zu vermeiden.
- Vor dem Upgrade wird (wenn aktiviert) ein komprimiertes Backup deines `modules`-Ordners nach `~/module_backups/` geschrieben.
- `apt-get full-upgrade` ist mächtiger als `upgrade`: es kann Abhängigkeiten anlegen und Pakete entfernen. Daher ist ein Backup und ein kurzes Prüfintervall empfehlenswert.
- Das Skript behandelt apt/dpkg-Locks mit einem Retry/Backoff-Mechanismus.
- Falls ein Reboot erforderlich ist, wird das erkannt; das Skript kann optional automatisch rebooten (siehe `AUTO_REBOOT_AFTER_UPGRADE`). Standardmäßig bleibt das deaktiviert, da du sagtest, dass ein Reboot ohnehin extern erfolgt.

Bevor du ein automatisches full-upgrade in Produktion nutzt, empfehle ich einen Dry‑Run:

```
DRY_RUN=true ~/scripts/update_modules.sh
```



Hinweise und Edge-Cases
- Lokale Änderungen: Repositories mit lokalen Änderungen werden übersprungen, um Merge-Konflikte zu vermeiden. Diese müssen manuell bereinigt werden.
- Git Pull: Das Skript verwendet `git pull --ff-only`, um automatische Merge-Commits zu vermeiden.
- npm: Wenn `package-lock.json` vorhanden ist, verwendet das Skript `npm ci`, sonst `npm install`.
- pm2: Das Skript prüft, ob `pm2` im PATH ist; wenn nicht, überspringt es den Neustart.

Nächste Schritte (ich kann sie für dich übernehmen):
- Ich kann `systemd` Timer & Service Unit Dateien erzeugen.
- Ich kann Beispiel-Cron-Einträge direkt in die Crontab schreiben (nur wenn du mir erlaubst, Befehle auszuführen).
- Ich kann ein optionales Backup/Rollback-Skript hinzufügen, das vor einem Update Snapshots macht.

Wenn du möchtest, passe mir bitte kurz diese Werte an:
- Pfad zu deinem `modules`-Ordner (z. B. `/home/pi/MagicMirror/modules`)
- pm2-Prozessname (z. B. `mm`)
- Ob ich die Cron/Timer-Dateien für dich generieren soll
