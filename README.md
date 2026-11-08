# RGB-Pi SCART cable on a Raspberry Pi 5 with stock Lakka

This is how I got a Raspberry Pi 5 running the stock Lakka image to output 320x240 (240p) RGB to a CRT through the original RGB-Pi SCART cable on the GPIO header. No custom OS, no custom kernel, and no RGB-Pi software. Once RetroArch starts, its CRT SwitchRes feature sets each game's own resolution and refresh rate, including 480i for PS1 games that use it.

The whole setup is two files: [`rgb-pi-crt.txt`](rgb-pi-crt.txt) for the Pi's boot config and [`switchres.ini`](switchres.ini) for RetroArch, plus a few RetroArch settings.

## My setup

| Part | What I use |
|---|---|
| Computer | Raspberry Pi 5 |
| OS | [Lakka](https://www.lakka.tv/) 6.1, the stock Raspberry Pi 5 image |
| Video cable | RGB-Pi SCART cable, the original passive one that plugs into the 40-pin GPIO header (not the HDMI-based RGB-Pi 2) |
| TV | A US RGB-modded CRT that takes RGB with composite sync. A PVM or a European SCART TV that takes RGB should work too. |
| Audio | A USB sound card (C-Media chip) plugged into the TV's audio input. The cable can't carry audio on a Pi 5 (see [Limits](#limits)). |

Nothing is plugged into the Pi's HDMI ports.

## Why the RGB-Pi instructions don't work on a Pi 5

RGB-Pi's instructions (and [Lakka's own CRT page](https://www.lakka.tv/doc/CRT-Screens/)) tell you to copy `rgb-pi.dtbo` into the overlays folder and add `enable_dpi_lcd`, `dpi_output_format=6`, and `hdmi_timings` lines to `config.txt`. On a Pi 5, none of that does anything:

- **The firmware doesn't drive video anymore.** On a Pi 3 or 4, the GPU firmware generated the DPI video signal from those `config.txt` lines. On a Pi 5, the Linux display driver (KMS) handles all video, and the firmware ignores `enable_dpi_lcd`, `dpi_mode`, and `hdmi_timings`.
- **`rgb-pi.dtbo` is for the wrong chip.** Decompiled, it only switches GPIO 2-9, 12-17, and 20-25 into their "DPI video" function on the Pi 3 and 4's Broadcom GPIO controller. On a Pi 5, the GPIO header belongs to the new RP1 chip, so the overlay has nothing to attach to.
- **The pin layout is already built in.** The Pi 5's device tree has the same layout RGB-Pi calls "mode 6" (18-bit RGB on the high pads). The official `vc4-kms-dpi-generic` overlay selects it with the `rgb666-padhi` option.

So the video setup is the official overlay with the right options and the RGB-Pi's timings:

```
dtoverlay=vc4-kms-dpi-generic,rgb666-padhi
dtparam=clock-frequency=6400000
dtparam=hactive=320,hfp=17,hsync=30,hbp=34
dtparam=vactive=240,vfp=1,vsync=3,vbp=22
dtparam=hsync-invert,vsync-invert
```

That's 320x240 at 60 Hz: a 6.4 MHz pixel clock over 401 pixels per line gives 15.96 kHz, and 266 lines per frame gives 60 Hz. The syncs are active-low, and the cable merges them into composite sync for the TV. The timings come from RGB-Pi's own OS 4 image for the Pi 4, which had already dropped `rgb-pi.dtbo` for a KMS overlay with the same pins and syncs.

This is only the boot mode. Because video now goes through KMS, RetroArch can change modes like on any Linux PC, so SwitchRes builds a new mode for each game within the limits in `switchres.ini`. Interlaced modes work because the Pi 5 kernel [generates interlaced DPI video with RP1's PIO](https://www.raspberrypi.com/news/how-we-added-interlaced-video-to-raspberry-pi-5/) (added in 2025).

## Setup

Run these from another computer on the same network, in a clone of this repo. Lakka's SSH login is `root`, password `root` (Settings > Services > SSH turns it on).

1. **Update the bootloader** if it's older than 2024-11-12. Interlaced modes need the RP1 firmware that came with it. Without it, `dmesg` shows `rp1-pio ... failed to contact RP1 firmware`.

   ```
   ssh root@lakka.local rpi-eeprom-update -a
   ssh root@lakka.local reboot
   ```

2. **Add the video config.** `/flash` is read-only, so remount it first. The `include` line keeps the settings in their own file, which Lakka updates don't overwrite (they only replace `distroconfig.txt`).

   ```
   ssh root@lakka.local 'mount -o remount,rw /flash && cat > /flash/rgb-pi-crt.txt' < rgb-pi-crt.txt
   ssh root@lakka.local 'echo "include rgb-pi-crt.txt" >> /flash/config.txt && mount -o remount,ro /flash'
   ```

3. **Add the SwitchRes limits.**

   ```
   ssh root@lakka.local 'cat > /storage/.config/retroarch/switchres.ini' < switchres.ini
   ```

4. **Set RetroArch's CRT settings.** RetroArch overwrites `retroarch.cfg` when it exits, so stop it first: `ssh root@lakka.local systemctl stop retroarch`. Then set these lines in `/storage/.config/retroarch/retroarch.cfg` (with `nano` on the Pi), and start it again with `systemctl start retroarch`.

   | Setting | Why |
   |---|---|
   | `crt_switch_resolution = "4"` | Turns on SwitchRes with the limits from `switchres.ini`. |
   | `crt_switch_resolution_super = "0"` | Uses each game's own width. With super resolution on, RetroArch's on-screen text is squeezed about 8x sideways. |
   | `video_threaded = "false"` | Threaded video off, so RetroArch syncs to the CRT's refresh rate. |
   | `menu_driver = "rgui"` | The default XMB menu is unreadable at 240 lines. RGUI is made for low resolutions. |
   | `audio_device = "plughw:CARD=Device,DEV=0"` | Sends sound to the USB sound card. `Device` is my card's ALSA name; `aplay -l` shows yours. |

5. **Reboot** with the cable plugged in: `ssh root@lakka.local reboot`.

## Fit the picture to your TV

Every CRT needs its own centering and size. I tune them with the [240p Test Suite](https://artemiourbina.itch.io/240p-test-suite) under Settings > Video > CRT SwitchRes in RetroArch. These are saved in `retroarch.cfg`:

| Setting | What it does | My TV |
|---|---|---|
| `crt_switch_center_adjust` | Horizontal centering, in pixels of the current mode | `6` |
| `crt_switch_porch_adjust` | Horizontal size | `-16` |
| `crt_switch_vertical_adjust` | Vertical centering | `0` |

## Checking it

- `dmesg | grep rp1-dpi` shows each mode the cable gets, e.g. `mode=256x224 total=318x260 4968kHz -H-V+DE+CK`. Interlaced modes add `Using PIO to generate VSync on GPIO2`.
- RetroArch's log in `/storage/logfiles/` has `[CRT]` and `Switchres:` lines for each game.
- Color bars without RetroArch: `systemctl stop retroarch`, then `modetest -M drm-rp1-dpi -s 36:320x240` (press Enter to quit), then `systemctl start retroarch`. If `36` isn't the connector ID, `modetest -M drm-rp1-dpi -c` lists them.

## Limits

- **No audio through the cable.** The RGB-Pi sends audio out of GPIO 18 and 19, but the Pi 5 can only output PWM audio on GPIO 12 and 13, which the cable uses for green. Hence the USB sound card. Without one, there's no sound at all, because ALSA's default device is the HDMI port, which won't open with no screen on it.
- **57 Hz and up.** My TV rolls below about 55 Hz, so `switchres.ini` starts at 57 Hz. Arcade games slower than that (e.g. Mortal Kombat at 54.7 Hz) run slightly fast. Console games all run near 60 Hz. If your TV handles 50 Hz, you can lower the range in `switchres.ini`.
- **Brief sync loss on resolution changes.** With super resolution off, the TV loses sync for a moment whenever a game changes its horizontal resolution (some SNES, Genesis, and PS1 games do this mid-game).
- **18-bit color**, the same as the RGB-Pi on a Pi 3 or 4.

## Undo it

Run `mount -o remount,rw /flash` on the Pi, delete the `include rgb-pi-crt.txt` line from `/flash/config.txt`, and reboot.

## License

[MIT](LICENSE). This project isn't affiliated with RGB-Pi, Lakka, or Raspberry Pi.
