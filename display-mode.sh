#!/bin/sh
# Pick CRT or HDMI settings for RetroArch at boot. If an HDMI screen is connected, HDMI wins.
# Runs from /storage/.config/autostart.sh, which finishes before RetroArch starts. POSIX sh (Lakka's shell is BusyBox ash).

CFG=/storage/.config/retroarch/retroarch.cfg
LOG=/storage/logs/display-mode.log

# set_key <key> <value>: replace a setting in retroarch.cfg, or add it if it's missing.
set_key() {
    if grep -q "^$1 = " "$CFG"; then
        sed -i "s|^$1 = .*|$1 = \"$2\"|" "$CFG"
    else
        echo "$1 = \"$2\"" >> "$CFG"
    fi
}

mode=crt
for status in /sys/class/drm/card*-HDMI-A-*/status; do
    [ "$(cat "$status" 2>/dev/null)" = connected ] && mode=hdmi
done

if [ "$mode" = hdmi ]; then
    # The RGB-Pi output always reports "connected". Force it off so RetroArch draws to the HDMI screen.
    for status in /sys/class/drm/card*-DPI-*/status; do
        [ -e "$status" ] && echo off > "$status"
    done
    set_key crt_switch_resolution 0
    set_key menu_driver xmb
    set_key video_threaded true
    set_key video_font_path /tmp/assets/xmb/monochrome/font.ttf
    set_key video_font_size 22.000000
    set_key menu_enable_widgets true
    # "" = ALSA's default device, the HDMI port's audio.
    set_key audio_device ""
    # CRT SwitchRes saves the last game's refresh rate (e.g. 57 Hz). Put back the HDMI TV's 60 Hz.
    set_key video_refresh_rate 60.000000
else
    # 4 = per-game modes from switchres.ini. Super resolution 0 = each game's own width, so on-screen text isn't squeezed.
    set_key crt_switch_resolution 4
    set_key crt_switch_resolution_super 0
    set_key menu_driver rgui
    set_key video_threaded false
    # Plain-text notifications. Widgets can't shrink below a 9 px font, which is too big for a 240-line screen.
    set_key menu_enable_widgets false
    # Pixel Operator is drawn on a 16 px grid, so it's only fully sharp at 16 (or 32).
    set_key video_font_path /storage/fonts/PixelOperator_size16.ttf
    set_key video_font_size 16.000000
    # The cable can't carry audio on a Pi 5, so use the first USB sound card if there is one. plughw converts formats as needed.
    for usbid in /proc/asound/card*/usbid; do
        [ -e "$usbid" ] || continue
        set_key audio_device "plughw:CARD=$(cat "${usbid%/usbid}/id"),DEV=0"
        break
    done
fi

mkdir -p "$(dirname "$LOG")"
echo "$(date '+%Y-%m-%d %H:%M:%S') $mode" > "$LOG"
