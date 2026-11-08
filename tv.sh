#!/usr/bin/env bash
# Save or apply each CRT TV's picture position and size on Lakka, over SSH from another computer. Profiles live in tvs/<name>.cfg.
#   tv.sh              show the active TV and its saved values
#   tv.sh <name>       switch to saved TV <name>, saving the outgoing TV's values first
#   tv.sh save [name]  save the current values as TV <name> (default: the active TV) and make it active. Creates new TVs.
# Set LAKKA_HOST to reach a Pi other than root@lakka.local.
set -euo pipefail
HOST="${LAKKA_HOST:-root@lakka.local}"
TVS="$(cd "$(dirname "$0")" && pwd)/tvs"
CFG=/storage/.config/retroarch/retroarch.cfg
ACTIVE=/storage/.config/crt-tv
KEYS='crt_switch_center_adjust|crt_switch_porch_adjust|crt_switch_vertical_adjust'

active() { ssh "$HOST" "cat $ACTIVE 2>/dev/null || true"; }

# RetroArch only writes retroarch.cfg when it exits, so stop it to get menu changes onto disk.
# Refuses while a game is loaded, because stopping would lose unsaved progress.
stop_retroarch() {
    ssh "$HOST" '
        pid=$(pidof retroarch) || exit 0
        if grep -q _libretro.so /proc/$pid/maps; then
            echo "A game is running in RetroArch. Quit it to the menu first." >&2
            exit 1
        fi
        systemctl stop retroarch'
    # From here on, start RetroArch again however the script ends.
    trap 'ssh "$HOST" systemctl start retroarch' EXIT
}

# save <name>: copy the values from retroarch.cfg into tvs/<name>.cfg and mark <name> active.
save() {
    mkdir -p "$TVS"
    { echo "# CRT picture position and size for the $1 TV. Written by tv.sh."
      ssh "$HOST" "grep -E '^($KEYS) = ' $CFG"; } > "$TVS/$1.cfg"
    ssh "$HOST" "echo $1 > $ACTIVE"
    echo "Saved the $1 TV:"
    grep -v '^#' "$TVS/$1.cfg"
}

# apply <name>: replace the values in retroarch.cfg with those from tvs/<name>.cfg.
apply() {
    if [ "$(grep -cE "^($KEYS) = " "$TVS/$1.cfg")" != 3 ]; then
        echo "$TVS/$1.cfg should have 3 settings. Not applying it." >&2
        exit 1
    fi
    # Drop the old lines and append the profile's. RetroArch puts them back in order the next time it saves.
    grep -E "^($KEYS) = " "$TVS/$1.cfg" |
        ssh "$HOST" "grep -vE '^($KEYS) = ' $CFG > $CFG.tv && cat >> $CFG.tv && mv $CFG.tv $CFG"
    echo "Applied the $1 TV:"
    grep -v '^#' "$TVS/$1.cfg"
}

check_name() {
    case "$1" in
        '') echo "No active TV yet. Name one: tv.sh save <name>" >&2; exit 1 ;;
        *[!a-z0-9-]*) echo "TV names are lowercase letters, numbers, and dashes." >&2; exit 1 ;;
    esac
}

case "${1:-}" in
    '')
        current="$(active)"
        echo "Active TV: ${current:-none}"
        echo "In retroarch.cfg (menu changes show up here once RetroArch exits):"
        ssh "$HOST" "grep -E '^($KEYS) = ' $CFG"
        ;;
    save)
        name="${2:-$(active)}"
        check_name "$name"
        stop_retroarch
        save "$name"
        ;;
    *)
        name="$1"
        check_name "$name"
        if [ ! -f "$TVS/$name.cfg" ]; then
            echo "No profile for the $name TV. Saved TVs: $(ls "$TVS" 2>/dev/null | sed -n 's/\.cfg$//p' | tr '\n' ' ')" >&2
            echo "For a new TV, tune it first, then run: tv.sh save $name" >&2
            exit 1
        fi
        stop_retroarch
        current="$(active)"
        [ -n "$current" ] && save "$current"
        apply "$name"
        ssh "$HOST" "echo $name > $ACTIVE"
        ;;
esac
