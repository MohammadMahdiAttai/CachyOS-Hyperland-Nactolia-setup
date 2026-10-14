# CachyOS + Hyprland + Noctalia: post-install setup

A single Bash script that turns a fresh **CachyOS** installation with **Hyprland** and the **Noctalia** shell into a configured desktop: Persian and English input, fonts, theming, Hyprland workspaces, NTFS mounting, external monitor brightness, music, a set of everyday applications with tuned configurations, and **Spotify** with Spicetify, the Marketplace, optional ad blocking and a theme of your choice.

The script is meant to run **once** on a new system. It does not stay in the background, and it does not patch anything when you open an application. Run it again only when you want to update Spotify or to add or change settings.

> **Status:** written and tested by the author on one CachyOS + Hyprland + Noctalia machine. Read the script before running it on your own system.

---

## Contents

- [What it does](#what-it-does)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Options](#options)
- [What the script configures](#what-the-script-configures)
- [Spotify in detail](#spotify-in-detail)
- [Files it creates or changes](#files-it-creates-or-changes)
- [Safety: backups, logs and re-runs](#safety-backups-logs-and-re-runs)
- [Troubleshooting](#troubleshooting)
- [Reverting](#reverting)
- [Known limitations](#known-limitations)
- [Disclaimer](#disclaimer)
- [License](#license)

---

## What it does

In one run, the script:

1. Asks whether to test the package mirrors, then updates the system with `pacman -Syu` (can be skipped).
2. Installs base packages, the AUR helpers **paru** and **yay**, and the fonts and toolkits the desktop needs.
3. Enables the English and Persian locales.
4. Installs the **Vazirmatn** font and configures Fontconfig, GTK 3/4, Qt 5/6 and the UWSM environment for it.
5. Configures **Hyprland**: a US + Persian keyboard switched with Alt+Shift, workspaces 1 to 10 on `Super+1..0` and `Super+Shift+1..0`, and removes a floating rule that stopped Dolphin from tiling.
6. Configures NTFS mounting (`ntfs-3g`, UDisks2) so that members of the `wheel` group can mount drives without a password prompt.
7. Enables **DDC/CI** brightness control for external monitors and turns it on in the Noctalia configuration.
8. Installs and configures **MPD** (user service) and **rmpc**.
9. Installs a list of applications from the official repositories and the AUR, and writes configuration files for several of them (aria2, mpv, fzf, bandwhich, pacseek, LocalSend and others).
10. Installs and configures **Spotify**: the client, optional **SpotX** ad blocking, **Spicetify**, the **Marketplace**, the **Adblockify** extension, and a menu entry that starts Spotify directly.
11. Prints a summary: what was installed, what was already present, what failed and what to do next.

Every step is idempotent. Running the script again skips what is already done and repairs what is missing.

---

## Requirements

- **CachyOS** (or another Arch-based distribution; the script checks for `pacman` and warns on other systems).
- A **Hyprland** session. The script must be run from a terminal *inside* that session so it can reload Hyprland and read its state. Without Hyprland, the files are still written, but live checks are skipped.
- A user account with `sudo`. **Do not run the script as root or with `sudo`**; it asks for your password when it needs it.
- Network access to `archlinux.org`, `aur.archlinux.org`, `github.com` and `repository.spotify.com`, plus the package mirrors that pacman uses. If some of them are blocked where you live, use `--proxy`.
- `python3` (mirror check) and `script` from util-linux (log file). Both are on a standard CachyOS install.
- About 3 to 5 GB of free disk space for packages, Spotify and the AUR builds.
- `paru` is installed by the script if it is missing. `yay` is installed as well.

---

## Quick start

The repository contains `setup-cachyos-full.sh` (the script), this `README.md` and the `LICENSE` file.

```bash
git clone https://github.com/MohammadMahdiAttai/CachyOS-Hyprland-Noctalia-setup.git
cd CachyOS-Hyprland-Noctalia-setup
chmod +x setup-cachyos-full.sh
./setup-cachyos-full.sh
```

Close Spotify before the Spotify step runs, because the script stops it while it applies Spicetify.

Before the system update starts, the script asks whether to test the package mirrors. Press Enter for yes, or type `n` to skip the test.

If the system update installs a new kernel or graphics driver, the script stops after the update and asks you to reboot. After the reboot, run it again with `--skip-update`; the finished steps are skipped.

Typical variants:

```bash
# everything, but without the full system upgrade
./setup-cachyos-full.sh --skip-update

# only the Spotify part (after the rest is already set up)
./setup-cachyos-full.sh --skip-update --skip-system --skip-apps

# behind a proxy (for example a local v2rayN or xray HTTP port)
./setup-cachyos-full.sh --proxy http://127.0.0.1:10809

# update Spotify to the newest build and re-apply Spicetify
./setup-cachyos-full.sh --update-spotify --skip-update
```

When the script starts, it writes a log and prints the path of the log and of the backup folder.

---

## Options

| Option | Default | Description |
|---|---|---|
| `--skip-update` | off | Do not run `pacman -Syu` |
| `--skip-system` | off | Skip locales, fonts, theming, Hyprland, storage, DDC/CI and MPD |
| `--skip-apps` | off | Skip the application list and its configuration |
| `--skip-spotify` | off | Skip the whole Spotify step |
| `--update-spotify` | off | Update Spotify to the newest build (launcher source) and re-apply Spicetify. Without it, the installed client is kept |
| `--spotify-launcher` | on | Use `spotify-launcher` from the repositories (the setup that has been verified) |
| `--spotify-aur` | off | Install the regular `spotify` package from the AUR into `/opt/spotify` instead |
| `--spotx` | on | Apply SpotX, a client-level ad blocker |
| `--no-spotx` | off | Do not apply SpotX. Use this if the Marketplace link disappears after a run |
| `--no-adblock` | off | Do not install the Adblockify extension |
| `--spotify-theme NAME` | none | Install and apply a theme from `spicetify-themes` (for example `Sleek`) |
| `--spotify-scheme NAME` | none | Colour scheme inside that theme (for example `Nord`) |
| `--review` | off | Make AUR builds interactive, so you can read each PKGBUILD |
| `--no-live` | off | Never touch the running desktop (no `hyprctl reload`, no Noctalia restart) |
| `--mirror-check` | ask | Test the package mirrors without asking. By default the script asks at the start |
| `--no-mirror-check` | off | Do not test the package mirrors (and do not ask) |
| `--allow-source-builds` | off | Also allow large AUR source builds (16 GB+ RAM recommended) |
| `--proxy URL` | none | Download through a proxy. The address is remembered in `~/.config/cachyos-setup/proxy` |
| `-h`, `--help` | | Show the help text |

---

## What the script configures

### System update and base

- **Mirror check (before the update):** every active server in the pacman mirror lists is tested by downloading a 256 KiB sample (10 second limit, in parallel). Working servers are put first, fastest first (measured by download speed, so a server that answers quickly but serves slowly does not win), and unreachable ones move to the end. The test downloads about 15 MB in total per run. At the start of the run, before the password prompt, the script asks whether to test the mirrors (Enter means yes; no answer within a minute also means yes). `--mirror-check` and `--no-mirror-check` skip the question. Nothing is removed or commented out, and the original lists are backed up first. The order is measured again on every run. Skip it with `--no-mirror-check`.
- `pacman -Syu` (unless `--skip-update`). If a kernel or graphics driver was updated, the script stops here and asks you to reboot before it touches the desktop.
- Base packages: build tools, `git`, `curl`, `unzip`, `zip`, `perl`, `python`, fonts (Noto, JetBrains Mono Nerd), GTK 3 and 4, `adw-gtk-theme`, Qt 5 and 6 Wayland support, `qt5ct` and `qt6ct`, `kitty`, `polkit`, UDisks2, `ntfs-3g`, `i2c-tools`, `ddcutil`, `libcap`, XDG desktop portals (Hyprland and GTK) and `libnotify`.
- **AUR helpers:** `paru` (installed from the repositories or built from `paru-bin`), then **`yay`** (from the repositories, or built from `yay-bin` with `paru`).

### Locales

- Enables `en_US.UTF-8` and `fa_IR.UTF-8` in `/etc/locale.gen` and runs `locale-gen`.
- Sets `en_US.UTF-8` as the system default only if no `LANG` is set yet. An existing choice is kept.

### Fonts

- **Vazirmatn** (Persian and Arabic font) from the repositories, or from its GitHub release if the package is missing.
- Fontconfig rules that prefer Vazirmatn for Persian and Arabic text and as the fallback for sans-serif.
- GTK 3 and GTK 4 settings (dark theme, Vazirmatn 10 pt).
- Qt 5 and Qt 6 settings through `qt5ct` and `qt6ct` (Fusion style, Vazirmatn and JetBrains Mono).
- Kitty: a Persian symbol map so that Persian glyphs fall back to Vazirmatn.

### UWSM environment

Written as a managed block into `~/.config/uwsm/env`, so your other variables are kept:

- `QT_QPA_PLATFORMTHEME=qt6ct`
- `ELECTRON_OZONE_PLATFORM_HINT=auto` (Electron and Chromium apps use native Wayland)
- `~/.local/bin` and `~/.spicetify` are added to `PATH`.

### Hyprland

- **Keyboard:** `kb_layout = "us,ir"` and `kb_options = "grp:alt_shift_toggle"` in `~/.config/hypr/config/inputs.lua`. The script changes only those two values and keeps the rest of the input block. If Hyprland rejects the change, it restores the original file.
- **Workspaces 1 to 10:** `Super+1..0` switches to a workspace, `Super+Shift+1..0` moves the focused window. The block is written between markers in `binds.lua`. `NUM_WPM` is set to 10 in `variables.lua`, and the dynamic-workspace file is simplified.
- **Dolphin:** removes a floating window rule for Dolphin in `windowrules.lua`, so Dolphin tiles like other windows.
- Every Hyprland change is validated with `hyprctl reload`. If Hyprland reports a new configuration error, the script reverts that file and reports it.

### NTFS and removable drives

- `ntfs-3g` is set as the NTFS driver for UDisks2 (`/etc/udisks2/mount_options.conf`).
- A polkit rule (`/etc/polkit-1/rules.d/10-udisks2-wheel-mount.rules`) lets members of the `wheel` group mount filesystems without a password.

### External monitor brightness (DDC/CI)

- Loads the `i2c-dev` kernel module at boot (`/etc/modules-load.d/i2c-dev.conf`).
- Creates the `i2c` group, adds your user to it, and installs a udev rule (`/etc/udev/rules.d/99-i2c-permissions.rules`) so that the `i2c-dev` devices belong to that group. Nothing is re-triggered while the desktop runs: the permissions take effect after the next reboot, because i2c-dev loads at boot.
- Sets `[brightness] enable_ddcutil = true` in `~/.config/noctalia/config.toml` and checks that the file is still valid TOML.

### Music: MPD and rmpc

- Installs `mpd` and `rmpc`.
- Writes `~/.config/mpd/mpd.conf` (music in `~/Music`, listening on `127.0.0.1:6600`, PipeWire output) if you do not have one yet, and enables the MPD **user** service.
- Generates a default `rmpc` configuration if none exists.

### Applications

Installed from the official repositories first, then from the AUR, in this order:

| Application | Source |
|---|---|
| Telegram Desktop | repositories |
| mpv, aria2, Haruna, OBS Studio, Okular, Obsidian, Xournal++ | repositories |
| bandwhich, zellij, nvtop, fzf, uv, kew | repositories |
| Anki | repositories, then AUR `anki-bin` |
| LocalSend | repositories, then AUR `localsend-bin` |
| OnlyOffice | AUR `onlyoffice-bin` |
| Visual Studio Code | AUR `visual-studio-code-bin`, then `code` |
| pacseek | repositories, then AUR |
| v2rayN | AUR `v2rayn-bin` (its cores: `xray` from the repositories or AUR `xray-bin`, `sing-box`, `dotnet-runtime-8.0`) |
| Hiddify | AUR `hiddify-desktop-bin` or `hiddify-next-bin` |
| Google Chrome | AUR `google-chrome`, then `chromium` |

Source builds of v2rayN and Hiddify are off unless you pass `--allow-source-builds`.

**Flatpak is not used.** Applications come from the official repositories and the AUR only.

### Application configuration

- **aria2** (`~/.config/aria2/aria2.conf`): up to 16 connections per server, 16 splits, resume on restart, a session file so unfinished downloads survive a reboot, and `file-allocation=none` on Btrfs. The helper `~/.local/bin/aria2-resume` resumes everything that is unfinished.
- **mpv** (`~/.config/mpv/mpv.conf`, only if missing): `gpu-next`, `hwdec=auto-safe`, resume playback, Vazirmatn subtitles.
- **fzf**: key bindings for bash, zsh and fish (`Ctrl+T`, `Ctrl+R`, `Alt+C`), written as a marked block.
- **uv**: nothing to configure; a usage hint is printed.
- **pacseek**: changes its `yay` settings to `paru`. You can change them back in pacseek's settings.
- **bandwhich**: sets the capabilities it needs, so it runs without `sudo`, and adds a pacman hook (`/etc/pacman.d/hooks/bandwhich-caps.hook`) that sets them again after each upgrade.
- **LocalSend**: opens TCP and UDP port 53317 if `ufw` or `firewalld` is active.

---

## Spotify in detail

The Spotify step does four things, in this order.

1. **The client.** By default, `spotify-launcher` from the repositories downloads Spotify's own Linux client into `~/.local/share/spotify-launcher/`. With `--spotify-aur`, the regular `spotify` package from the AUR is installed into `/opt/spotify` instead. The AUR option makes that folder writable for Spicetify (the Spicetify documentation asks for it) and installs a pacman hook (`/etc/pacman.d/hooks/spotify-spicetify.hook`) that repeats this after each upgrade.

2. **SpotX (ad blocking in the client).** SpotX patches the Spotify client so that audio and display ads are not played. It is **on by default**. It runs on a *stock* client only, and before Spicetify. If you see no Marketplace link after a run, try `--no-spotx`.

3. **Spicetify and the Marketplace.** The Spicetify CLI is downloaded as a prebuilt binary into `~/.spicetify` (with an AUR fallback). The Marketplace is installed into `~/.config/spicetify/CustomApps/marketplace`. Spicetify is applied with `spicetify backup` and `spicetify apply`.

4. **Adblockify.** The extension `adblock.js` from [rxri/spicetify-extensions](https://github.com/rxri/spicetify-extensions) is copied into `~/.config/spicetify/Extensions/` and added to the `extensions` setting. It blocks ads between songs and in the interface. It is **on by default** (`--no-adblock` turns it off). After the apply step, the script checks that the file is in the client and that the Spotify page loads it.

### Theme

- By default, Spicetify uses its original look (`SpicetifyDefault`). The script does not choose a theme for you.
- Choose a theme yourself in **Marketplace** (in the top bar next to Search, or in the *Your Library* sidebar, depending on your Spotify version).
- If you pass `--spotify-theme`, the script installs that theme from `spicetify-themes`, downloading only its files.
- If you already chose a theme in Marketplace, a later run keeps it.

### Starting Spotify

- The menu entry (`~/.local/share/applications/spotify-launcher.desktop`) starts `spotify-launcher --skip-update`. The launcher's own update check is skipped, because an automatic update would replace the patched files and remove Spicetify. The script does **not** run anything when you open Spotify.
- With `--spotify-aur`, the package's own menu entry is used.

### First run and warm-up

Spicetify needs the Spotify version that the client writes to its `prefs` file. If that version is missing or different, the setup starts Spotify once and keeps it open:

- about **60 seconds** on a fresh install (the Spicetify documentation asks you to log in during this time);
- about **20 seconds** after an update, when your login already exists.

Spotify then closes by itself and the setup continues. Spotify is started only when this is needed, not on every run.

### Updates

- Spotify does not update itself through the menu entry.
- To update Spotify and re-apply Spicetify, run the script with `--update-spotify`. Without that option, the installed client is kept.
- With `--spotify-aur`, pacman updates the package. Run the script again afterwards to re-apply Spicetify.

### Compatibility check

Spicetify 2.45.3 lists Spotify for Linux up to version 1.2.96. If your client is newer, the script prints a warning. The Marketplace may then not appear until Spicetify supports that version.

---

## Files it creates or changes

Paths relative to your home directory unless marked otherwise.

| Path | Purpose |
|---|---|
| `~/.config/fontconfig/conf.d/65-persian-font.conf` | Persian font rules |
| `~/.config/gtk-3.0/settings.ini`, `~/.config/gtk-4.0/settings.ini` | GTK settings |
| `~/.config/qt5ct/qt5ct.conf`, `~/.config/qt6ct/qt6ct.conf` | Qt settings |
| `~/.config/uwsm/env` | Environment variables and `PATH` (managed block) |
| `~/.config/kitty/kitty.conf` | Persian symbol map (managed block) |
| `~/.config/hypr/config/inputs.lua`, `binds.lua`, `variables.lua`, `workspaces.lua`, `windowrules.lua` | Hyprland configuration |
| `~/.config/noctalia/config.toml` | Enables DDC/CI brightness |
| `~/.config/mpd/mpd.conf`, `~/.config/rmpc/` | MPD and rmpc |
| `~/.config/aria2/aria2.conf`, `~/.cache/aria2/` | aria2 configuration and session |
| `~/.config/mpv/mpv.conf` | mpv configuration (only if missing) |
| `~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish` | fzf key bindings (managed block) |
| `~/.config/pacseek/config.json` | pacseek uses `paru` |
| `~/.local/bin/aria2-resume` | aria2 helper |
| `~/.local/share/fonts/Vazirmatn/` | Vazirmatn font files (if installed from GitHub) |
| `~/.spicetify/` | Spicetify CLI |
| `~/.config/spicetify/` | Spicetify configuration, Marketplace, themes, extensions |
| `~/.config/spotify/prefs` | Spotify preferences (read by Spicetify, not written by the script) |
| `~/.local/share/spotify-launcher/` | Spotify client when using the launcher |
| `~/.local/share/applications/spotify-launcher.desktop` | Menu entry override for the launcher |
| `~/.config/cachyos-setup/proxy` | Proxy address, if you use `--proxy` |
| `~/.local/state/cachyos-setup/` | Logs and Spotify state markers |
| `~/.config/setup-backups/<timestamp>/` | Backups of every file the script changed |
| `/etc/locale.gen`, `/etc/locale.conf` | Locales (only if no default is set) |
| `/etc/pacman.d/mirrorlist`, `/etc/pacman.d/cachyos*-mirrorlist` | Order of the mirror servers (backups first; no server is removed) |
| `/etc/modules-load.d/i2c-dev.conf`, `/etc/udev/rules.d/99-i2c-permissions.rules` | DDC/CI |
| `/etc/polkit-1/rules.d/10-udisks2-wheel-mount.rules`, `/etc/udisks2/mount_options.conf` | NTFS mounting |
| `/etc/pacman.d/hooks/bandwhich-caps.hook` | bandwhich capabilities after upgrades |
| `/etc/pacman.d/hooks/spotify-spicetify.hook`, `/usr/local/bin/spotify-spicetify-writable` | Only with `--spotify-aur` |

The script also installs packages with `pacman` and `paru`, and it changes group membership (`i2c`) and file capabilities (`setcap` for bandwhich).

---

## Safety: backups, logs and re-runs

- **Backups:** before a file is changed, a copy is saved under `~/.config/setup-backups/<timestamp>/` (system files too, with a folder structure that mirrors their path).
- **Logs:** every run writes `~/.local/state/cachyos-setup/setup-<timestamp>.log`. The log is cleaned of terminal escape codes. The Spotify steps also write `spotify-client.log` in the same folder.
- **Interrupted runs:** if a run is interrupted, the next run reports the previous log and continues. A stale `pacman` lock from an interrupted run is removed automatically.
- **Idempotent:** every step checks what is already in place. Re-running the script only changes what is missing or different.
- **Hyprland:** a change that Hyprland rejects is reverted automatically.
- **Reboot guard:** after `pacman -Syu`, the script checks the pacman log for upgraded or installed kernel and graphics packages (`linux*`, `nvidia*`, `mesa`, `egl-wayland`, `libglvnd`, `vulkan*`, `wayland`, `xorg-xwayland`, `hyprland`). If it finds one, it stops before reloading the desktop and asks you to reboot. The running session would otherwise keep the old driver while the desktop is reloaded.
- **Sudo:** the script keeps the sudo session alive during long AUR builds, and it refuses to run as root.
- **Inhibit sleep:** while the script runs, it asks systemd not to suspend or lock the session.

---

## Troubleshooting

**The screen froze or went black during a run.** Older versions re-triggered the i2c devices while the desktop was running, and on the author's machine that froze the monitor image. The current version does not do that: the DDC/CI permissions take effect after the next reboot. If the screen still freezes, switch to a text console with `Ctrl+Alt+F3`, log in, run `sudo reboot`, then send the newest log from `~/.local/state/cachyos-setup/` and the output of `journalctl -k --since "<a minute before the freeze>" --no-pager | grep -i -E "nvrm|nvidia|drm|blocked|hung|btrfs"`.

**The downloads are slow.** The mirror check ranks the servers by a measured 256 KiB download, and it runs again on every update, so run the update again to refresh the order. If the downloads are still slow, the network or the servers are the cause; `--no-mirror-check` skips the check. Send the mirror check lines from the log if you want help with it.

**The Marketplace link is not visible.** Look in the top bar next to the Search box for a store-like icon and hover over it. If it is not there, run the script with `--no-spotx`, then check the summary and `spotify-client.log`. The log says where the link was injected (top bar, sidebar, or not at all).

**Ads are still playing.** Check that Adblockify is in Spotify: the summary should contain "Adblockify is in the Spotify client and loaded by its page". In Spotify, *Marketplace → Extensions* should list it. SpotX blocks audio ads at the client level and is on by default; if ads continue, check that the run did not use `--no-spotx`. Ad blocking depends on Spotify's internal APIs, so it can stop working after a Spotify update: run the script again with `--update-spotify`.

**The Spotify step says the client was not downloaded.** The launcher's state file can record a version while the client files are missing, for example after an interrupted download. In that case the script now downloads the client again. If it still fails, check the network or use `--proxy`, then read `~/.local/state/cachyos-setup/spotify-client.log`. The lines above that message show the error that spotify-launcher reported. A new download never removes the current client before it is complete.

**Spotify asks for a login.** This happens once on a fresh install. The setup keeps Spotify open for about 60 seconds so that you can log in, then closes it.

**A step reports FAILED.** Read the summary at the end, then the log in `~/.local/state/cachyos-setup/`. Run the script again after fixing the cause; finished steps are skipped.

**Spicetify says "backup version and Spotify version are mismatched".** Spotify was updated after the last run. Run the script with `--update-spotify`.

**Hyprland keyboard does not switch.** Log out and back in. Then check `hyprctl getoption input:kb_layout`.

**Monitor brightness does not change.** Log out and back in, so that the `i2c` group takes effect. Then run `ddcutil detect`.

**Mounting an NTFS drive asks for a password.** Log out and back in, so that the `wheel` group is active in your session.

---

## Reverting

- **Spotify patches:** `spicetify restore` restores the original Spotify files from Spicetify's backup. To remove the Marketplace and extensions completely, delete `~/.config/spicetify` and `~/.spicetify`.
- **SpotX:** SpotX keeps its own backup next to the client file; re-installing the Spotify package (or `spotify-launcher --force-update`) gives you a stock client.
- **Configuration files:** copy the files you want back from `~/.config/setup-backups/<timestamp>/`.
- **Packages:** remove them with `sudo pacman -Rns <package>`.
- **System hooks and rules:** delete the files listed in [Files it creates or changes](#files-it-creates-or-changes) under `/etc` and `/usr/local/bin`, then run `sudo systemctl daemon-reload` and `sudo udevadm control --reload-rules`.

---

## Known limitations

- The script is written for **CachyOS with Hyprland and Noctalia**. Other setups may need changes.
- **Spotify modifications** (SpotX, Spicetify, Adblockify) depend on the Spotify client's internal code. A new Spotify build can break them until the tools are updated. Check the summary after each `--update-spotify` run.
- **AUR packages** are built from source or repackaged by their maintainers. Review them with `--review` if you want to.
- Persian text rendering depends on Vazirmatn and on how each application uses fontconfig.
- Only the **launcher** source has been verified end to end on the author's machine. `--spotify-aur` is implemented and tested with simulated packages, but it has not been checked on a real system with the AUR package.

---

## Disclaimer

This project changes system files and installs third-party software, including modifications to the Spotify client (SpotX, Spicetify, Adblockify). Modifying Spotify may violate Spotify's Terms of Service, and your account could be restricted. Read the script before running it. You are responsible for what you run on your system. The project is provided without any warranty.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
