#!/usr/bin/env bash
# Install the RGB-Pi CRT setup on a Raspberry Pi 5 running Lakka, over SSH from another computer. Safe to run again.
#   ./install.sh [user@host]   (default: root@lakka.local)
set -euo pipefail
cd "$(dirname "$0")"
HOST="${1:-root@lakka.local}"

ssh "$HOST" 'grep -q "Raspberry Pi 5" /proc/device-tree/model' || { echo "$HOST isn't a Raspberry Pi 5." >&2; exit 1; }

# Interlaced modes (480i) need a bootloader from 2024-11-12 or later, which carries the RP1 firmware for PIO.
stamp=$(ssh "$HOST" 'vcgencmd bootloader_version 2>/dev/null | sed -n "s/^timestamp //p"')
if [ -n "$stamp" ] && [ "$stamp" -lt 1731369600 ]; then
    echo "Warning: the bootloader is older than 2024-11-12, so 480i won't work. Run: ssh $HOST rpi-eeprom-update -a, then reboot."
fi

# Keep one copy of the original files, the first time only.
ssh "$HOST" 'mount -o remount,rw /flash
    [ -e /flash/config.txt.pre-crt ] || cp /flash/config.txt /flash/config.txt.pre-crt
    cfg=/storage/.config/retroarch/retroarch.cfg
    [ -e $cfg ] && [ ! -e $cfg.pre-crt ] && cp $cfg $cfg.pre-crt || true'

# Boot config: the DPI overlay settings, plus an include line in config.txt (added only once).
# Lakka updates only overwrite distroconfig.txt, so this survives them.
ssh "$HOST" 'cat > /flash/rgb-pi-crt.txt' < rgb-pi-crt.txt
ssh "$HOST" 'grep -q "^include rgb-pi-crt.txt" /flash/config.txt ||
    printf "\n# RGB-Pi SCART cable on the GPIO header. Comment out to disable.\ninclude rgb-pi-crt.txt\n" >> /flash/config.txt
    mount -o remount,ro /flash'

# RetroArch per-game CRT modes, the boot script that picks CRT or HDMI settings, and the notification font.
ssh "$HOST" 'mkdir -p /storage/.config/retroarch /storage/bin /storage/fonts'
ssh "$HOST" 'cat > /storage/.config/retroarch/switchres.ini' < switchres.ini
ssh "$HOST" 'cat > /storage/bin/display-mode.sh && chmod +x /storage/bin/display-mode.sh' < display-mode.sh
ssh "$HOST" 'cat > /storage/fonts/PixelOperator_size16.ttf' < fonts/PixelOperator_size16.ttf

# Run display-mode.sh first thing in autostart.sh, which Lakka runs before RetroArch. Keeps anything already in the file.
ssh "$HOST" 'f=/storage/.config/autostart.sh
    grep -q display-mode.sh $f 2>/dev/null && exit 0
    { echo "#!/bin/sh"
      echo "# Pick CRT or HDMI settings for RetroArch (lakka-rgb-pi-pi5)."
      echo "[ -x /storage/bin/display-mode.sh ] && /storage/bin/display-mode.sh"
      [ -e $f ] && grep -v "^#!" $f; true
    } > $f.new && mv $f.new $f && chmod +x $f'

echo "Installed on $HOST. Reboot it to apply: ssh $HOST reboot"
