#!/usr/bin/env bash
# ==============================================================================
#  CachyOS + Hyprland (Lua) + Noctalia — Complete Post-Install Setup  (v2)
# ==============================================================================
#
#  SYSTEM / DESKTOP
#     - full system update, base packages, paru (AUR helper)
#     - en_US + fa_IR locales, US+Persian keyboard (Alt+Shift) in Hyprland
#     - Vazirmatn font, Fontconfig, GTK3/GTK4, Qt5ct/Qt6ct, UWSM env, Kitty
#     - Hyprland: workspaces 1-10, Dolphin tiling rule (auto-reverted on error)
#     - NTFS + UDisks2 + Polkit, DDC/CI monitor brightness (Noctalia), MPD + rmpc
#
#  APPLICATIONS
#     Telegram, mpv, aria2 (fast + resume), Haruna, OnlyOffice, OBS Studio, Anki,
#     LocalSend, Okular, Obsidian, bandwhich, zellij, pacseek, VS Code, v2rayN,
#     Hiddify, Google Chrome, Xournal++, uv, nvtop, fzf, kew
#
#  SPOTIFY (launcher by default; --spotify-aur for the regular package; --spotx for SpotX)
#     spotify-launcher  -> the verified client (default); --spotify-aur: paru into /opt/spotify
#     SpotX             -> ad-block on the client (on by default; --no-spotx turns it off)
#     Spicetify         -> Marketplace (you choose the theme there)
#     menu entry        -> starts Spotify directly (no patching or update check on start)
#     rerun the script  -> after a Spotify update, re-applies Spicetify (the only time it patches)
#
#  Safe to run more than once (idempotent). Every config file that is changed
#  is backed up first. Run it from a terminal INSIDE your Hyprland session:
#
#      chmod +x setup-cachyos-full.sh && ./setup-cachyos-full.sh
#
#  Do NOT run it with sudo — it asks for your password itself.
#  Behind a proxy (e.g. the HTTP port of a local v2rayN / xray):
#      ./setup-cachyos-full.sh --proxy http://127.0.0.1:10809
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------ options --
SKIP_UPDATE=0
SKIP_SYSTEM=0
SKIP_APPS=0
SKIP_SPOTIFY=0
AUR_INTERACTIVE=0
NO_LIVE=0
MIRROR_CHECK=ask                  # ask | 1 = test the package mirrors | 0 = skip them
ALLOW_SOURCE_BUILDS=0
PROXY_URL=""
SPOTIFY_THEME=""       # empty: the script picks no theme; choose one in Spotify > Marketplace
SPOTIFY_SCHEME=""
SPOTIFY_WARMUP_HOLD="${SPOTIFY_WARMUP_HOLD:-60}"   # seconds Spotify stays open on first run (Spicetify docs)
UPDATE_SPOTIFY=0      # 1 = setup also updates Spotify (launcher) to the newest build

usage() {
    cat <<'EOF'
Usage: ./setup-cachyos-full.sh [options]

  --skip-update          do not run a full system upgrade (pacman -Syu)
  --skip-system          skip system/desktop configuration (Persian, Hyprland, NTFS, DDC, MPD)
  --skip-apps            skip application installation and app configuration
  --skip-spotify         skip the Spotify client / ad-block / Spicetify step
  --review               AUR builds become interactive (you review every PKGBUILD)
  --no-live              never touch the running desktop (no hyprctl reload, no Noctalia restart)
  --mirror-check          test the package mirrors without asking
  --no-mirror-check       do not test the package mirrors (and do not ask)
  --allow-source-builds  also allow huge AUR source builds (needs 16 GB+ RAM)
  --proxy URL            download through a proxy, e.g. http://127.0.0.1:10809 (remembered)
  --update-spotify       update Spotify to the newest build and re-patch it (default: keep the installed client)
  --spotify-launcher     Spotify client from spotify-launcher (default; the verified setup)
  --spotify-aur          regular "spotify" package from the AUR, installed to /opt/spotify
  --spotx                apply SpotX (client-level ad-block; on by default)
  --no-spotx             do not apply SpotX (use this if Marketplace disappears)
  --no-adblock           do not install Adblockify (a Spicetify extension that blocks ads)
  --spotify-theme NAME   optional: install and apply a theme from spicetify-themes (e.g. Sleek)
  --spotify-scheme NAME  colour scheme inside that theme (e.g. Nord)
  -h, --help             show this help

Logs: ~/.local/state/cachyos-setup/
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            -h|--help)             usage; exit 0 ;;
            --skip-update)         SKIP_UPDATE=1 ;;
            --skip-system)         SKIP_SYSTEM=1 ;;
            --skip-apps)           SKIP_APPS=1 ;;
            --skip-spotify)        SKIP_SPOTIFY=1 ;;
            --review)              AUR_INTERACTIVE=1 ;;
            --no-live)             NO_LIVE=1 ;;
            --mirror-check)        MIRROR_CHECK=1 ;;
            --no-mirror-check)     MIRROR_CHECK=0 ;;
            --allow-source-builds) ALLOW_SOURCE_BUILDS=1 ;;
            --proxy)               shift; PROXY_URL="${1:-}" ;;
            --proxy=*)             PROXY_URL="${1#*=}" ;;
            --update-spotify)      UPDATE_SPOTIFY=1 ;;
            --spotify-launcher)    SPOTIFY_SOURCE=launcher ;;
            --spotify-aur)         SPOTIFY_SOURCE=aur ;;
            --spotx)               SPOTX=1 ;;
            --no-spotx)            SPOTX=0 ;;
            --no-adblock)          ADBLOCK_ON=0 ;;
            --spotify-theme)       shift; SPOTIFY_THEME="${1:-}" ;;
            --spotify-scheme)      shift; SPOTIFY_SCHEME="${1:-}" ;;
            *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------- constants --
STAMP="${SETUP_STAMP:-$(date +%Y%m%d-%H%M%S)}"
LOG_DIR="$HOME/.local/state/cachyos-setup"
LOG_FILE="$LOG_DIR/setup-$STAMP.log"
BACKUP_DIR="$HOME/.config/setup-backups/$STAMP"
PROXY_FILE="$HOME/.config/cachyos-setup/proxy"
WORKDIR=""
SUDO_KEEPALIVE_PID=""
START_SECONDS=$SECONDS
HYPR_BASELINE=""

# Spotify locations: the regular package, installed by paru into /opt/spotify
# Spotify: client source. launcher = spotify-launcher from the repositories (the verified default);
# aur = the regular "spotify" package from the AUR, installed to /opt/spotify.
SPOTIFY_SOURCE="${SPOTIFY_SOURCE:-launcher}"
SPOTX="${SPOTX:-1}"                       # 1 = apply SpotX (client-level ad-block; on by default)
ADBLOCK_ON="${ADBLOCK_ON:-1}"             # 1 = install Adblockify (ads between songs and in the UI)
ADBLOCK_URL="${ADBLOCK_URL:-https://raw.githubusercontent.com/rxri/spicetify-extensions/main/adblock/adblock.js}"
REBOOT_REQUIRED=0                 # 1 = a kernel or graphics driver changed in this run
SPOTIFY_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/spotify-launcher"
SPOTIFY_INSTALL="$SPOTIFY_HOME/install"
SPOTIFY_STATE="$SPOTIFY_HOME/state.json"
SPOTIFY_DIR="${SPOTIFY_ROOT:-$SPOTIFY_INSTALL/usr/share/spotify}"   # SPOTIFY_ROOT is for tests only
SPOTIFY_BIN="$SPOTIFY_DIR/spotify"
SPOTIFY_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/cachyos-setup/spotify.conf"
SPOTIFY_PREFS="${XDG_CONFIG_HOME:-$HOME/.config}/spotify/prefs"
SPICETIFY_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/spicetify"
SPICETIFY_BIN=""
SPICETIFY_RELEASES="https://github.com/spicetify/cli/releases"
# Spicetify 2.45.3 lists Spotify for Linux compatibility up to this version (macOS/Windows: 1.3.3)
SPICETIFY_LINUX_MAX_SPOTIFY="1.2.96"
MARKETPLACE_URL="${MARKETPLACE_URL:-https://github.com/spicetify/marketplace/releases/latest/download/marketplace.zip}"
THEMES_REPO="${THEMES_REPO:-https://github.com/spicetify/spicetify-themes.git}"
SPOTX_URL="${SPOTX_URL:-https://raw.githubusercontent.com/SpotX-Official/SpotX-Bash/main/spotx.sh}"
SPOTIFY_MARKS="$LOG_DIR/spotify-markers"
SPOTIFY_STOCK="$LOG_DIR/spotify-stock"
SPOTIFY_CLIENT_LOG="$LOG_DIR/spotify-client.log"
SPOTIFY_NOTE=""

declare -a RES_OK=() RES_SKIP=() RES_FAIL=() RES_WARN=()

# ------------------------------------------------------------------- colors --
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[1;33m'
    C_BLUE=$'\033[0;34m'; C_CYAN=$'\033[0;36m'; C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''; C_BOLD=''; C_DIM=''; C_RESET=''
fi

# ------------------------------------------------------------------ logging --
_ts()  { date '+%H:%M:%S'; }
info() { printf '%s %s==>%s %s\n'    "$(_ts)" "$C_BLUE"   "$C_RESET" "$*"; }
ok()   { printf '%s %s[ OK ]%s %s\n' "$(_ts)" "$C_GREEN"  "$C_RESET" "$*"; }
warn() { printf '%s %s[WARN]%s %s\n' "$(_ts)" "$C_YELLOW" "$C_RESET" "$*"; RES_WARN+=("$*"); }
err()  { printf '%s %s[FAIL]%s %s\n' "$(_ts)" "$C_RED"    "$C_RESET" "$*"; }
skip() { printf '%s %s[SKIP]%s %s\n' "$(_ts)" "$C_CYAN"   "$C_RESET" "$*"; }
note() { printf '%s       %s%s%s\n'  "$(_ts)" "$C_DIM"    "$*" "$C_RESET"; }
die()  { err "$*"; exit 1; }

STEP_NO=0
STEP_TOTAL=0
STEP_NAME=""
STEP_T0=$SECONDS

step_end() {
    if [[ -n "$STEP_NAME" ]]; then
        note "finished in $((SECONDS - STEP_T0))s"
        STEP_NAME=""
    fi
    return 0
}

step() {
    step_end
    STEP_NO=$((STEP_NO + 1))
    STEP_NAME="$1"
    STEP_T0=$SECONDS
    printf '\n%s%s━━━ [%d/%d] %s ━━━%s\n' "$C_BOLD" "$C_BLUE" "$STEP_NO" "$STEP_TOTAL" "$1" "$C_RESET"
}

# ------------------------------------------------------------------ helpers --
have() { command -v "$1" &>/dev/null; }

hypr_running() {
    ((NO_LIVE)) && return 1
    have hyprctl && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]
}

SUDO=(sudo)
as_root() { "${SUDO[@]}" "$@"; }

retry() {    # retry <tries> <command...>
    local tries=$1 n=1
    shift
    until "$@"; do
        if ((n >= tries)); then return 1; fi
        warn "attempt $n/$tries failed — retrying in $((n * 5))s"
        sleep $((n * 5))
        n=$((n + 1))
    done
}

# Any HTTP answer (even 404) means the host is reachable; 000 means no route.
reachable() {
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 6 --max-time 10 "$1" 2>/dev/null || true)
    [[ -n "$code" && "$code" != 000 ]]
}

notify() { have notify-send && notify-send -a "CachyOS setup" "$1" "$2" >/dev/null 2>&1 || true; }

ensure_workdir() {
    if [[ -z "$WORKDIR" || ! -d "$WORKDIR" ]]; then
        WORKDIR="$(mktemp -d)"
    fi
}

pkg_installed() { pacman -Qq "$1" &>/dev/null; }
pkg_in_repos()  { pacman -Si "$1" &>/dev/null; }

PACMAN_LOCK=/var/lib/pacman/db.lck

# Package managers that can legitimately hold the pacman lock. The 'pacman --dbpath ...'
# calls made by update widgets (checkupdates) never hold the real lock, so they are ignored.
pm_holders() {
    pgrep -a -x 'pacman|paru|yay|makepkg|pamac-daemon|packagekitd' 2>/dev/null | grep -v -- '--dbpath'
}

# A lock older than the current boot cannot belong to a live process (forced reboot / crash).
pacman_lock_is_stale() {
    local boot lock_ts
    boot=$(awk '/^btime/ {print $2}' /proc/stat 2>/dev/null)
    lock_ts=$(stat -c %Y "$PACMAN_LOCK" 2>/dev/null)
    if [[ -n "$boot" && -n "$lock_ts" ]] && ((lock_ts < boot)); then
        return 0
    fi
    [[ -z "$(pm_holders)" ]]
}

# Remove a stale lock, or wait (max 3 min) for the real holder to finish.
pacman_unlock_wait() {
    [[ -e "$PACMAN_LOCK" ]] || return 0
    local waited=0 holders line
    while [[ -e "$PACMAN_LOCK" ]]; do
        if pacman_lock_is_stale; then
            warn "Stale pacman lock (left behind by an interrupted run) — removing it"
            as_root rm -f "$PACMAN_LOCK"
            return 0
        fi
        if ((waited == 0)); then
            holders="$(pm_holders)"
            warn "pacman is locked by another package-manager process — waiting for it to finish:"
            while IFS= read -r line; do
                [[ -n "$line" ]] && note "  $line"
            done <<<"$holders"
        fi
        if ((waited >= 180)); then
            err "pacman is still locked after 3 minutes. Close the other package manager (or reboot), then run this script again."
            return 1
        fi
        sleep 5
        waited=$((waited + 5))
    done
    ok "pacman lock released"
}

pac_install() {
    pacman_unlock_wait || return 1
    retry 3 as_root pacman -S --needed --noconfirm "$@"
}

# single attempt, no retry (used for the one-by-one fallback)
pac_install_once() {
    pacman_unlock_wait || return 1
    as_root pacman -S --needed --noconfirm "$@"
}

pac_install_list() {   # pac_install_list "label" pkg...
    local label=$1 p
    local -a failed=()
    shift
    info "$label: ${*}"
    if pac_install "$@"; then
        ok "$label ready"
        return 0
    fi
    warn "bulk install failed — retrying one package at a time"
    for p in "$@"; do
        if pkg_in_repos "$p" && pac_install_once "$p"; then
            continue
        fi
        failed+=("$p")
    done
    if ((${#failed[@]})); then
        err "$label: could not install: ${failed[*]}"
        RES_FAIL+=("packages: ${failed[*]}")
        return 1
    fi
    ok "$label ready"
}

aur_install() {
    local pkg=$1
    local -a flags=(-S --needed)
    # nice: long builds must never starve the compositor
    if ((AUR_INTERACTIVE)); then
        retry 2 nice -n 10 paru "${flags[@]}" "$pkg"
    else
        retry 2 nice -n 10 paru "${flags[@]}" --noconfirm --skipreview "$pkg"
    fi
}

# install_app "Name" spec...   spec = pacman:<pkg> | aur:<pkg>
# Specs are tried in order; the first that works wins.
APP_NO=0
APP_TOTAL=0

install_app() {
    local name=$1 spec kind id
    shift
    if ((APP_TOTAL > 0)); then
        APP_NO=$((APP_NO + 1))
        info "[$APP_NO/$APP_TOTAL] Installing $name"
    else
        info "Installing $name"
    fi

    for spec in "$@"; do
        kind=${spec%%:*}; id=${spec#*:}
        case "$kind" in
            pacman|aur)
                if pkg_installed "$id"; then
                    ok "$name is already installed ($id)"
                    RES_SKIP+=("$name  (already installed: $id)")
                    return 0
                fi ;;
        esac
    done

    for spec in "$@"; do
        kind=${spec%%:*}; id=${spec#*:}
        case "$kind" in
            pacman)
                if ! pkg_in_repos "$id"; then
                    note "'$id' is not in the pacman repositories"
                    continue
                fi
                if pac_install "$id"; then
                    ok "$name installed with pacman ($id)"
                    RES_OK+=("$name  (pacman: $id)")
                    return 0
                fi
                warn "pacman could not install $id" ;;
            aur)
                if ! have paru; then
                    note "paru is not available — skipping AUR '$id'"
                    continue
                fi
                if ! paru -Si "$id" &>/dev/null; then
                    note "'$id' was not found in the AUR"
                    continue
                fi
                if aur_install "$id"; then
                    ok "$name installed from the AUR ($id)"
                    RES_OK+=("$name  (AUR: $id)")
                    return 0
                fi
                warn "AUR build of $id failed" ;;
        esac
    done

    err "$name could not be installed by any method"
    RES_FAIL+=("$name")
    return 1
}

backup_file() {
    local f=$1 dest
    [[ -e "$f" ]] || return 0
    dest="$BACKUP_DIR/${f#/}"
    mkdir -p "$(dirname "$dest")"
    cp -a "$f" "$dest" 2>/dev/null || true
}

backup_root_file() {
    local f=$1 dest
    as_root test -e "$f" || return 0
    dest="$BACKUP_DIR/${f#/}"
    mkdir -p "$(dirname "$dest")"
    as_root cp -a "$f" "$dest" 2>/dev/null || true
    as_root chown -R "$(id -u):$(id -g)" "$BACKUP_DIR" 2>/dev/null || true
}

write_file() {   # write_file PATH  < content   (backs up, skips when identical)
    local f=$1 tmp
    ensure_workdir
    tmp=$(mktemp -p "$WORKDIR")
    cat > "$tmp"
    mkdir -p "$(dirname "$f")"
    if [[ -f "$f" ]] && cmp -s "$tmp" "$f"; then
        note "unchanged: $f"
        rm -f "$tmp"
        return 0
    fi
    backup_file "$f"
    cp "$tmp" "$f"
    rm -f "$tmp"
    ok "wrote $f"
}

write_root_file() {   # write_root_file PATH  < content
    local f=$1 tmp
    ensure_workdir
    tmp=$(mktemp -p "$WORKDIR")
    cat > "$tmp"
    if as_root test -f "$f" && as_root cmp -s "$tmp" "$f"; then
        note "unchanged: $f"
        rm -f "$tmp"
        return 0
    fi
    backup_root_file "$f"
    as_root install -D -m 644 "$tmp" "$f"
    rm -f "$tmp"
    ok "wrote $f"
}

set_block() {   # set_block FILE ID COMMENT_PREFIX < content   (idempotent marked block)
    local f=$1 id=$2 prefix=$3 tmp rc
    ensure_workdir
    tmp=$(mktemp -p "$WORKDIR")
    cat > "$tmp"
    mkdir -p "$(dirname "$f")"
    touch "$f"
    backup_file "$f"
    python3 "$WORKDIR/set_block.py" "$f" "$prefix >>> setup-script:$id >>>" \
        "$prefix <<< setup-script:$id <<<" "$tmp"
    rc=$?
    rm -f "$tmp"
    return $rc
}

snapshot() {   # snapshot TAG file...
    local tag=$1 f
    shift
    mkdir -p "$WORKDIR/snap-$tag"
    for f in "$@"; do
        [[ -f "$f" ]] && cp -a "$f" "$WORKDIR/snap-$tag/$(printf '%s' "$f" | tr '/' '_')"
    done
    return 0
}

restore() {    # restore TAG file...
    local tag=$1 f s
    shift
    for f in "$@"; do
        s="$WORKDIR/snap-$tag/$(printf '%s' "$f" | tr '/' '_')"
        [[ -f "$s" ]] && cp -a "$s" "$f"
    done
    return 0
}

hypr_errors() {
    if hypr_running; then
        hyprctl configerrors 2>/dev/null | sed '/^[[:space:]]*$/d'
    fi
    return 0
}

# Reload Hyprland; succeed only if no NEW config errors appeared.
hypr_validate() {
    hypr_running || return 0
    hyprctl reload >/dev/null 2>&1
    sleep 1
    [[ "$(hypr_errors)" == "$HYPR_BASELINE" ]]
}

# ----------------------------------------------------- embedded python tools --
write_python_tools() {
    ensure_workdir

cat > "$WORKDIR/lualib.py" <<'PY'
import re

LONG_OPEN = re.compile(r'\[(=*)\[')


def find_matching(text, open_idx):
    """Index of the bracket that closes text[open_idx] (Lua-aware), or -1."""
    n = len(text)
    stack = []
    i = open_idx
    while i < n:
        c = text[i]
        if c == '-' and text.startswith('--', i):
            m = LONG_OPEN.match(text, i + 2)
            if m:
                close = ']' + m.group(1) + ']'
                j = text.find(close, m.end())
                i = n if j == -1 else j + len(close)
            else:
                j = text.find('\n', i)
                i = n if j == -1 else j + 1
            continue
        if c in ('"', "'"):
            q = c
            i += 1
            while i < n and text[i] != q:
                if text[i] == '\\':
                    i += 1
                i += 1
            i += 1
            continue
        if c == '[':
            m = LONG_OPEN.match(text, i)
            if m:
                close = ']' + m.group(1) + ']'
                j = text.find(close, m.end())
                i = n if j == -1 else j + len(close)
                continue
        if c in '({[':
            stack.append(c)
        elif c in ')}]':
            if not stack:
                return -1
            stack.pop()
            if not stack:
                return i
        i += 1
    return -1
PY

cat > "$WORKDIR/set_block.py" <<'PY'
import os
import re
import sys

path, begin, end, content_file = sys.argv[1:5]
content = open(content_file, encoding="utf-8").read().rstrip("\n")
text = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
block = "%s\n%s\n%s\n" % (begin, content, end)
pat = re.compile(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", re.S)
if pat.search(text):
    text = pat.sub(lambda m: block, text, count=1)
else:
    if text and not text.endswith("\n"):
        text += "\n"
    if text:
        text += "\n"
    text += block
open(path, "w", encoding="utf-8").write(text)
PY

cat > "$WORKDIR/patch_inputs.py" <<'PY'
import re
import sys

sys.path.insert(0, sys.argv[1])
from lualib import find_matching  # noqa: E402

path, mode = sys.argv[2], sys.argv[3]
VALUES = {"kb_layout": "us,ir", "kb_options": "grp:alt_shift_toggle"}
text = open(path, encoding="utf-8").read()


def targeted(text):
    """Change only kb_layout / kb_options; keep every other input setting."""
    lines = text.split("\n")
    found = {k: False for k in VALUES}
    for idx, line in enumerate(lines):
        if line.lstrip().startswith("--"):
            continue
        for key in VALUES:
            if found[key]:
                continue
            m = re.search(r'(\b%s\s*=\s*)(["\']).*?\2' % key, line)
            if m:
                lines[idx] = (line[:m.start()] + m.group(1)
                              + '"%s"' % VALUES[key] + line[m.end():])
                found[key] = True
    text = "\n".join(lines)
    missing = [k for k, v in found.items() if not v]
    if not missing:
        return text
    add = "".join('\n        %s = "%s",' % (k, VALUES[k]) for k in missing)
    m = re.search(r'(?m)^(?![ \t]*--).*?\binput\s*=\s*\{', text)
    if m:
        return text[:m.end()] + add + text[m.end():]
    body = "".join('        %s = "%s",\n' % (k, VALUES[k]) for k in missing)
    return (text.rstrip("\n")
            + '\n\nhl.config({\n    input = {\n' + body + '    },\n})\n')


def replace_block(text):
    """Old behaviour: replace the first hl.config({ ... }) with a clean block."""
    start = text.find("hl.config({")
    if start == -1:
        raise SystemExit("hl.config({ not found in inputs.lua")
    end = find_matching(text, text.find("(", start))
    if end == -1:
        raise SystemExit("could not find the end of hl.config({ ... })")
    new = '''hl.config({
    input = {
        kb_layout = "us,ir",
        kb_variant = "",
        kb_model = "",
        kb_options = "grp:alt_shift_toggle",
        kb_rules = "",
        accel_profile = "flat",
    },
})'''
    return text[:start] + new + text[end + 1:]


out = targeted(text) if mode == "targeted" else replace_block(text)
open(path, "w", encoding="utf-8").write(out)
PY

cat > "$WORKDIR/patch_binds.py" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()

# 1) Remove blocks generated by the old scripts (some had broken Lua).
legacy = re.compile(r'HyDE[- ]style workspace switching', re.I)
while True:
    m = legacy.search(text)
    if not m:
        break
    ls = text.rfind("\n", 0, m.start()) + 1
    if ls > 0:
        prev_start = text.rfind("\n", 0, ls - 1) + 1
        if re.match(r'\s*--\s*=+\s*$', text[prev_start:ls - 1]):
            ls = prev_start
    em = re.compile(r'(?m)^end[ \t]*$').search(text, m.end())
    if not em:
        break
    te = em.end()
    if text[te:te + 1] == "\n":
        te += 1
    text = text[:ls] + text[te:]

# 2) (Re)write our managed block.
begin = "-- >>> setup-script:workspaces >>>"
end = "-- <<< setup-script:workspaces <<<"
block = begin + '''
-- Workspaces 1..NUM_WPM
--   Super + 1..0         focus workspace
--   Super + Shift + 1..0 move the focused window
if NUM_WPM and mainMod and digitCode then
    for i = 1, NUM_WPM do
        local key = i % 10

        hl.bind(
            mainMod .. " + " .. digitCode(key),
            hl.dsp.focus({ workspace = i })
        )

        hl.bind(
            mainMod .. " + SHIFT + " .. digitCode(key),
            hl.dsp.window.move({ workspace = i })
        )
    end
end
''' + end + "\n"
pat = re.compile(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", re.S)
if pat.search(text):
    text = pat.sub(lambda m: block, text, count=1)
else:
    text = text.rstrip("\n") + "\n\n" + block
open(path, "w", encoding="utf-8").write(text)
PY

cat > "$WORKDIR/patch_rules.py" <<'PY'
import re
import sys

sys.path.insert(0, sys.argv[1])
from lualib import find_matching  # noqa: E402

path = sys.argv[2]
text = open(path, encoding="utf-8").read()
spans = []
for m in re.finditer(r'hl\.window_rule\s*\(', text):
    ls = text.rfind("\n", 0, m.start()) + 1
    if text[ls:m.start()].lstrip().startswith("--"):
        continue
    end = find_matching(text, m.end() - 1)
    if end == -1:
        continue
    if re.search(r'dolphin', text[m.start():end + 1], re.I):
        spans.append((m.start(), end + 1))
for s, e in reversed(spans):
    if text[e:e + 1] == "\n":
        e += 1
    text = text[:s] + "-- (Dolphin floating rule removed by setup script)\n" + text[e:]
open(path, "w", encoding="utf-8").write(text)
print(len(spans))
PY

cat > "$WORKDIR/noctalia_toml.py" <<'PY'
import pathlib
import re
import sys
import tomllib

path = pathlib.Path(sys.argv[1])
KEY = "enable_ddcutil"
if not path.exists():
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("[brightness]\nenable_ddcutil = true\n", encoding="utf-8")
    print("created")
    sys.exit(0)
text = path.read_text(encoding="utf-8")
try:
    data = tomllib.loads(text)
except Exception as exc:  # noqa: BLE001
    print("config.toml is not valid TOML, left untouched: %s" % exc)
    sys.exit(2)
tbl = data.get("brightness")
if isinstance(tbl, dict) and tbl.get(KEY) is True:
    print("already enabled")
    sys.exit(0)
lines = text.split("\n")
done = False
for i, line in enumerate(lines):
    if re.match(r'^\s*enable_ddcutil\s*=', line):
        lines[i] = re.sub(r'=.*$', '= true', line)
        done = True
        break
if not done:
    for i, line in enumerate(lines):
        if re.match(r'^\s*\[brightness\]\s*(#.*)?$', line):
            lines.insert(i + 1, "enable_ddcutil = true")
            done = True
            break
if not done:
    if lines and lines[-1] != "":
        lines.append("")
    lines += ["[brightness]", "enable_ddcutil = true", ""]
new = "\n".join(lines)
try:
    tomllib.loads(new)
except Exception as exc:  # noqa: BLE001
    print("refusing to write invalid TOML: %s" % exc)
    sys.exit(3)
path.write_text(new, encoding="utf-8")
print("updated")
PY

cat > "$WORKDIR/pacseek_cfg.py" <<'PY'
import json
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
changed = 0


def fix(v):
    global changed
    if isinstance(v, str) and re.search(r'\byay\b', v):
        changed += 1
        return re.sub(r'\byay\b', 'paru', v)
    if isinstance(v, dict):
        return {k: fix(x) for k, x in v.items()}
    if isinstance(v, list):
        return [fix(x) for x in v]
    return v


new = fix(data)
if changed:
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(new, fh, indent=2)
print(changed)
PY

cat > "$WORKDIR/clean_log.py" <<'PY'
# Turn a raw PTY transcript into a readable log. Terminal behaviour is emulated where it
# matters: carriage return overwrites the line, ESC[K / ESC[2K erase, backspace moves back.
# Colour codes, cursor movement and OSC titles (incl. sudo's OSC 3008 markers) are dropped.
import re
import sys

OSC = re.compile(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)')
CSI = re.compile(r'\x1b\[[0-9;?]*[ -/]*[@-~]')


def render(text):
    text = OSC.sub('', text)
    text = re.sub(r'\]3008;[^\s\\]*\\', '', text)      # leftovers when ESC was stripped
    lines, buf, cur = [], [], 0
    i, n = 0, len(text)
    while i < n:
        m = CSI.match(text, i)
        if m:
            seq = m.group(0)
            if seq.endswith('K'):
                params = seq[2:-1]
                if params in ('', '0'):
                    del buf[cur:]                       # erase to end of line
                elif params == '2':
                    buf, cur = [], 0                    # erase whole line
            i = m.end()
            continue
        ch = text[i]
        i += 1
        if ch == '\r':
            cur = 0
        elif ch == '\n':
            lines.append(''.join(buf).rstrip())
            buf, cur = [], 0
        elif ch == '\x08':
            cur = max(0, cur - 1)
        else:
            if cur < len(buf):
                buf[cur] = ch
            else:
                buf.append(ch)
            cur += 1
    lines.append(''.join(buf).rstrip())
    return lines


def main():
    keep = []
    for line in render(sys.stdin.read()):
        if line.startswith('Script ') and (' started' in line or ' done' in line):
            continue
        keep.append(line)
    while keep and not keep[-1]:
        keep.pop()
    sys.stdout.write('\n'.join(keep) + '\n')


main()
PY
}

# ============================================================================
#  PREFLIGHT
# ============================================================================
banner() {
    printf '%s' "$C_BOLD$C_BLUE"
    cat <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║     CachyOS + Hyprland + Noctalia — Complete Post-Install        ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    printf '%s' "$C_RESET"
    info "Log file : $LOG_FILE"
    info "Backups  : $BACKUP_DIR"
}

check_reach() {
    local label=$1 url=$2
    if reachable "$url"; then
        printf '%s       %s✔%s %s\n' "$(_ts)" "$C_GREEN" "$C_RESET" "$label"
    else
        printf '%s       %s✘%s %s  (unreachable — related steps may fail; try --proxy)\n' \
            "$(_ts)" "$C_RED" "$C_RESET" "$label"
    fi
}

report_previous_run() {
    local raw log last
    for raw in "$LOG_DIR"/*.log.raw; do
        [[ -e "$raw" ]] || continue
        [[ "$raw" == "$LOG_FILE.raw" ]] && continue
        log="${raw%.raw}"
        last="$(sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' "$raw" | tr -d '\r' | grep -a '━━━' | tail -1 | sed 's/━//g')"
        warn "A previous run never finished (crash / power loss / forced reboot): $(basename "$log")"
        [[ -n "$last" ]] && note "it stopped during:$last"
        python3 "$WORKDIR/clean_log.py" <"$raw" >"$log" 2>/dev/null || true
        rm -f "$raw"
        note "full log saved: $log"
    done
    return 0
}

check_resources() {
    local mem_kb swap_kb cores
    mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
    swap_kb=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
    cores=$(nproc 2>/dev/null || echo '?')
    info "Resources: $(( ${mem_kb:-0} / 1024 / 1024 )) GB RAM, $(( ${swap_kb:-0} / 1024 / 1024 )) GB swap/zram, $cores CPU threads"
    if (( ${mem_kb:-0} < 7500000 )); then
        warn "Less than 8 GB RAM: large AUR builds are disabled and builds run at low priority"
    fi
}

# Proxy: remembered in ~/.config/cachyos-setup/proxy so the Spotify helpers use it too.
load_proxy_file() {
    if [[ -n "$PROXY_URL" ]]; then
        mkdir -p "$(dirname "$PROXY_FILE")"
        printf '%s\n' "$PROXY_URL" >"$PROXY_FILE"
    elif [[ -f "$PROXY_FILE" ]]; then
        PROXY_URL=$(head -1 "$PROXY_FILE")
    fi
    if [[ -n "$PROXY_URL" ]]; then
        export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$PROXY_URL"
        export HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL" ALL_PROXY="$PROXY_URL"
        # shellcheck disable=SC2054  # sudo's --preserve-env takes a comma-separated list
    SUDO=(sudo --preserve-env=http_proxy,https_proxy,all_proxy,HTTP_PROXY,HTTPS_PROXY,ALL_PROXY)
    fi
}

preflight() {
    info "Preflight checks"
    [[ $EUID -ne 0 ]] || die "Do not run this script as root (it uses sudo when needed)."
    have pacman  || die "pacman not found — this script is for Arch / CachyOS."
    have sudo    || die "sudo is required."
    have python3 || die "python3 is required."
    have curl    || die "curl is required (sudo pacman -S curl)."

    if [[ -r /etc/os-release ]] && ! grep -qiE 'cachyos|arch' /etc/os-release; then
        warn "This does not look like CachyOS/Arch — continuing anyway."
    fi

    if hypr_running; then
        ok "Hyprland session detected"
    else
        warn "Not inside a Hyprland session: files will be configured, but live reload/tests are skipped."
    fi

    load_proxy_file
    [[ -n "$PROXY_URL" ]] && ok "Using proxy: $PROXY_URL"

    info "Network reachability"
    check_reach "archlinux.org (mirrors)"    "https://archlinux.org"
    check_reach "aur.archlinux.org (AUR)"    "https://aur.archlinux.org"
    check_reach "github.com (releases)"      "https://github.com"
    check_reach "repository.spotify.com"     "https://repository.spotify.com/"

    report_previous_run
    check_resources
    ((NO_LIVE)) && note "--no-live: the running desktop will not be touched"

    ((SKIP_UPDATE)) || ask_mirror_check

    info "Authenticating with sudo"
    sudo -v || die "sudo authentication failed."
    (
        while true; do
            sudo -n true 2>/dev/null
            sleep 50
            kill -0 "$$" 2>/dev/null || exit 0
        done
    ) &
    SUDO_KEEPALIVE_PID=$!
    ok "sudo session will be kept alive during long AUR builds"

    # a forced reboot during pacman leaves a stale lock behind
    pacman_unlock_wait || die "The package manager is locked by another process."
}

# ============================================================================
#  STEP: system update + base packages
# ============================================================================
# true when pacman, after line $2 of its log, upgraded or installed a kernel or a graphics component
reboot_needed_since() {    # $1 = pacman log, $2 = number of lines that were already there
    [[ -f "$1" ]] || return 1
    tail -n +"$(( $2 + 1 ))" "$1" \
        | grep -E '\] \[ALPM\] (upgraded|installed) (linux|nvidia|mesa|egl-wayland|libglvnd|vulkan|wayland|xorg-xwayland|hyprland)' >/dev/null
}

# printed instead of reloading the desktop when a kernel or graphics driver changed
reboot_required_notice() {
    printf '\n%s%s' "$C_BOLD" "$C_YELLOW"
    cat <<'EOF'
==============================================================================
  REBOOT FIRST
  A kernel or graphics driver was updated in this run. The running system still
  uses the old one, and reloading the desktop now can leave the screen black or
  the session frozen. The rest of the setup is paused until you reboot.
==============================================================================
EOF
    printf '%s\n' "$C_RESET"
    note "Reboot, then run:  ./setup-cachyos-full.sh --skip-update"
    note "The steps that already finished are skipped on the next run."
    note "The desktop was not reloaded in this run."
}

# Asked once, before anything is installed. Enter (or no answer within a minute) means yes.
ask_mirror_check() {
    [[ "$MIRROR_CHECK" == ask ]] || return 0
    if [[ ! -t 0 ]]; then
        MIRROR_CHECK=1
        note "no terminal to ask: the mirror check will run (--no-mirror-check skips it)"
        return 0
    fi
    local answer=""
    printf '%s' "Test the package mirrors before the system update? (about a minute, about 15 MB of test downloads) [Y/n] "
    read -r -t 60 answer || true
    echo
    MIRROR_CHECK="$(mirror_answer "$answer")"
    if [[ "$MIRROR_CHECK" == 1 ]]; then
        ok "mirror check: yes"
    else
        note "mirror check: skipped by your answer"
    fi
}

# Maps an answer to 1 (test the mirrors) or 0 (skip). Only "n" or "no" means no.
mirror_answer() {
    case "${1,,}" in
        n|no) echo 0 ;;
        *)    echo 1 ;;
    esac
}

# Tests the configured package mirrors and puts the working ones first (fastest first).
# Nothing is removed from the mirror lists: unreachable servers only move to the end.
check_mirrors() {
    ask_mirror_check
    [[ "$MIRROR_CHECK" == 1 ]] || { note "mirror check skipped"; return 0; }
    have python3 || { warn "python3 is missing: mirror check skipped"; return 0; }
    ensure_workdir
    local stage target staged
    stage=$(mktemp -d "$WORKDIR/mirrors.XXXXXX") || return 0
    info "Testing the package mirrors (working ones first, fastest first)"
    if ! PACMAN_CONF="${PACMAN_CONF:-/etc/pacman.conf}" python3 - "$stage" <<'PY'
import concurrent.futures as cf
import os
import re
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import urlparse

conf = os.environ.get("PACMAN_CONF", "/etc/pacman.conf")
stage = sys.argv[1]
arch = os.uname().machine
TIMEOUT = 8.0
# the user agent pacman itself sends: several mirrors answer 403 to the default Python one
PACMAN_UA = "pacman/7.0.0 (Linux x86_64) libalpm/16.0.1"
SERVER = re.compile(r"^\s*Server\s*=\s*(\S+)")

if not os.path.isfile(conf):
    print("  %s not found: nothing to check" % conf)
    sys.exit(0)

# mirrorlist files that repositories include, with the first repository that uses each file
section, use = None, {}
with open(conf, encoding="utf-8", errors="replace") as fh:
    for raw in fh:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^\[(.+)\]$", line)
        if m:
            section = m.group(1)
            continue
        m = re.match(r"^Include\s*=\s*(\S+)", line)
        if m and section not in (None, "options"):
            use.setdefault(m.group(1), section)


def host(url, repo):
    return urlparse(url.replace("$repo", repo).replace("$arch", arch)).netloc


SAMPLE = 256 * 1024      # bytes downloaded from each server to measure its speed
DEADLINE = 10.0          # seconds allowed for that sample


def probe(url, repo):
    # pacman appends "<repo>.db" to the server URL after replacing $repo and $arch
    base = url.replace("$repo", repo).replace("$arch", arch).rstrip("/")
    req = urllib.request.Request(base + "/" + repo + ".db", headers={"User-Agent": PACMAN_UA})
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            if resp.status not in (200, 206):
                return False, 0.0, 0.0, "HTTP %d" % resp.status
            got, first = 0, None
            while got < SAMPLE and time.monotonic() - t0 < DEADLINE:
                chunk = resp.read1(65536)
                if not chunk:
                    break
                if first is None:
                    first = time.monotonic() - t0
                got += len(chunk)
        if got < 4096:
            return False, 0.0, 0.0, "empty response"
        elapsed = max(time.monotonic() - t0, 1e-3)
        return True, first, got / elapsed / 1024.0, ""
    except urllib.error.HTTPError as e:
        return False, 0.0, 0.0, "HTTP %d" % e.code
    except Exception as e:
        return False, 0.0, 0.0, str(getattr(e, "reason", e))[:60]

changes = []
for path, repo in use.items():
    if not os.path.isfile(path):
        print("  %s is missing: skipped" % path)
        continue
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines(keepends=True)
    idx = [i for i, l in enumerate(lines) if SERVER.match(l)]
    if not idx:
        continue
    texts = [lines[i] if lines[i].endswith("\n") else lines[i] + "\n" for i in idx]
    urls = [SERVER.match(t).group(1) for t in texts]
    with cf.ThreadPoolExecutor(max_workers=8) as ex:
        res = list(ex.map(lambda u: probe(u, repo), urls))
    good = [k for k in range(len(urls)) if res[k][0]]
    print("  %s [%s]: %d servers, %d working" % (path, repo, len(urls), len(good)))
    if not good:
        print("      no working server: the order is left as it is")
        continue
    best = max(good, key=lambda k: res[k][2])
    print("      fastest: %s (%.0f KiB/s, first byte %.2f s)" % (host(urls[best], repo), res[best][2], res[best][1]))
    bad = [k for k in range(len(urls)) if not res[k][0]]
    for k in bad[:5]:
        print("      not working: %s (%s)" % (host(urls[k], repo), res[k][3]))
    if len(bad) > 5:
        print("      and %d more not working" % (len(bad) - 5))
    order = sorted(range(len(urls)), key=lambda k: (0, -res[k][2], res[k][1], k) if res[k][0] else (1, 0, 0, k))
    if order == list(range(len(urls))):
        continue
    new = list(lines)
    for pos, k in zip(idx, order):
        new[pos] = texts[k]
    staged = os.path.join(stage, "list%d" % len(changes))
    with open(staged, "w", encoding="utf-8") as fh:
        fh.write("".join(new))
    changes.append((path, staged))
    print("      order changed: working servers first, fastest first")

with open(os.path.join(stage, "manifest.tsv"), "w", encoding="utf-8") as fh:
    for path, staged in changes:
        fh.write("%s\t%s\n" % (path, staged))
PY
    then
        warn "The mirror check could not finish; the current mirror order is kept"
        rm -rf "$stage"
        return 0
    fi
    if [[ -s "$stage/manifest.tsv" ]]; then
        while IFS=$'\t' read -r target staged; do
            write_root_file "$target" < "$staged" || warn "could not update $target"
        done < "$stage/manifest.tsv"
        ok "Mirror order updated (backups in $BACKUP_DIR)"
    else
        note "No mirror order change was needed"
    fi
    rm -rf "$stage"
}

step_update() {
    step "Mirror check and system update (pacman -Syu)"
    check_mirrors
    local before=0
    [[ -f /var/log/pacman.log ]] && before=$(wc -l < /var/log/pacman.log)
    if pacman_unlock_wait && retry 2 as_root pacman -Syu --noconfirm; then
        ok "System is up to date"
        if reboot_needed_since /var/log/pacman.log "$before"; then
            REBOOT_REQUIRED=1
            warn "A kernel or graphics driver was updated; the running system still uses the old one"
        else
            note "No kernel or graphics driver changed."
        fi
    else
        warn "System update failed — continuing with the existing package versions."
    fi
}

step_base() {
    step "Base packages (fonts, themes, Qt/GTK, portals, tools, Spotify prerequisites)"
    local -a pkgs=(
        base-devel git curl wget unzip zip perl python
        fontconfig glib2 gsettings-desktop-schemas libxkbcommon xkeyboard-config
        noto-fonts noto-fonts-emoji noto-fonts-extra ttf-jetbrains-mono-nerd
        gtk3 gtk4 adw-gtk-theme qt5ct qt6ct qt5-wayland qt6-wayland kitty
        polkit udisks2 ntfs-3g i2c-tools ddcutil libcap util-linux
        xdg-utils xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
        libnotify
    )
    pac_install_list "Base packages" "${pkgs[@]}"
}

step_helpers() {
    step "AUR helpers (paru, yay)"

    if have paru; then
        ok "paru is already installed ($(paru --version 2>/dev/null | head -1))"
        RES_SKIP+=("paru  (already installed)")
    else
        info "Installing paru"
        if pkg_in_repos paru && pac_install paru; then
            ok "paru installed from the repositories"
            RES_OK+=("paru  (AUR helper)")
        else
            info "paru is not in the repositories — building paru-bin from the AUR"
            ensure_workdir
            local d="$WORKDIR/paru-bin"
            if retry 3 bash -c 'rm -rf "$1"; git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$1"' _ "$d" \
               && (cd "$d" && makepkg -si --noconfirm --needed); then
                ok "paru installed"
                RES_OK+=("paru  (AUR helper)")
            else
                err "Could not install paru — AUR applications will be skipped."
                RES_FAIL+=("paru")
            fi
        fi
    fi

    if have yay; then
        ok "yay is already installed ($(yay --version 2>/dev/null | head -1))"
        RES_SKIP+=("yay  (already installed)")
    else
        info "Installing yay (AUR helper): repository package first, then yay-bin from the AUR"
        if pkg_in_repos yay && pac_install yay; then
            ok "yay installed from the repositories"
            RES_OK+=("yay  (AUR helper)")
        elif have paru && aur_install yay-bin && have yay; then
            ok "yay installed from the AUR (yay-bin)"
            RES_OK+=("yay  (AUR helper)")
        else
            err "Could not install yay"
            RES_FAIL+=("yay")
        fi
    fi
}

# ============================================================================
#  STEP: locale + Persian keyboard prerequisites
# ============================================================================
step_locale() {
    step "Locales: English + Persian"
    as_root sed -i -E \
        -e 's/^[[:space:]]*#[[:space:]]*(en_US\.UTF-8 UTF-8)/\1/' \
        -e 's/^[[:space:]]*#[[:space:]]*(fa_IR(\.UTF-8)? UTF-8)/\1/' \
        /etc/locale.gen
    if as_root locale-gen >/dev/null; then
        ok "locale-gen finished"
    else
        warn "locale-gen reported a problem"
    fi

    if locale -a | grep -i '^fa_IR' >/dev/null; then
        ok "fa_IR locale is available"
    else
        warn "fa_IR locale was not generated — check /etc/locale.gen"
    fi

    # Only set a default if none exists, so an existing choice is never overridden.
    if ! grep -q '^LANG=' /etc/locale.conf 2>/dev/null; then
        as_root localectl set-locale LANG=en_US.UTF-8 && ok "System default: en_US.UTF-8"
    else
        note "keeping existing system default: $(grep '^LANG=' /etc/locale.conf)"
    fi
}

# ============================================================================
#  STEP: Vazirmatn
# ============================================================================
install_vazirmatn_from_github() {
    local url="https://github.com/rastikerdar/vazirmatn/releases/download/v33.003/vazirmatn-v33.003.zip"
    local font_dir="$HOME/.local/share/fonts/Vazirmatn" tmp count=0 f
    ensure_workdir
    tmp="$WORKDIR/vazirmatn"
    mkdir -p "$tmp" "$font_dir"
    retry 3 curl -fL --retry 3 --connect-timeout 15 --max-time 180 -o "$tmp/v.zip" "$url" || return 1
    unzip -q -o "$tmp/v.zip" -d "$tmp/x" || return 1
    # static TTFs only — variable and web fonts only create duplicates
    while IFS= read -r -d '' f; do
        cp -f "$f" "$font_dir/"
        count=$((count + 1))
    done < <(find "$tmp/x" -type f -iname '*.ttf' \
                ! -ipath '*/variable/*' ! -ipath '*/webfonts/*' -print0)
    if ((count == 0)); then
        while IFS= read -r -d '' f; do
            cp -f "$f" "$font_dir/"
            count=$((count + 1))
        done < <(find "$tmp/x" -type f -iname '*.otf' -print0)
    fi
    ((count > 0)) || return 1
    ok "copied $count Vazirmatn font files to $font_dir"
}

step_vazirmatn() {
    step "Vazirmatn (Persian font)"
    local font_dir="$HOME/.local/share/fonts/Vazirmatn"

    if fc-list | grep -i vazirmatn >/dev/null; then
        ok "Vazirmatn is already visible to Fontconfig"
    else
        info "Vazirmatn not found — trying repository, GitHub release, then AUR"
        if pkg_in_repos ttf-vazirmatn && pac_install ttf-vazirmatn; then
            ok "installed ttf-vazirmatn from the repositories"
        elif install_vazirmatn_from_github; then
            :
        elif have paru && aur_install ttf-vazirmatn; then
            ok "installed ttf-vazirmatn from the AUR"
        else
            err "Could not install Vazirmatn"
            RES_FAIL+=("Vazirmatn font")
        fi
    fi

    # leftovers from older scripts
    if [[ -d "$font_dir" ]]; then
        find "$font_dir" -type d \( -name webfonts -o -name variable \) -prune \
            -exec rm -rf {} + 2>/dev/null || true
    fi
    fc-cache -f >/dev/null 2>&1

    if fc-match Vazirmatn | grep -i vazirmatn >/dev/null; then
        ok "fc-match Vazirmatn → $(fc-match Vazirmatn)"
        RES_OK+=("Vazirmatn font")
    else
        warn "fc-match does not resolve Vazirmatn"
    fi
}

# ============================================================================
#  STEP: fontconfig / GTK / Qt / UWSM / Kitty
# ============================================================================
step_theming() {
    step "Fonts & theming: Fontconfig, GTK, Qt, UWSM env, Kitty"

    # --- Fontconfig -----------------------------------------------------------
    local old="$HOME/.config/fontconfig/fonts.conf"
    if [[ -f "$old" ]] && grep -qi vazirmatn "$old"; then
        backup_file "$old"
        rm -f "$old"
        note "removed old fonts.conf created by an earlier script (backed up)"
    fi
    write_file "$HOME/.config/fontconfig/conf.d/65-persian-font.conf" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>

  <!-- Persian / Arabic text: Vazirmatn first -->
  <match target="pattern">
    <test name="lang" compare="contains"><string>fa</string></test>
    <edit name="family" mode="prepend" binding="strong">
      <string>Vazirmatn</string>
    </edit>
  </match>
  <match target="pattern">
    <test name="lang" compare="contains"><string>ar</string></test>
    <edit name="family" mode="prepend" binding="strong">
      <string>Vazirmatn</string>
    </edit>
  </match>

  <!-- Generic sans-serif -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Vazirmatn</family>
      <family>Noto Sans</family>
      <family>Noto Sans Arabic</family>
    </prefer>
  </alias>

  <!-- GNOME's Adwaita Sans has no Persian glyphs: fall back to Vazirmatn -->
  <alias>
    <family>Adwaita Sans</family>
    <prefer>
      <family>Adwaita Sans</family>
      <family>Vazirmatn</family>
    </prefer>
  </alias>

</fontconfig>
EOF
    fc-cache -f >/dev/null 2>&1

    # --- GTK 3 / 4 ------------------------------------------------------------
    write_file "$HOME/.config/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Adwaita
gtk-font-name=Vazirmatn 10
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintmedium
gtk-xft-rgba=rgb
gtk-application-prefer-dark-theme=1
EOF
    write_file "$HOME/.config/gtk-4.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Adwaita
gtk-font-name=Vazirmatn 10
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
EOF
    if have gsettings; then
        gsettings set org.gnome.desktop.interface font-name "Vazirmatn 10" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" 2>/dev/null || true
    fi

    # --- Qt 5 / 6 (also fixes Dolphin / Okular / Haruna look) -----------------
    local scheme="/usr/share/qt6ct/colors/darker.conf"
    [[ -f "$HOME/.config/qt6ct/colors/noctalia.conf" ]] && scheme="$HOME/.config/qt6ct/colors/noctalia.conf"
    [[ -f "$HOME/.config/qt6ct/colors/Noctalia.conf" ]] && scheme="$HOME/.config/qt6ct/colors/Noctalia.conf"
    local qtconf
    qtconf=$(cat <<EOF
[Appearance]
color_scheme_path=$scheme
custom_palette=true
icon_theme=Adwaita
standard_dialogs=default
style=Fusion

[Fonts]
fixed="JetBrainsMono Nerd Font,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
general="Vazirmatn,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
EOF
)
    printf '%s\n' "$qtconf" | write_file "$HOME/.config/qt6ct/qt6ct.conf"
    printf '%s\n' "$qtconf" | write_file "$HOME/.config/qt5ct/qt5ct.conf"

    # --- UWSM environment (managed block: your other variables are kept) ------
    set_block "$HOME/.config/uwsm/env" "base" "#" <<'EOF'
# Qt theming through qt6ct
export QT_QPA_PLATFORMTHEME=qt6ct
export LANG=en_US.UTF-8
# Electron / Chromium apps (VS Code, Obsidian, Chrome ...) use native Wayland
export ELECTRON_OZONE_PLATFORM_HINT=auto
EOF
    ok "UWSM environment updated: $HOME/.config/uwsm/env"

    # --- Kitty ---------------------------------------------------------------
    local kitty="$HOME/.config/kitty/kitty.conf"
    mkdir -p "$(dirname "$kitty")"
    touch "$kitty"
    if grep -q 'U+0600-U+06FF' "$kitty" && ! grep -q 'setup-script:persian' "$kitty"; then
        note "Kitty already has a Persian symbol_map — left as is"
    else
        set_block "$kitty" "persian" "#" <<'EOF'
# Persian / Arabic font fallback
symbol_map U+0600-U+06FF,U+0750-U+077F,U+08A0-U+08FF,U+FB50-U+FDFF,U+FE70-U+FEFF Vazirmatn
EOF
        ok "Kitty Persian font fallback configured"
    fi
}

# ============================================================================
#  STEP: Hyprland (Lua)
# ============================================================================
step_hyprland() {
    step "Hyprland: Persian keyboard, workspaces 1-10, Dolphin tiling"
    local cfg="$HOME/.config/hypr/config"
    local inputs="$cfg/inputs.lua" vars="$cfg/variables.lua" binds="$cfg/binds.lua"
    local rules="$cfg/windowrules.lua" wsp="$cfg/workspaces.lua"

    if [[ ! -d "$cfg" ]]; then
        warn "$cfg not found — Hyprland steps skipped."
        return 0
    fi
    HYPR_BASELINE="$(hypr_errors)"
    [[ -n "$HYPR_BASELINE" ]] && warn "Hyprland already reports config errors before we touch anything"

    # --- keyboard ------------------------------------------------------------
    if [[ -f "$inputs" ]]; then
        backup_file "$inputs"
        snapshot inputs "$inputs"
        if python3 "$WORKDIR/patch_inputs.py" "$WORKDIR" "$inputs" targeted && hypr_validate; then
            ok "inputs.lua: kb_layout = us,ir   kb_options = grp:alt_shift_toggle"
        else
            warn "Targeted edit was not accepted — falling back to full input-block replacement"
            restore inputs "$inputs"
            if python3 "$WORKDIR/patch_inputs.py" "$WORKDIR" "$inputs" replace && hypr_validate; then
                ok "inputs.lua rewritten (input block replaced)"
            else
                restore inputs "$inputs"
                hypr_validate
                err "Could not apply the keyboard layout — inputs.lua restored to its original state"
                RES_FAIL+=("Hyprland keyboard layout (inputs.lua)")
            fi
        fi
    else
        warn "inputs.lua not found — keyboard layout not configured"
        RES_FAIL+=("Hyprland keyboard layout (inputs.lua missing)")
    fi

    if hypr_running; then
        local active
        active="$(hyprctl getoption input:kb_layout 2>/dev/null | tr '\n' ' ')"
        note "active kb_layout: ${active:-unknown}"
        if grep -q 'us,ir' <<<"$active"; then
            ok "Hyprland is running with layouts us,ir"
        else
            warn "Hyprland does not report 'us,ir' yet — log out and in again, then run: hyprctl getoption input:kb_layout"
        fi
        if hyprctl switchxkblayout current 1 &>/dev/null; then
            sleep 0.5
            if hyprctl devices 2>/dev/null | grep -i 'active keymap:.*persian' >/dev/null; then
                ok "Functional test: keyboard switched to Persian"
                RES_OK+=("Persian keyboard (US + IR, Alt+Shift)")
            else
                warn "Switched layout, but Persian was not reported by hyprctl devices"
            fi
            hyprctl switchxkblayout current 0 &>/dev/null
            note "keyboard returned to English"
        fi
    fi

    # --- workspaces + binds --------------------------------------------------
    snapshot ws "$vars" "$wsp" "$binds"
    local touched=0
    if [[ -f "$vars" ]]; then
        backup_file "$vars"
        sed -E -i 's/\bNUM_WPM[[:space:]]*=[[:space:]]*[0-9]+/NUM_WPM = 10/' "$vars"
        touched=1
    fi
    if [[ -f "$wsp" ]]; then
        backup_file "$wsp"
        cat > "$wsp" <<'EOF'
-- Dynamic workspaces (HyDE style)
-- Workspaces are created on demand and removed automatically when empty.
EOF
        touched=1
    fi
    if [[ -f "$binds" ]]; then
        backup_file "$binds"
        if python3 "$WORKDIR/patch_binds.py" "$binds"; then touched=1; fi
    fi
    if ((touched)); then
        if hypr_validate; then
            ok "Workspaces 1-10: Super+1..0 focus, Super+Shift+1..0 move window"
            RES_OK+=("Hyprland workspaces 1-10")
        else
            restore ws "$vars" "$wsp" "$binds"
            hypr_validate
            err "Hyprland rejected the workspace changes — they were reverted automatically"
            RES_FAIL+=("Hyprland workspace binds (reverted)")
        fi
    else
        note "variables.lua / workspaces.lua / binds.lua not found — nothing to change"
    fi

    # --- Dolphin floating rule ----------------------------------------------
    if [[ -f "$rules" ]]; then
        snapshot rules "$rules"
        backup_file "$rules"
        local n
        n=$(python3 "$WORKDIR/patch_rules.py" "$WORKDIR" "$rules" 2>/dev/null | tail -1)
        if [[ "${n:-0}" -gt 0 ]]; then
            if hypr_validate; then
                ok "Removed $n Dolphin floating rule(s) — Dolphin now tiles"
            else
                restore rules "$rules"
                hypr_validate
                warn "Hyprland rejected the window-rule change — reverted"
            fi
        else
            note "no Dolphin floating rule found"
        fi
    fi

    hypr_running && hyprctl reload >/dev/null 2>&1
    return 0
}

# ============================================================================
#  STEP: NTFS / UDisks2 / Polkit
# ============================================================================
step_storage() {
    step "Storage: NTFS (ntfs-3g), UDisks2, passwordless mounting"

    write_root_file /etc/polkit-1/rules.d/10-udisks2-wheel-mount.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.udisks2.filesystem-mount" ||
         action.id == "org.freedesktop.udisks2.filesystem-mount-system") &&
        subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
EOF
    # duplicate rule file created by an older script
    if as_root test -f /etc/polkit-1/rules.d/10-udisks2.rules \
       && as_root grep -q 'filesystem-mount-system' /etc/polkit-1/rules.d/10-udisks2.rules; then
        backup_root_file /etc/polkit-1/rules.d/10-udisks2.rules
        as_root rm -f /etc/polkit-1/rules.d/10-udisks2.rules
        note "removed duplicate polkit rule 10-udisks2.rules (same effect, now in 10-udisks2-wheel-mount.rules)"
    fi

    write_root_file /etc/udisks2/mount_options.conf <<'EOF'
[defaults]
ntfs_drivers=ntfs-3g
EOF
    if [[ ! -e /usr/bin/mount.ntfs && -x /usr/bin/ntfs-3g ]]; then
        as_root ln -s /usr/bin/ntfs-3g /usr/bin/mount.ntfs
    fi
    as_root systemctl restart udisks2 2>/dev/null || true
    ok "NTFS volumes mount through ntfs-3g without a password prompt (wheel group)"
    RES_OK+=("NTFS / UDisks2 / Polkit")
}

# ============================================================================
#  STEP: DDC/CI brightness + Noctalia
# ============================================================================
step_ddc() {
    step "External monitor brightness (DDC/CI) + Noctalia"
    local me
    me="$(id -un)"

    write_root_file /etc/modules-load.d/i2c-dev.conf <<'EOF'
i2c-dev
EOF
    as_root groupadd -f i2c
    if id -nG "$me" | grep -w i2c >/dev/null; then
        note "$me is already in the i2c group"
    else
        as_root usermod -aG i2c "$me" && ok "added $me to the i2c group (takes effect after re-login)"
    fi
    local udev_rule=/etc/udev/rules.d/99-i2c-permissions.rules rule_before rule_now
    rule_before="$(cat "$udev_rule" 2>/dev/null || true)"
    write_root_file "$udev_rule" <<'EOF'
KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
EOF
    rule_now="$(cat "$udev_rule" 2>/dev/null || true)"
    # Nothing is re-triggered while the desktop runs: re-triggering the i2c devices froze the monitor image.
    # i2c-dev loads at boot (modules-load.d) and the rule applies to the devices created then.
    if [[ "$rule_now" != "$rule_before" ]]; then
        note "DDC/CI permissions are set; they take effect after the next reboot"
    else
        note "DDC/CI permissions were already in place"
    fi
    local conf="$HOME/.config/noctalia/config.toml" res rc
    backup_file "$conf"
    res="$(python3 "$WORKDIR/noctalia_toml.py" "$conf" 2>&1)"
    rc=$?
    case $rc in
        0) ok "Noctalia: [brightness] enable_ddcutil = true  ($res)" ;;
        *) warn "Noctalia config not changed: $res" ;;
    esac
    # state files can override the config
    local f
    for f in "$HOME"/.local/state/noctalia/*.toml; do
        [[ -f "$f" ]] && sed -i 's/enable_ddcutil = false/enable_ddcutil = true/' "$f"
    done

    if have noctalia && noctalia config validate &>/dev/null; then
        ok "noctalia config validate passed"
    else
        note "could not run 'noctalia config validate' (command missing or not supported)"
    fi
    RES_OK+=("DDC/CI brightness (Noctalia)")
}

# ============================================================================
#  STEP: MPD + rmpc
# ============================================================================
step_mpd() {
    step "MPD + rmpc (music)"
    install_app "MPD" pacman:mpd
    install_app "rmpc" pacman:rmpc aur:rmpc

    local mpd_dir="$HOME/.config/mpd" rmpc_dir="$HOME/.config/rmpc"
    mkdir -p "$HOME/Music" "$mpd_dir/playlists" "$rmpc_dir"

    if [[ -s "$mpd_dir/mpd.conf" ]] && grep -q '^music_directory' "$mpd_dir/mpd.conf"; then
        note "keeping existing $mpd_dir/mpd.conf"
    else
        write_file "$mpd_dir/mpd.conf" <<'EOF'
music_directory "~/Music"

database {
    plugin "simple"
    path "~/.config/mpd/database"
}

playlist_directory "~/.config/mpd/playlists"

state_file "~/.config/mpd/state"
sticker_file "~/.config/mpd/sticker.sql"

bind_to_address "127.0.0.1"
port "6600"

audio_output {
    type "pipewire"
    name "PipeWire Output"
}
EOF
    fi

    if [[ -s "$rmpc_dir/config.ron" ]]; then
        note "keeping existing rmpc config"
    elif have rmpc; then
        rmpc config > "$rmpc_dir/config.ron" 2>/dev/null && ok "generated default rmpc config"
    fi

    if systemctl --user daemon-reload && systemctl --user enable mpd &>/dev/null \
       && systemctl --user restart mpd; then
        sleep 1
    fi
    if systemctl --user is-active --quiet mpd; then
        ok "MPD user service is running (127.0.0.1:6600)"
        if have rmpc; then
            rmpc update >/dev/null 2>&1 || true
            if rmpc status >/dev/null 2>&1; then
                ok "rmpc connected to MPD — put music in ~/Music and run: rmpc"
            else
                warn "rmpc could not talk to MPD"
            fi
        fi
    else
        warn "MPD user service is not running — see: systemctl --user status mpd"
    fi
}

# ============================================================================
#  STEP: applications
# ============================================================================
step_apps() {
    step "Applications"
    info "Official repository apps first (fast), then AUR"
    note "Download progress and speed are shown live by pacman and paru below"
    APP_NO=0
    APP_TOTAL=22

    install_app "Telegram Desktop" pacman:telegram-desktop
    install_app "mpv"              pacman:mpv
    install_app "aria2"            pacman:aria2
    install_app "Haruna"           pacman:haruna
    install_app "OBS Studio"       pacman:obs-studio
    install_app "Okular"           pacman:okular
    install_app "Obsidian"         pacman:obsidian
    install_app "Xournal++"        pacman:xournalpp
    install_app "bandwhich"        pacman:bandwhich
    install_app "zellij"           pacman:zellij
    install_app "nvtop"            pacman:nvtop
    install_app "fzf"              pacman:fzf
    install_app "uv (Python)"      pacman:uv
    install_app "kew"              pacman:kew aur:kew

    install_app "Anki"             pacman:anki aur:anki-bin
    install_app "LocalSend"        pacman:localsend aur:localsend-bin
    install_app "OnlyOffice"       aur:onlyoffice-bin
    install_app "Visual Studio Code" aur:visual-studio-code-bin pacman:code
    install_app "pacseek"          pacman:pacseek aur:pacseek aur:pacseek-bin

    # v2rayN needs its cores; install them first (non-fatal helpers)
    info "v2rayN helpers: xray core, sing-box, .NET 8 runtime"
    if pkg_installed xray || pkg_installed xray-bin; then
        note "xray core already installed"
    elif pkg_in_repos xray && pac_install xray; then
        note "xray core ready (repositories)"
    elif have paru && aur_install xray-bin; then
        note "xray core ready (AUR: xray-bin)"
    else
        warn "xray core could not be installed (v2rayN can download its own cores)"
    fi
    local helper
    for helper in sing-box dotnet-runtime-8.0; do
        if pkg_in_repos "$helper" && pac_install "$helper"; then
            note "$helper ready"
        else
            warn "v2rayN helper '$helper' could not be installed (v2rayN can download its own cores)"
        fi
    done
    # Prebuilt packages only. Building v2rayN (.NET SDK) or Hiddify (Flutter + Go) from source needs
    # many GB of RAM and can freeze the machine, so it is opt-in (--allow-source-builds).
    local -a v2ray_specs=(aur:v2rayn-bin) hiddify_specs=(aur:hiddify-desktop-bin aur:hiddify-next-bin)
    if ((ALLOW_SOURCE_BUILDS)); then
        v2ray_specs+=(aur:v2rayn)
        hiddify_specs+=(aur:hiddify)
    fi
    install_app "v2rayN"           "${v2ray_specs[@]}" \
        || note "no prebuilt v2rayN package worked — source builds are off (see --allow-source-builds)"
    install_app "Hiddify"          "${hiddify_specs[@]}" \
        || note "no prebuilt Hiddify package worked — source builds are off (see --allow-source-builds)"
    install_app "Google Chrome"    aur:google-chrome pacman:chromium
    APP_TOTAL=0
}

# ============================================================================
#  STEP: Spotify — client, optional SpotX (ad-block), Spicetify (Marketplace)
# ============================================================================
#  Default (verified): spotify-launcher from the repositories downloads Spotify's own Linux client,
#  Spicetify is applied with the original look, and the Marketplace is registered.
#  --spotify-aur installs the regular "spotify" package from the AUR into /opt/spotify instead.
#  Spicetify and SpotX must then write into that folder, so a pacman hook keeps it writable.
#  --spotx (on by default) applies SpotX (client-level ad-block); --no-spotx turns it off.
#
#  Order (checked in the Spicetify and SpotX sources and in the Spicetify docs):
#   - SpotX must run on a STOCK xpui.spa, before Spicetify extracts anything.
#   - Spicetify reads the Spotify version from the prefs file (app.last-launched-version), which
#     exists only after Spotify has run once. Spotify is started once (warm-up) and kept open for
#     SPOTIFY_WARMUP_HOLD seconds (the docs ask for about 60 s on a fresh install).
#   - Upgrades: the launcher replaces its client folder; with the AUR package, pacman upgrades it and
#     the hook removes the old Spicetify folder. A stock copy of xpui.spa is kept per version.

read_mark()   { cat "$SPOTIFY_MARKS/$1" 2>/dev/null || true; }
write_mark()  { mkdir -p "$SPOTIFY_MARKS"; printf '%s\n' "$2" >"$SPOTIFY_MARKS/$1"; }
clear_marks() { rm -f "$SPOTIFY_MARKS"/* 2>/dev/null || true; }
spotify_prefs_version() {
    [[ -f "$SPOTIFY_PREFS" ]] || return 0
    tr -d '\r' <"$SPOTIFY_PREFS" \
        | sed -nE 's/^app\.last-launched-version[[:space:]]*=[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/p' \
        | head -1
}
prefs_mtime() { stat -c %Y "$SPOTIFY_PREFS" 2>/dev/null || echo 0; }
spotify_running() { pgrep -x spotify >/dev/null 2>&1; }
spotify_stop() {
    spotify_running || return 0
    pkill -x spotify 2>/dev/null || true
    for _ in $(seq 1 20); do
        spotify_running || return 0
        sleep 1
    done
    pkill -9 -x spotify 2>/dev/null || true
    sleep 1
}
spotify_client_is_stock() {
    [[ -f "$SPOTIFY_DIR/Apps/xpui.spa" ]] || return 1
    [[ -z "$(find "$SPOTIFY_DIR/Apps" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ]]
}
spotify_stock_copy() { echo "$SPOTIFY_STOCK/xpui.spa.${1//[^A-Za-z0-9.]/_}"; }
spotify_save_stock() {    # $1 = package version; only call while the client is stock
    local dst
    dst=$(spotify_stock_copy "$1")
    mkdir -p "$SPOTIFY_STOCK"
    [[ -f "$dst" ]] || cp -a "$SPOTIFY_DIR/Apps/xpui.spa" "$dst"
}
spotify_restore_stock() {    # $1 = package version; fails when there is no copy for it
    local src
    src=$(spotify_stock_copy "$1")
    [[ -f "$src" ]] || return 1
    rm -rf "$SPOTIFY_DIR/Apps/xpui"
    cp -a "$src" "$SPOTIFY_DIR/Apps/xpui.spa"
}
spotify_prepare_permissions() {
    if [[ ! -w "$SPOTIFY_DIR/Apps" || ! -w "$SPOTIFY_DIR/Apps/xpui.spa" ]]; then
        as_root chmod a+wr "$SPOTIFY_DIR" && as_root chmod -R a+wr "$SPOTIFY_DIR/Apps"
    fi
}
spotx_patch() {
    local f
    ensure_workdir
    f="$WORKDIR/spotx.sh"
    info "Applying SpotX (ad-block) to the stock client"
    retry 3 curl -fsSL --connect-timeout 15 --max-time 120 -o "$f" "$SPOTX_URL" \
        || { err "Cannot download SpotX from $SPOTX_URL"; return 1; }
    bash "$f" -P "$SPOTIFY_DIR" --noninteractive 2>&1 | tee >(sed -u 's/\x1b\[[0-9;?]*[A-Za-z]//g' >>"$SPOTIFY_CLIENT_LOG")
    return "${PIPESTATUS[0]}"
}
spotify_warmup() {
    local before after start waited=0 pid hold_until
    before=$(spotify_prefs_version)
    start=$(date +%s)
    info "Starting Spotify once so it records its version (Spicetify needs it)"
    spotify_stop
    if [[ $SPOTIFY_SOURCE == aur ]]; then
        "$SPOTIFY_BIN" >>"$SPOTIFY_CLIENT_LOG" 2>&1 &
    else
        spotify-launcher --skip-update >>"$SPOTIFY_CLIENT_LOG" 2>&1 &
    fi
    pid=$!
    while (( waited < 150 )); do
        after=$(spotify_prefs_version)
        # Accept when the version is new, when this launch rewrote prefs, or when Spotify has
        # been up for 25 s with a version already recorded (an unchanged value is still correct).
        if [[ -n "$after" ]] && { [[ "$after" != "$before" ]] || (( $(prefs_mtime) >= start )) || (( waited >= 25 )); }; then
            local hold=$SPOTIFY_WARMUP_HOLD
            # an existing login is reused after an update: a short stay is enough
            if [[ -n "$before" ]] && (( hold > 20 )); then hold=20; fi
            ok "Spotify recorded its version: $after"
            notify "Spotify" "Keep Spotify open for ${hold} seconds"
            note "keeping Spotify open for ${hold}s (fresh installs: log in; the docs ask for 60s)"
            hold_until=$(( $(date +%s) + hold ))
            while (( $(date +%s) < hold_until )) && kill -0 "$pid" 2>/dev/null; do
                sleep 2
            done
            spotify_stop
            # stop by PID as well: the name check above does not cover every Spotify process
            pkill -P "$pid" 2>/dev/null || true
            kill "$pid" 2>/dev/null || true
            for _ in $(seq 1 10); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
            kill -9 "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 0
        fi
        sleep 3
        waited=$((waited + 3))
    done
    spotify_stop
    kill "$pid" 2>/dev/null || true
    err "Spotify did not record its version within 150s (it needs a graphical session)"
    return 1
}
spicetify_run() {    # run the Spicetify CLI and mirror its output to the log (colours stripped)
    "$SPICETIFY_BIN" "$@" 2>&1 | tee >(sed -u 's/\x1b\[[0-9;?]*[A-Za-z]//g' >>"$SPOTIFY_CLIENT_LOG")
    return "${PIPESTATUS[0]}"
}
spicetify_install_prebuilt() {
    local final ver tgz url
    [[ "$(uname -m)" == x86_64 ]] || return 1
    ensure_workdir
    tgz="$WORKDIR/spicetify.tar.gz"
    final=$(curl -fsSIL -o /dev/null -w '%{url_effective}' --max-time 30 "$SPICETIFY_RELEASES/latest") || return 1
    ver=${final##*/v}
    [[ "$ver" =~ ^[0-9.]+$ ]] || return 1
    url="$SPICETIFY_RELEASES/download/v$ver/spicetify-$ver-linux-amd64.tar.gz"
    retry 3 curl -fsSL --connect-timeout 15 --max-time 300 -o "$tgz" "$url" || return 1
    mkdir -p "$HOME/.spicetify" || return 1
    tar -xzf "$tgz" -C "$HOME/.spicetify" || return 1
    chmod +x "$HOME/.spicetify/spicetify"
    mkdir -p "$HOME/.local/bin"
    [[ -e "$HOME/.local/bin/spicetify" ]] || ln -s "$HOME/.spicetify/spicetify" "$HOME/.local/bin/spicetify"
}
spicetify_cli_ensure() {
    if [[ -x "$HOME/.spicetify/spicetify" ]]; then
        SPICETIFY_BIN="$HOME/.spicetify/spicetify"
    elif [[ -n "$(command -v spicetify 2>/dev/null)" && -x "$(command -v spicetify)" ]]; then
        SPICETIFY_BIN="$(command -v spicetify)"
    else
        info "Installing the Spicetify CLI (prebuilt binary)"
        if spicetify_install_prebuilt; then
            SPICETIFY_BIN="$HOME/.spicetify/spicetify"
        elif have paru && aur_install spicetify-cli && have spicetify; then
            SPICETIFY_BIN="$(command -v spicetify)"
        else
            err "Could not install the Spicetify CLI"
            return 1
        fi
    fi
    ok "Spicetify CLI: $("$SPICETIFY_BIN" -v 2>/dev/null | head -1)"
}
spicetify_configure() {
    rm -rf "$SPICETIFY_CFG/Themes/marketplace"     # placeholder theme from the first v1 script
    spicetify_run config spotify_path "$SPOTIFY_DIR" prefs_path "$SPOTIFY_PREFS" \
        inject_css 1 replace_colors 0
}
register_custom_app() {
    local name=$1 cfg="$SPICETIFY_CFG/config-xpui.ini" cur="" item new=""
    local -a items=()
    cur=$(tr -d '\r' <"$cfg" 2>/dev/null | sed -nE 's/^custom_apps[[:space:]]*=[[:space:]]*(.*)$/\1/p' | head -1)
    IFS='|' read -r -a items <<<"$cur"
    for item in "${items[@]}"; do
        item=${item//[[:space:]]/}
        [[ -z "$item" || "$item" == "$name" ]] && continue
        new+="$item|"
    done
    new+="$name"
    spicetify_run config custom_apps "$new"
}
marketplace_install() {
    local tmp src dest="$SPICETIFY_CFG/CustomApps/marketplace"
    ensure_workdir
    tmp="$WORKDIR/marketplace"
    rm -rf "$tmp"
    mkdir -p "$tmp" "$SPICETIFY_CFG/CustomApps"
    info "Downloading Spicetify Marketplace"
    retry 3 curl -fsSL --connect-timeout 15 --max-time 300 -o "$tmp/marketplace.zip" "$MARKETPLACE_URL" \
        || { err "Cannot download Marketplace from $MARKETPLACE_URL"; return 1; }
    unzip -q -o "$tmp/marketplace.zip" -d "$tmp/x" || { err "Marketplace archive is corrupt"; return 1; }
    src=""
    local manifest
    manifest=$(find "$tmp/x" -maxdepth 2 -name manifest.json 2>/dev/null | head -1)
    [[ -n "$manifest" ]] && src=$(dirname "$manifest")
    if [[ -z "$src" || ! -f "$src/index.js" ]]; then
        err "Marketplace archive has an unexpected layout"
        return 1
    fi
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -a "$src/." "$dest/"
    register_custom_app marketplace || return 1
    ok "Marketplace installed: $dest"
}
theme_install() {
    local name=$1 tmp dest
    dest="$SPICETIFY_CFG/Themes/$name"
    ensure_workdir
    tmp="$WORKDIR/themes"
    rm -rf "$tmp"
    info "Downloading theme '$name' (its files only, without screenshots)"
    retry 3 git clone -q --depth 1 --filter=blob:none --no-checkout "$THEMES_REPO" "$tmp" || return 1
    git -C "$tmp" sparse-checkout init --no-cone >/dev/null 2>&1 || true
    git -C "$tmp" sparse-checkout set --no-cone "/$name/*" "!/$name/*.png" "!/$name/*.jpg" "!/$name/*.gif" \
        >/dev/null 2>&1 || return 1
    git -C "$tmp" checkout -q HEAD || return 1
    if [[ ! -f "$tmp/$name/color.ini" || ! -f "$tmp/$name/user.css" ]]; then
        err "Theme '$name' was not found in spicetify-themes"
        return 1
    fi
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -a "$tmp/$name/." "$dest/"
    ok "Theme '$name' installed: $dest"
}
theme_setup() {
    local current=""
    current=$(tr -d '\r' <"$SPICETIFY_CFG/config-xpui.ini" 2>/dev/null \
        | sed -nE 's/^current_theme[[:space:]]*=[[:space:]]*(.*)$/\1/p' | head -1)
    # the placeholder theme of the first script version must not stay selected
    if [[ "$current" == marketplace ]]; then
        spicetify_run config current_theme "" color_scheme "" >/dev/null || true
        current=""
    fi
    if [[ -z "$SPOTIFY_THEME" ]]; then
        if [[ -z "$current" || "$current" == SpicetifyDefault ]]; then
            # the original Spotify look, as in the setup that was verified; themes are chosen in Marketplace
            spicetify_run config current_theme SpicetifyDefault color_scheme " " replace_colors 0 \
                overwrite_assets 0 inject_theme_js 0 >/dev/null || true
            ok "original Spotify look (SpicetifyDefault); pick a theme in Spotify > Marketplace"
        else
            note "keeping your theme: $current (change it in Spotify > Marketplace)"
        fi
        return 0
    fi
    if ! theme_install "$SPOTIFY_THEME"; then
        warn "Theme '$SPOTIFY_THEME' could not be installed; the current theme is kept"
        return 0
    fi
    local file="$SPICETIFY_CFG/Themes/$SPOTIFY_THEME/color.ini" scheme="$SPOTIFY_SCHEME"
    if ! tr -d '\r' <"$file" | grep "^\[$scheme\]" >/dev/null; then
        scheme=$(tr -d '\r' <"$file" | sed -nE 's/^\[([^]]+)\].*/\1/p' | head -1)
        warn "Colour scheme '$SPOTIFY_SCHEME' not found in $SPOTIFY_THEME; using '$scheme'"
    fi
    spicetify_run config current_theme "$SPOTIFY_THEME" color_scheme "$scheme" replace_colors 1 >/dev/null
    ok "Theme set: $SPOTIFY_THEME / $scheme"
}
spicetify_backup() {
    info "Backing up the stock client (records the Spotify version Spicetify depends on)"
    spicetify_run --no-restart backup
}
spicetify_apply() {
    spotify_stop
    info "Applying Spicetify (theme, Marketplace, custom modifications)"
    spicetify_run --no-restart apply
}
spotify_verify() {
    local xdir="$SPOTIFY_DIR/Apps/xpui" routes=0 top=0 side=0
    if [[ ! -d "$xdir" ]]; then
        err "Spicetify output is missing: $xdir"
        return 1
    fi
    grep -rqs 'spicetify-routes-marketplace' "$xdir" && routes=1
    # the nav link is written as _renderNavLinks(["marketplace",], true) for the top bar
    # (next to Search) and as ..., false for the "Your Library" sidebar
    grep -rqsF '"marketplace",], true)' "$xdir" && top=1
    grep -rqsF '"marketplace",], false)' "$xdir" && side=1
    if (( routes )); then
        ok "Marketplace is registered in the Spotify UI bundle"
    else
        warn "Marketplace is NOT registered: Spicetify could not patch this Spotify build"
    fi
    if (( top )); then
        ok "Marketplace nav link: top bar, next to Search (hover the new icon to check)"
    fi
    if (( side )); then
        ok "Marketplace nav link: 'Your Library' sidebar"
    fi
    if (( ! top && ! side )); then
        warn "Marketplace nav link was not injected (the route may still be reachable)"
    fi
    (( routes ))
}
spotify_newer_than_spicetify_support() {
    python3 -c 'import re, sys
v = re.sub(r"^\d+:", "", sys.argv[1])
m = re.match(r"(\d+)\.(\d+)\.(\d+)", v)
mx = tuple(int(x) for x in sys.argv[2].split("."))
sys.exit(0 if m and tuple(int(x) for x in m.groups()) > mx else 1)' "$1" "$SPICETIFY_LINUX_MAX_SPOTIFY"
}
install_spotify_hook() {
    write_root_file /usr/local/bin/spotify-spicetify-writable <<'EOF'
#!/bin/sh
# Runs after each install or upgrade of the spotify package.
# Spicetify and SpotX write into /opt/spotify. A Spicetify folder left from the old version would
# make the upgraded Spotify load an old, patched UI, so it is removed here.
[ -d /opt/spotify ] || exit 0
chmod a+wr /opt/spotify
[ -d /opt/spotify/Apps ] && chmod -R a+wr /opt/spotify/Apps
rm -rf /opt/spotify/Apps/xpui
exit 0
EOF
    as_root chmod 755 /usr/local/bin/spotify-spicetify-writable
    write_root_file /etc/pacman.d/hooks/spotify-spicetify.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = spotify

[Action]
Description = Making Spotify writable for Spicetify...
When = PostTransaction
Exec = /usr/local/bin/spotify-spicetify-writable
EOF
}
retire_spotify_launcher() {
    if pkg_installed spotify-launcher; then
        info "Removing spotify-launcher (the regular Spotify package replaces it)"
        if as_root pacman -Rns --noconfirm spotify-launcher >>"$SPOTIFY_CLIENT_LOG" 2>&1; then
            ok "spotify-launcher removed"
        else
            warn "spotify-launcher could not be removed (see $SPOTIFY_CLIENT_LOG)"
        fi
    fi
    rm -f "$HOME/.local/share/applications/spotify-launcher.desktop"
    if [[ -d "$HOME/.local/share/spotify-launcher" ]]; then
        rm -rf "$HOME/.local/share/spotify-launcher"
        note "removed the launcher's downloaded copy of Spotify"
    fi
}
spotify_launcher_version() {
    [[ -f "$SPOTIFY_STATE" ]] || return 0
    python3 -c 'import json, sys
try:
    print(json.load(open(sys.argv[1])).get("version", ""))
except Exception:
    pass' "$SPOTIFY_STATE" 2>/dev/null
}
spotify_update_due() {
    python3 - "$SPOTIFY_STATE" <<'PY'
import json, sys, time
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        last = json.load(fh).get("last_update_check", 0)
    if isinstance(last, dict):                       # serde SystemTime form
        last = last.get("secs_since_epoch", 0)
    sys.exit(0 if time.time() - float(last) >= 86400 else 1)
except Exception:                                    # no usable state: let the launcher decide
    sys.exit(0)
PY
}
spotify_update_check() {    # optional: --check-update forces a version check now
    if [[ "${1:-}" != --check-update ]] && ! spotify_update_due; then
        return 0
    fi
    if ! reachable "https://repository.spotify.com/"; then
        warn "repository.spotify.com is unreachable — skipping the client update check (try --proxy)"
        return 0
    fi
    info "Checking the Spotify client version (spotify-launcher)"
    spotify_launcher_run "$@" || warn "Client update check failed; the installed client is kept"
}
spotify_launcher_run() {    # extra launcher flags, e.g. --check-update / --force-update
    local attempt before=0 err=""
    for attempt in 1 2 3; do
        [[ -f "$SPOTIFY_CLIENT_LOG" ]] && before=$(wc -l < "$SPOTIFY_CLIENT_LOG")
        if timeout 1500 spotify-launcher "$@" --no-exec >>"$SPOTIFY_CLIENT_LOG" 2>&1; then
            # the launcher reports update errors itself and still exits 0, so check the lines it wrote now
            err=$(tail -n +"$((before + 1))" "$SPOTIFY_CLIENT_LOG" | grep -E 'ERROR|Update failed' | tail -n 1) || true
            if [[ -z "$err" ]]; then
                return 0
            fi
            warn "spotify-launcher reported an error (attempt $attempt/3): $err"
        else
            warn "spotify-launcher failed (attempt $attempt/3) — see $SPOTIFY_CLIENT_LOG"
        fi
        sleep $((attempt * 5))
    done
    return 1
}
spotify_reinstall_client() {
    # The current client stays in place until a complete new copy has been downloaded.
    # Only then is it swapped in: a failed download must never leave the user without a client.
    local staging="$SPOTIFY_HOME/install-setup" state_bak="$SPOTIFY_HOME/state.before-reinstall"
    info "Downloading a clean Spotify client (the current files stay in place until the new copy is complete)"
    spotify_stop
    rm -rf "$staging"
    rm -f "$state_bak"
    [[ -f "$SPOTIFY_STATE" ]] && cp -f "$SPOTIFY_STATE" "$state_bak"
    if ! spotify_launcher_run --force-update --install-dir "$staging" \
            || [[ ! -f "$staging/usr/share/spotify/Apps/xpui.spa" ]]; then
        warn "The new client was not downloaded completely; the previous files are kept"
        rm -rf "$staging"
        [[ -f "$state_bak" ]] && mv -f "$state_bak" "$SPOTIFY_STATE"
        rm -f "$state_bak"
        return 1
    fi
    rm -rf "$SPOTIFY_INSTALL"
    mv "$staging" "$SPOTIFY_INSTALL"
    rm -f "$state_bak"
    clear_marks
    spotify_client_is_stock
}

# the client folder and the binary in it, for the chosen source
spotify_setup_paths() {
    if [[ $SPOTIFY_SOURCE == aur ]]; then
        SPOTIFY_DIR="${SPOTIFY_ROOT:-/opt/spotify}"
    else
        SPOTIFY_DIR="${SPOTIFY_ROOT:-$SPOTIFY_INSTALL/usr/share/spotify}"
    fi
    SPOTIFY_BIN="$SPOTIFY_DIR/spotify"
}

# installed client version: launcher state or pacman; empty when the client is missing
# true when the client files are on disk (stock: Apps/xpui.spa; after Spicetify: Apps/xpui/)
spotify_client_on_disk() {
    [[ -f "$SPOTIFY_DIR/Apps/xpui.spa" || -d "$SPOTIFY_DIR/Apps/xpui" ]]
}
spotify_installed_version() {
    if [[ $SPOTIFY_SOURCE == aur ]]; then
        pacman -Q spotify 2>/dev/null | awk '{print $2}'
    else
        spotify_launcher_version
    fi
}

# ---- the pipeline: client -> SpotX (only with --spotx) -> warm-up -> Marketplace/theme -> backup -> apply
# true when prefs already records this client version (numbers only: 1.2.96.518 matches 1.2.96.518.g366879e1)
spotify_prefs_current() {    # $1 = client version, e.g. 1:1.2.96.518.g366879e1
    local want got
    want=$(printf '%s' "$1" | sed -E 's/^[0-9]+://' | sed -nE 's/^([0-9]+(\.[0-9]+)*).*/\1/p' | head -1)
    got=$(spotify_prefs_version | sed -nE 's/^([0-9]+(\.[0-9]+)*).*/\1/p' | head -1)
    [[ -n "$want" && "$want" == "$got" ]]
}

# adds NAME to a pipe-separated Spicetify list (extensions) without removing the others
register_spicetify_list() {    # $1 = config key, $2 = name
    local key=$1 name=$2 cfg="$SPICETIFY_CFG/config-xpui.ini" cur="" item new=""
    local -a items=()
    if [[ -f "$cfg" ]]; then
        cur=$(tr -d '\r' <"$cfg" | sed -nE "s/^${key}[[:space:]]*=[[:space:]]*(.*)\$/\1/p" | head -1)
    fi
    IFS='|' read -r -a items <<<"$cur"
    for item in "${items[@]}"; do
        item=${item//[[:space:]]/}
        [[ -z "$item" || "$item" == "$name" ]] && continue
        new+="$item|"
    done
    new+="$name"
    spicetify_run config "$key" "$new"
}

# Adblockify (rxri/spicetify-extensions): blocks ads between songs and in the UI, without patching the client
adblock_install() {
    local dst="$SPICETIFY_CFG/Extensions/adblock.js" tmp
    ensure_workdir
    tmp="$WORKDIR/adblock.js"
    mkdir -p "$SPICETIFY_CFG/Extensions"
    retry 3 curl -fsSL --connect-timeout 15 --max-time 120 -o "$tmp" "$ADBLOCK_URL" \
        || { err "Cannot download Adblockify from $ADBLOCK_URL"; return 1; }
    if [[ ! -s "$tmp" ]] || ! grep -q "Spicetify" "$tmp"; then
        err "The downloaded Adblockify file does not look like a Spicetify extension"
        return 1
    fi
    cp -f "$tmp" "$dst"
    register_spicetify_list extensions adblock.js || return 1
    ok "Adblockify installed: $dst"
}

# The menu starts Spotify directly. With the launcher, its own update check is skipped: an automatic
# update would replace the patched files, and Spicetify would be gone until this script runs again.
spotify_install_menu_entry() {
    local apps="$HOME/.local/share/applications" desk sys
    mkdir -p "$apps"
    if [[ $SPOTIFY_SOURCE == aur ]]; then
        # the regular package brings its own menu entry, so no override is needed
        rm -f "$apps/spotify.desktop" "$apps/spotify-launcher.desktop"
    else
        desk="$apps/spotify-launcher.desktop"
        sys=/usr/share/applications/spotify-launcher.desktop
        rm -f "$apps/spotify.desktop"
        if [[ -f "$sys" ]]; then
            sed -E 's|^Exec=.*|Exec=spotify-launcher --skip-update %U|' "$sys" | write_file "$desk"
        else
            write_file "$desk" <<'EOF'
[Desktop Entry]
Type=Application
Name=Spotify
Comment=Spotify with Spicetify and Marketplace
Exec=spotify-launcher --skip-update %U
Icon=spotify-client
Terminal=false
Categories=Audio;Music;Player;AudioVideo;
MimeType=x-scheme-handler/spotify;
StartupWMClass=spotify
EOF
        fi
    fi
    have update-desktop-database && update-desktop-database "$apps" >/dev/null 2>&1 || true
}

# Earlier versions created helper commands that patched Spotify on every start. Remove them.
remove_old_spotify_helpers() {
    local f removed=0
    for f in "$HOME/.local/bin/spotify-start" "$HOME/.local/bin/spotify-patch" "$SPOTIFY_CONF"; do
        if [[ -e "$f" ]]; then
            rm -f "$f"
            removed=1
        fi
    done
    if [[ -d "$HOME/.local/share/cachyos-setup" ]]; then
        rm -rf "$HOME/.local/share/cachyos-setup"
        removed=1
    fi
    if (( removed )); then
        note "removed the old per-start helpers (spotify-start, spotify-patch)"
    fi
    return 0
}

# Checks that Spicetify really put Adblockify into the Spotify client after apply
adblock_verify() {
    local xdir="$SPOTIFY_DIR/Apps/xpui"
    if [[ ! -f "$xdir/extensions/adblock.js" ]]; then
        warn "Adblockify is not in the Spotify client after apply (see $SPOTIFY_CLIENT_LOG)"
    elif grep -rqsF 'extensions/adblock.js' "$xdir"; then
        ok "Adblockify is in the Spotify client and loaded by its page"
    else
        warn "Adblockify file is in the client, but the page does not load it (see $SPOTIFY_CLIENT_LOG)"
    fi
}

spotify_pipeline() {    # $1 = installed client version
    local version=$1 need_backup=0 backed=0
    if spotify_newer_than_spicetify_support "$version"; then
        warn "Spotify $version is newer than $SPICETIFY_LINUX_MAX_SPOTIFY, the last Spotify-for-Linux version listed by Spicetify 2.45.3."
        warn "Spotify patching skipped: Spicetify does not support this client yet, so Spotify is left as it is."
        note "options: --spotify-aur (the AUR package; the build I could see was 1.2.92), or run the setup again once Spicetify lists $version"
        return 2
    fi
    if [[ $SPOTIFY_SOURCE == aur ]]; then
        spotify_prepare_permissions || { err "Cannot make $SPOTIFY_DIR writable for Spicetify (sudo needed)"; return 1; }
    fi

    if (( SPOTX )) && [[ "$(read_mark spotx)" != "$version" ]]; then
        need_backup=1
        if ! spotify_client_is_stock; then
            if [[ $SPOTIFY_SOURCE == aur ]]; then
                warn "The Spotify folder was changed earlier (Spicetify or SpotX); restoring the stock file"
                spotify_restore_stock "$version" \
                    || { err "No stock copy for $version. Reinstall the package (paru -S spotify) and run this again"; return 1; }
            else
                warn "The client folder was changed earlier (Spicetify or SpotX); installing a clean copy"
                spotify_reinstall_client || { err "Could not re-download the Spotify client"; return 1; }
                version=$(spotify_installed_version)
                [[ -n "$version" ]] || { err "Client version unknown after reinstall"; return 1; }
            fi
        fi
        spotify_save_stock "$version"
        spotx_patch || { err "SpotX failed. See $SPOTIFY_CLIENT_LOG"; return 1; }
        write_mark spotx "$version"
        ok "SpotX applied for $version"
    fi
    [[ "$(read_mark spicetify)" == "$version" ]] || need_backup=1

    spicetify_cli_ensure || return 1
    if (( need_backup )); then
        if spotify_prefs_current "$version"; then
            note "Spotify already records this version; it does not need to be started again"
        else
            spotify_warmup || return 1
        fi
    fi
    spicetify_configure || return 1
    marketplace_install || warn "Marketplace could not be installed (run the setup script again to retry)"
    theme_setup
    if (( ADBLOCK_ON )); then
        adblock_install || warn "Adblockify could not be installed (you can still add it from Marketplace > Extensions)"
    fi
    if (( need_backup )); then
        spicetify_backup || { err "spicetify backup failed. See $SPOTIFY_CLIENT_LOG"; return 1; }
        backed=1
    fi
    if ! spicetify_apply; then
        if (( backed )); then
            err "spicetify apply failed. See $SPOTIFY_CLIENT_LOG"
            return 1
        fi
        warn "apply rejected the existing backup; rebuilding it once"
        spotify_warmup || return 1
        spicetify_backup || { err "spicetify backup failed. See $SPOTIFY_CLIENT_LOG"; return 1; }
        spicetify_apply || { err "spicetify apply failed again. See $SPOTIFY_CLIENT_LOG"; return 1; }
    fi
    spotify_verify || warn "Marketplace injection could not be confirmed (send $SPOTIFY_CLIENT_LOG if it is still missing)"
    if (( ADBLOCK_ON )); then adblock_verify; fi
    write_mark spicetify "$version"
    if (( SPOTX )); then
        ok "Spotify $version is patched (SpotX + Spicetify)"
    else
        ok "Spotify $version is patched (Spicetify, no SpotX)"
    fi
}

# ---- setup step -------------------------------------------------------------------------------
step_spotify() {
    local ad="off"
    (( SPOTX )) && ad="on"
    step "Spotify: client ($SPOTIFY_SOURCE), SpotX ad-block $ad, Spicetify (Marketplace)"
    ensure_workdir
    remove_old_spotify_helpers
    spotify_setup_paths
    local version=""
    if [[ $SPOTIFY_SOURCE == aur ]]; then
        version=$(spotify_installed_version)
        if [[ -n "$version" ]]; then
            ok "Spotify package already installed ($version)"
            RES_SKIP+=("Spotify package  (already installed: $version)")
        else
            info "Installing Spotify from the AUR with paru (it can take a while)"
            if ! aur_install spotify; then
                err "Spotify could not be installed from the AUR (see the paru output above)"
                if pkg_installed spotify-launcher; then
                    rm -f "$HOME/.local/share/applications/spotify-launcher.desktop"
                    warn "spotify-launcher is kept for now, so the menu starts Spotify again"
                fi
                RES_FAIL+=("Spotify package")
                return 0
            fi
            version=$(spotify_installed_version)
        fi
        if [[ -z "$version" || ! -x "$SPOTIFY_BIN" ]]; then
            err "Spotify is not installed in $SPOTIFY_DIR"
            RES_FAIL+=("Spotify package")
            return 0
        fi
        spotify_install_menu_entry
        install_spotify_hook
        retire_spotify_launcher
    else
        if ! pac_install_list "Spotify launcher" spotify-launcher; then
            RES_FAIL+=("Spotify launcher")
            return 0
        fi
        spotify_install_menu_entry
        if ! spotify_client_on_disk && [[ -n "$(spotify_installed_version)" ]]; then
            # the launcher's state file still records a version, but the files are gone
            # (an earlier download was interrupted or the folder was removed)
            warn "The launcher's record says Spotify is installed, but its files are missing. Downloading the client again."
            spotify_reinstall_client || true
        elif [[ -z "$(spotify_installed_version)" ]] || (( UPDATE_SPOTIFY )); then
            spotify_update_check --check-update
        else
            note "keeping the installed Spotify client (add --update-spotify to update it)"
        fi
        version=$(spotify_installed_version)
        if [[ -z "$version" ]] || ! spotify_client_on_disk; then
            err "The Spotify client was not downloaded. Check the network or use --proxy, then run the script again."
            RES_FAIL+=("Spotify client download")
            return 0
        fi
    fi

    local extra=""
    (( SPOTX )) && extra=" + SpotX ad-block"
    (( ADBLOCK_ON )) && extra="$extra + Adblockify"
    spotify_pipeline "$version"
    case $? in
        0) RES_OK+=("Spotify $version ($SPOTIFY_SOURCE client$extra + Spicetify with Marketplace)") ;;
        2) ;;    # skipped on purpose; the warnings above say why
        *) RES_FAIL+=("Spotify patching (see $SPOTIFY_CLIENT_LOG)") ;;
    esac
    SPOTIFY_NOTE="Open Spotify from the app menu as usual; it starts without patching or update checks. Ads: SpotX and Adblockify are on by default (--no-spotx / --no-adblock turn them off). Choose your theme in Spotify's Marketplace (top bar next to Search, or the Your Library sidebar). After a Spotify update, run ./setup-cachyos-full.sh again to re-apply Spicetify. If Marketplace is missing, try --no-spotx, then send ~/.local/state/cachyos-setup/spotify-client.log."
}

# ============================================================================
#  STEP: application configuration
# ============================================================================
config_aria2() {
    local dl="$HOME/Downloads" conf="$HOME/.config/aria2/aria2.conf"
    local session="$HOME/.cache/aria2/aria2.session" alloc="falloc" fs
    mkdir -p "$dl" "$HOME/.cache/aria2"
    touch "$session"
    fs="$(stat -f -c %T "$dl" 2>/dev/null || echo unknown)"
    [[ "$fs" == "btrfs" ]] && alloc="none"   # falloc fragments btrfs (copy-on-write)

    write_file "$conf" <<EOF
# ============================================================================
# aria2 — tuned for speed and resume   (generated by setup-cachyos-full.sh)
# ============================================================================

# --- where to save --------------------------------------------------------
dir=$dl
file-allocation=$alloc
disk-cache=64M

# --- speed ------------------------------------------------------------------
# up to 16 connections to the same server, file split in 16 parts
max-connection-per-server=16
split=16
min-split-size=1M
max-concurrent-downloads=5
optimize-concurrent-downloads=true
# with several mirrors for one file, prefer the fastest
uri-selector=adaptive
max-overall-download-limit=0
max-download-limit=0
lowest-speed-limit=0
http-accept-gzip=true

# --- resume & reliability ---------------------------------------------------
# continue a partially downloaded file (works together with the .aria2 control file)
continue=true
always-resume=true
max-resume-failure-tries=0
# retry forever, wait 5 s between tries
max-tries=0
retry-wait=5
timeout=60
connect-timeout=30
auto-file-renaming=true
allow-overwrite=false
remote-time=true

# --- session: unfinished downloads are remembered across Ctrl+C / reboot -----
# NOTE: do not set 'input-file' here — aria2 then ignores URLs given on the
# command line. Resume everything unfinished with:   aria2-resume
save-session=$session
save-session-interval=30

# --- output ---------------------------------------------------------------
log-level=warn
console-log-level=notice
summary-interval=0
human-readable=true
download-result=full
user-agent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36

# --- BitTorrent / magnet ----------------------------------------------------
enable-dht=true
enable-dht6=true
bt-enable-lpd=true
enable-peer-exchange=true
bt-max-peers=0
bt-request-peer-speed-limit=10M
bt-save-metadata=true
bt-load-saved-metadata=true
follow-torrent=true
seed-ratio=1.0
listen-port=6881-6999
dht-listen-port=6881-6999
EOF
    if aria2c --conf-path="$conf" --version >/dev/null 2>&1; then
        ok "aria2 config accepted (file-allocation=$alloc on $fs)"
    else
        warn "aria2c rejected the generated config — check $conf"
    fi
    # helper: resume every unfinished download recorded in the session file
    mkdir -p "$HOME/.local/bin"
    write_file "$HOME/.local/bin/aria2-resume" <<EOF
#!/usr/bin/env bash
# Resume all unfinished aria2 downloads recorded in the session file.
exec aria2c --input-file="$session" --save-session="$session" "\$@"
EOF
    chmod 755 "$HOME/.local/bin/aria2-resume"
    note "usage:  aria2c URL     (16 connections; run the same command again to resume)"
    note "        aria2-resume   (resume everything unfinished, even after a reboot)"
}

config_mpv() {
    local conf="$HOME/.config/mpv/mpv.conf"
    if [[ -f "$conf" ]]; then
        note "keeping existing $conf"
        return 0
    fi
    write_file "$conf" <<'EOF'
# mpv — sensible defaults for Wayland / Hyprland
vo=gpu-next
hwdec=auto-safe

# playback
save-position-on-quit=yes
keep-open=yes

# subtitles — Persian friendly
sub-auto=fuzzy
sub-font="Vazirmatn"
sub-codepage=utf8:cp1256
EOF
}

config_pacseek() {
    have pacseek || return 0
    local conf="$HOME/.config/pacseek/config.json"
    if [[ ! -f "$conf" ]] && have script; then
        note "starting pacseek once so it creates its config"
        timeout 12 script -qec pacseek /dev/null < <(sleep 3; printf '\021') >/dev/null 2>&1 || true
    fi
    if [[ -f "$conf" ]]; then
        backup_file "$conf"
        local n
        n="$(python3 "$WORKDIR/pacseek_cfg.py" "$conf" 2>/dev/null | tail -1)"
        if [[ "${n:-0}" -gt 0 ]]; then
            ok "pacseek now installs AUR packages with paru ($n setting(s) changed from yay)"
        else
            note "pacseek config already uses paru (or has no yay entries)"
        fi
    else
        warn "pacseek config not created yet. On first launch open Settings and change 'yay' to 'paru'."
    fi
}

config_bandwhich() {
    have bandwhich || return 0
    local bin
    bin="$(command -v bandwhich)"
    if as_root setcap cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep "$bin"; then
        ok "bandwhich can run without sudo (capabilities set on $bin)"
    else
        warn "could not set capabilities — run it with: sudo bandwhich"
        return 0
    fi
    write_root_file /etc/pacman.d/hooks/bandwhich-caps.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = bandwhich

[Action]
Description = Re-applying capabilities to bandwhich...
When = PostTransaction
Exec = /usr/bin/setcap cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep /usr/bin/bandwhich
EOF
}

config_localsend() {
    pkg_installed localsend-bin || pkg_installed localsend || have localsend_app || return 0
    # LocalSend discovers devices on TCP+UDP 53317
    if have ufw && as_root ufw status 2>/dev/null | grep 'Status: active' >/dev/null; then
        as_root ufw allow 53317/tcp >/dev/null && as_root ufw allow 53317/udp >/dev/null \
            && ok "ufw: opened port 53317 (LocalSend)"
    elif have firewall-cmd && as_root firewall-cmd --state &>/dev/null; then
        as_root firewall-cmd --permanent --add-port=53317/tcp --add-port=53317/udp >/dev/null \
            && as_root firewall-cmd --reload >/dev/null \
            && ok "firewalld: opened port 53317 (LocalSend)"
    else
        note "no active firewall detected — LocalSend needs no changes"
    fi
}

config_path_env() {
    # ~/.local/bin (aria2-resume, uv tools ...) must be on PATH in the graphical session
    set_block "$HOME/.config/uwsm/env" "path" "#" <<'EOF'
# user-installed tools
for d in "$HOME/.local/bin" "$HOME/.spicetify"; do
    [ -d "$d" ] && case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
done
export PATH
EOF
    ok "UWSM environment: ~/.local/bin is on PATH"
}

config_fzf() {
    have fzf || return 0
    local sys_fish=/usr/share/cachyos-fish-config/cachyos-config.fish
    local sys_zsh=/usr/share/cachyos-zsh-config/cachyos-config.zsh
    local rc

    # bash
    rc="$HOME/.bashrc"
    if [[ -f "$rc" ]] && fzf --bash &>/dev/null; then
        if grep -q fzf "$rc" && ! grep -q 'setup-script:fzf' "$rc"; then
            note "bash: .bashrc already mentions fzf — left as is"
        else
            set_block "$rc" "fzf" "#" <<'EOF'
# fzf: Ctrl+T files, Ctrl+R history, Alt+C cd
command -v fzf >/dev/null 2>&1 && eval "$(fzf --bash)"
EOF
            ok "fzf key bindings enabled for bash"
        fi
    fi

    # zsh
    rc="$HOME/.zshrc"
    if have zsh && [[ -f "$rc" ]] && fzf --zsh &>/dev/null; then
        if { grep -q fzf "$rc" && ! grep -q 'setup-script:fzf' "$rc"; } || grep -qs fzf "$sys_zsh"; then
            note "zsh: fzf already configured — left as is"
        else
            set_block "$rc" "fzf" "#" <<'EOF'
# fzf: Ctrl+T files, Ctrl+R history, Alt+C cd
command -v fzf >/dev/null 2>&1 && source <(fzf --zsh)
EOF
            ok "fzf key bindings enabled for zsh"
        fi
    fi

    # fish
    rc="$HOME/.config/fish/config.fish"
    if have fish && fzf --fish &>/dev/null; then
        if { [[ -f "$rc" ]] && grep -q fzf "$rc" && ! grep -q 'setup-script:fzf' "$rc"; } || grep -qs fzf "$sys_fish"; then
            note "fish: fzf already configured — left as is"
        else
            set_block "$rc" "fzf" "#" <<'EOF'
# fzf: Ctrl+T files, Ctrl+R history, Alt+C cd
if status is-interactive; and type -q fzf
    fzf --fish | source
end
EOF
            ok "fzf key bindings enabled for fish"
        fi
    fi
    RES_OK+=("fzf shell integration")
}

config_uv() {
    have uv || return 0
    ok "uv ready: $(uv --version 2>/dev/null)"
    note "usage: uv init proj && cd proj && uv add requests && uv run main.py   |   uv tool install ruff"
}

step_app_config() {
    step "Application configuration (aria2, mpv, shell tools, pacseek, bandwhich, LocalSend ...)"
    mkdir -p "$HOME/Music" "$HOME/.local/bin"
    config_path_env
    have aria2c && config_aria2
    have mpv && config_mpv
    config_fzf
    config_uv
    config_pacseek
    config_bandwhich
    config_localsend
    if pkg_installed v2rayn-bin || pkg_installed v2rayn; then
        mkdir -p "$HOME/.local/share/v2rayN/bin"
        ok "v2rayN data directory created"
    fi
}

# ============================================================================
#  FINAL
# ============================================================================
restart_noctalia() {
    hypr_running || return 0
    pgrep -x noctalia >/dev/null 2>&1 || return 0
    info "Restarting Noctalia so the new settings are loaded"
    pkill -x noctalia 2>/dev/null
    sleep 1
    if have uwsm; then
        nohup uwsm app -- noctalia >/dev/null 2>&1 &
    else
        nohup noctalia >/dev/null 2>&1 &
    fi
    disown 2>/dev/null || true
    ok "Noctalia restarted"
}

print_list() {   # print_list "title" color array...
    local title=$1 color=$2 item
    shift 2
    (($#)) || return 0
    printf '\n%s%s%s\n' "$color" "$title" "$C_RESET"
    for item in "$@"; do printf '   • %s\n' "$item"; done
}

step_final() {
    step "Summary"
    step_end
    restart_noctalia

    printf '\n%s╔══════════════════════════════════════════════════════════════╗\n' "$C_BOLD"
    printf   '║                        SETUP FINISHED                        ║\n'
    printf   '╚══════════════════════════════════════════════════════════════╝%s\n' "$C_RESET"
    printf 'Total time: %dm %ds\n' $(((SECONDS - START_SECONDS) / 60)) $(((SECONDS - START_SECONDS) % 60))

    print_list "Installed / configured now" "$C_GREEN"  "${RES_OK[@]}"
    print_list "Already present"            "$C_CYAN"   "${RES_SKIP[@]}"
    print_list "FAILED — run the script again to retry" "$C_RED" "${RES_FAIL[@]}"
    print_list "Warnings"                   "$C_YELLOW" "${RES_WARN[@]}"

    cat <<EOF

${C_BOLD}Next steps${C_RESET}
  1. Log out and log in again (or reboot): new i2c group, locale, UWSM
     environment, fonts and Qt/GTK settings are only fully applied then.
  2. Test the Persian keyboard: Alt+Shift, then type  سلام دنیا
  3. Checks:   fc-match Vazirmatn     hyprctl getoption input:kb_layout
               ddcutil detect         systemctl --user status mpd
  4. Download with aria2:   aria2c "URL"      (re-run it to resume)
EOF
    if [[ -n "$SPOTIFY_NOTE" ]]; then
        printf '  5. Spotify: %s\n' "$SPOTIFY_NOTE"
    fi
    cat <<EOF

Log file : $LOG_FILE
Backups  : $BACKUP_DIR
Spotify  : $SPOTIFY_CLIENT_LOG
EOF
    ((${#RES_FAIL[@]} == 0)) || return 1
}

# ============================================================================
#  MAIN
# ============================================================================
run_in_pty() {
    local raw="$LOG_FILE.raw" cmd rc inhibit=""
    # Keep the PC awake: a long install must not hit the idle timer (screen off / lock / suspend).
    if have systemd-inhibit; then
        inhibit="systemd-inhibit --what=idle:sleep --who=cachyos-setup --why='Installing packages' --mode=block "
    fi
    cmd="${inhibit}bash $(printf '%q ' "$0" "$@")"
    SETUP_IN_PTY=1 SETUP_STAMP="$STAMP" script -qefc "$cmd" "$raw"
    rc=$?
    # readable log: escape sequences removed, only the final state of progress lines kept
    python3 "$WORKDIR/clean_log.py" <"$raw" >"$LOG_FILE" 2>/dev/null || true
    rm -f "$raw"
    return $rc
}

main() {
    parse_args "$@"

    mkdir -p "$LOG_DIR"
    # Progress bars and download speeds (pacman, paru, curl, git) are only
    # printed when stdout is a real terminal. The whole run happens inside a
    # pseudo-terminal (`script`) that also records the log.
    if [[ -z "${SETUP_IN_PTY:-}" ]]; then
        if [[ -t 1 ]] && have script; then
            ensure_workdir
            trap cleanup EXIT
            write_python_tools
            run_in_pty "$@"
            return $?
        elif [[ -t 1 ]]; then
            echo "WARNING: 'script' (util-linux) not found — running without a log file." >&2
        else
            exec > >(tee >(sed -u 's/\x1b\[[0-9;]*[A-Za-z]//g' >> "$LOG_FILE")) 2>&1
        fi
    fi

    ensure_workdir
    mkdir -p "$BACKUP_DIR"
    trap cleanup EXIT
    trap on_interrupt INT TERM

    STEP_TOTAL=2                                    # base, helpers
    ((SKIP_UPDATE))  || STEP_TOTAL=$((STEP_TOTAL + 1))
    ((SKIP_SYSTEM))  || STEP_TOTAL=$((STEP_TOTAL + 7))   # locale, fonts, theming, Hyprland, storage, DDC, MPD
    ((SKIP_APPS))    || STEP_TOTAL=$((STEP_TOTAL + 2))   # apps + app config
    ((SKIP_SPOTIFY)) || STEP_TOTAL=$((STEP_TOTAL + 1))
    STEP_TOTAL=$((STEP_TOTAL + 1))                  # summary

    banner
    write_python_tools
    preflight

    ((SKIP_UPDATE)) || step_update
    if (( REBOOT_REQUIRED )); then
        reboot_required_notice
        return 0
    fi
    step_base
    step_helpers

    if ((! SKIP_SYSTEM)); then
        step_locale
        step_vazirmatn
        step_theming
        step_hyprland
        step_storage
        step_ddc
        step_mpd
    fi

    ((SKIP_APPS))    || step_apps
    ((SKIP_SPOTIFY)) || step_spotify
    ((SKIP_APPS))    || step_app_config

    step_final
    local rc=$?
    sleep 0.3
    return $rc
}

cleanup() {
    [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    [[ -n "$WORKDIR" && -d "$WORKDIR" ]] && rm -rf "$WORKDIR"
    WORKDIR=""
    return 0
}

on_interrupt() {
    echo
    err "Interrupted. Re-run the script any time — finished steps are skipped."
    exit 130
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
    exit $?
fi
