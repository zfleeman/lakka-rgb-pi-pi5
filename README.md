# RGB-Pi SCART cable on a Raspberry Pi 5 with stock Lakka

This repo gets the original RGB-Pi SCART cable (the passive one that plugs into the GPIO header) working on a Raspberry Pi 5 running the stock Lakka image. No custom OS, no custom kernel, and no RGB-Pi software. Games run at their native resolution and refresh rate on an RGB CRT: 240p for most consoles, 480i where PS1 games use it, and a new video mode for each game through RetroArch's CRT SwitchRes. If an HDMI screen is plugged in at boot, Lakka uses it with normal HDMI settings instead.

Tested on Lakka 6.1 with a Raspberry Pi 5 and a US RGB-modded CRT that runs at 60 Hz.

## Why the RGB-Pi instructions don't work on a Pi 5

RGB-Pi's instructions (and Lakka's own CRT page) tell you to copy `rgb-pi.dtbo` into the overlays folder and add `enable_dpi_lcd`, `dpi_output_format=6`, and `hdmi_timings` lines to `config.txt`. On a Pi 5, all of that does nothing:

- **The firmware doesn't drive video anymore.** On a Pi 3 or 4, the GPU firmware generated the DPI video signal from those `config.txt` lines. On a Pi 5, the Linux display driver (KMS) handles all video, and the firmware ignores `enable_dpi_lcd`, `dpi_mode`, and `hdmi_timings`.
- **`rgb-pi.dtbo` is for the wrong chip.** Decompiled, it only switches GPIO 2-9, 12-17, and 20-25 into their "DPI video" function on the Broadcom GPIO controller of the Pi 3 and 4. On a Pi 5, the GPIO header belongs to the new RP1 chip, so the overlay has nothing to attach to.
- **The pin setup is already built in.** The Pi 5's device tree defines the same pin layout (RGB-Pi calls it "mode 6", 18-bit RGB with the color on the high pads). The official `vc4-kms-dpi-generic` overlay selects it with the `rgb666-padhi` option.

So the whole video setup is the official overlay with the right options and the RGB-Pi's timings, in [`rgb-pi-crt.txt`](rgb-pi-crt.txt):

```
dtoverlay=vc4-kms-dpi-generic,rgb666-padhi
dtparam=clock-frequency=6400000
dtparam=hactive=320,hfp=17,hsync=30,hbp=34
dtparam=vactive=240,vfp=1,vsync=3,vbp=22
dtparam=hsync-invert,vsync-invert
```

That's 320x240 at 60 Hz (15.96 kHz) with active-low syncs, which the cable merges into composite sync for the TV. It's only the boot mode. Once RetroArch starts, SwitchRes replaces it with a mode that matches each game, because RetroArch can now change modes through KMS like on any other Linux PC. Interlaced modes (480i) work too: since early 2025 the Pi 5 kernel can [generate interlaced DPI video with RP1's PIO](https://www.raspberrypi.com/news/how-we-added-interlaced-video-to-raspberry-pi-5/).

The clue came from RGB-Pi's own OS 4 image for the Pi 4, which had already dropped `rgb-pi.dtbo` for a KMS overlay (`vc4-vga666-argon,mode6`) with the same pins and syncs. The timings above come from it.

## What you need

- A Raspberry Pi 5 with [Lakka](https://www.lakka.tv/) 6.x on its SD card.
- An original RGB-Pi SCART cable (the GPIO one, not the newer HDMI-based RGB-Pi 2).
- A CRT that takes RGB with composite sync (SCART, or an RGB-modded TV).
- A USB sound card plugged into the TV's audio input, if you want sound on the CRT (see [Known limits](#known-limits)).
- Another computer on the same network with `ssh` and `bash` (macOS or Linux), to run the installer.

## Install

1. **Make sure SSH is on in Lakka** (Settings > Services > SSH). The login is `root`, password `root`. Copying your SSH key over with `ssh-copy-id root@lakka.local` saves typing it for every step.
2. **Update the bootloader** if it's older than 2024-11-12, or 480i won't work: `ssh root@lakka.local rpi-eeprom-update -a`, then reboot. The installer warns you if it's too old. With an old bootloader, `dmesg` shows `rp1-pio ... failed to contact RP1 firmware`.
3. **Run the installer** from this repo on your computer: `./install.sh` (or `./install.sh root@<pi's IP>` if `lakka.local` doesn't resolve). It's safe to run again.
4. **Reboot the Pi** with the cable plugged in and no HDMI screen: `ssh root@lakka.local reboot`.

The installer saves the original files on the Pi as `/flash/config.txt.pre-crt` and `/storage/.config/retroarch/retroarch.cfg.pre-crt` the first time it runs.

## Fit the picture to your TV

Every CRT needs its own centering and size. Tune them with the [240p Test Suite](https://artemiourbina.itch.io/240p-test-suite) (the SNES or Genesis version runs in any matching core) and these RetroArch settings under Settings > Video > CRT SwitchRes:

| Setting in `retroarch.cfg` | What it does |
|---|---|
| `crt_switch_center_adjust` | Horizontal centering, in pixels of the current mode. |
| `crt_switch_porch_adjust` | Horizontal size. |
| `crt_switch_vertical_adjust` | Vertical centering. |

If you move the Pi between CRTs, `tv.sh` saves each TV's three values as a profile in `tvs/<name>.cfg` on your computer:

| Command | What it does |
|---|---|
| `./tv.sh` | Shows the active TV and the values in `retroarch.cfg`. |
| `./tv.sh save <name>` | Saves the current values as a TV and makes it active. This is how you add a TV. |
| `./tv.sh <name>` | Switches to a saved TV. It saves the outgoing TV's current values first, so menu tweaks aren't lost. |

RetroArch only writes its settings when it exits, so `tv.sh` restarts RetroArch. It won't while a game is loaded, so quit to the menu first. Set `LAKKA_HOST` if your Pi isn't `root@lakka.local`.

## Your TV's refresh range

[`switchres.ini`](switchres.ini) tells SwitchRes what the TV can handle, so it only builds modes the TV can show. The tested range starts at 57 Hz because the test TV rolls below about 55 Hz. Games slower than 57 Hz (some arcade boards) run slightly fast, and console games all run near 60 Hz, so they aren't affected. If you have a European SCART TV that syncs at 50 Hz, the file has a commented-out line for 50 Hz PAL games (288p and 576i). That line is untested. Edit the file on the Pi at `/storage/.config/retroarch/switchres.ini`, or edit it here and run `./install.sh` again.

## CRT and HDMI at boot

[`display-mode.sh`](display-mode.sh) runs from Lakka's `autostart.sh` at every boot, before RetroArch starts. If an HDMI screen is connected, it turns off the RGB-Pi output (which always reports "connected") and sets RetroArch's HDMI settings. Otherwise it sets the CRT ones:

| Setting | CRT | HDMI |
|---|---|---|
| `crt_switch_resolution` | `4` (per-game modes from `switchres.ini`) | `0` (off) |
| `crt_switch_resolution_super` | `0` (each game's own width) | unchanged |
| `menu_driver` | `rgui` (readable at 240 lines) | `xmb` |
| `video_threaded` | `false` | `true` |
| `video_font_path` | the Pixel Operator font from `fonts/` | RetroArch's default |
| `video_font_size` | `16` | `22` |
| `menu_enable_widgets` | `false` | `true` |
| `video_refresh_rate` | set by SwitchRes for each game | `60` |
| `audio_device` | the first USB sound card, if there is one | ALSA's default (HDMI) |

Changes to these in the RetroArch menu get reset at the next boot. Change them in `display-mode.sh` instead. The picture settings from the section above aren't touched, so your menu changes to those stick. `/storage/logs/display-mode.log` shows which mode the last boot picked.

A few of these choices need explaining:

- **Super resolution is off.** With it on (e.g. 2560), every mode is 2560 pixels wide and RetroArch stretches the game to fit. That looks the same on a CRT, but RetroArch's on-screen text gets squeezed about 8x sideways. With it off, the TV briefly loses sync when a game changes its horizontal resolution (some SNES, Genesis, and PS1 games do this mid-game).
- **Widgets are off.** Widget notifications can't shrink below a 9 px font, so they cover too much of a 240-line screen. Plain-text notifications are used instead.
- **A pixel font.** RetroArch's default font is made for big screens, and at small sizes its edges fall between pixels and come out soft. [Pixel Operator](https://www.dafont.com/pixel-operator.font) (CC0) is drawn on a 16 px grid, so it's fully sharp at size 16 and fits almost any message on a 320-pixel-wide screen. Fonts with hand-drawn 1-bit bitmaps, like Terminus, show up as garbage in RetroArch.

## Checking it

- `dmesg | grep rp1-dpi` shows each mode the cable gets, e.g. `mode=256x224 total=318x260 4968kHz -H-V+DE+CK`. Interlaced modes add `Using PIO to generate VSync on GPIO2`.
- RetroArch's log in `/storage/logfiles/` has `[CRT]` and `Switchres:` lines for each game.
- Color bars without RetroArch: `systemctl stop retroarch`, then `modetest -M drm-rp1-dpi -s 36:320x240` (press Enter to quit), then `systemctl start retroarch`. If `36` isn't the connector ID, `modetest -M drm-rp1-dpi -c` lists them.

## N64 tip

SwitchRes picks the mode from the size the core reports. At the Mupen64Plus-Next default of 640x480, every N64 game runs in 480i, which flickers because each line only refreshes 30 times a second. Set the core's resolution (`mupen64plus-43screensize`) to 320x240. Most real N64 games output 240p, so that matches the original hardware.

## Known limits

- **No audio through the cable.** The RGB-Pi sends audio out of GPIO 18 and 19, but the Pi 5 can only output PWM audio on GPIO 12 and 13, which the cable uses for green. Use a USB sound card plugged into the TV's audio input. `display-mode.sh` picks the first one it finds. Without one, the CRT has no sound, because ALSA's default device is the HDMI port, which won't open with no screen on it. `aplay -l` lists the sound cards.
- **18-bit color.** The cable carries 6 bits per color, the same as on a Pi 3 or 4.
- **Low refresh rates.** See [Your TV's refresh range](#your-tvs-refresh-range). Games taller than the range allows get cut off at the top and bottom.
- **Long notifications.** RetroArch notifications don't scroll, so long messages and achievement popups get cut off at the right edge. RetroArch's OpenGL driver also draws a hardcoded shadow behind plain-text notifications, which is easy to see at 320x240.

## Uninstall

On the Pi, run `mount -o remount,rw /flash`, comment out `include rgb-pi-crt.txt` in `/flash/config.txt`, and remove the `display-mode.sh` line from `/storage/.config/autostart.sh`. Reboot. To put RetroArch's settings back too, copy `/storage/.config/retroarch/retroarch.cfg.pre-crt` over `retroarch.cfg` while RetroArch is stopped.

## Files

| File | Installed to | What it does |
|---|---|---|
| `rgb-pi-crt.txt` | `/flash/rgb-pi-crt.txt` | The DPI overlay settings. `config.txt` pulls it in with an `include` line, so Lakka updates (which only overwrite `distroconfig.txt`) keep it. |
| `switchres.ini` | `/storage/.config/retroarch/switchres.ini` | The TV's limits for SwitchRes. |
| `display-mode.sh` | `/storage/bin/display-mode.sh` | Picks CRT or HDMI settings at boot. |
| `fonts/PixelOperator_size16.ttf` | `/storage/fonts/` | The CRT notification font. |
| `install.sh` | (runs on your computer) | Copies everything above over SSH and hooks `display-mode.sh` into `autostart.sh`. |
| `tv.sh` | (runs on your computer) | Saves and switches per-TV picture settings. |

## License

The scripts and config are under the [MIT License](LICENSE). Pixel Operator is by Jayvee Enaguas and is in the public domain ([CC0](fonts/PixelOperator-CC0.txt)). RGB-Pi is a product of its makers. This project isn't affiliated with RGB-Pi, Lakka, or Raspberry Pi.
