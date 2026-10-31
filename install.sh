#!/bin/bash
# SoloOS (was Solo Operator System) installer for the Mac, app first (0.11.0): installs the app and the styles pack, then
# opens SoloOS within a minute or two; the heavy editing tools (Python, WhisperX, the speech model, Claude Code) install
# inside the app's Setup screen with progress and Retry, from install-tools.sh (the one place the tool steps live).
# No password prompts. Re-running it updates / repairs; finished steps are skipped.
#
#   curl -fsSL https://raw.githubusercontent.com/amirionxai-glitch/soloos/main/install.sh | bash
#   SOS_WITH_TOOLS=1 …   also installs the tools here, in the terminal (no app needed)
#
# What goes where (nothing needs sudo; python/, models/, bin/ and Claude Code come from install-tools.sh):
#   ~/Library/Application Support/SOS/bin/       micromamba
#   ~/Library/Application Support/SOS/python/    Python 3.11 + ffmpeg/ffprobe + node + WhisperX + yt-dlp (conda-forge/pip)
#   ~/Library/Application Support/SOS/models/    WhisperX model cache (HF_HOME)
#   ~/Library/Application Support/SOS/sos/       the asset pack (SOS_HOME): styles, templates, music, sounds, the hub
#   /Applications (or ~/Applications)            SoloOS.app
#   ~/.local/bin/claude                          Claude Code, by Anthropic's own installer (skipped if present)
#   ~/Library/Fonts                              Instrument Serif (free, OFL)

main() {
  set -euo pipefail

  REPO="${SOS_REPO:-amirionxai-glitch/soloos}"
  DL="${SOS_DOWNLOAD:-https://github.com/$REPO/releases/latest/download}"
  SUPPORT="$HOME/Library/Application Support/SOS"
  SOS_HOME="$SUPPORT/sos"
  CACHE="$SUPPORT/downloads"
  APP_NAME="SoloOS"
  OLD_APP_NAME="Solo Operator System"           # the name before 0.4.0: replaced by SoloOS.app

  step() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
  ok() { printf '  ✓ %s\n' "$*"; }
  warn() { printf '  ! %s\n' "$*"; }
  die() { printf '\n✕ %s\n' "$*" >&2; exit 1; }

  # ---- 1. this Mac ----
  step "Checking this Mac"
  [ "$(uname -s)" = "Darwin" ] || die "This installer is for macOS. On Windows use install.ps1 (README.md)."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [ "$major" -ge 12 ] || die "macOS 12 or newer is needed (this Mac has $(sw_vers -productVersion))."
  case "$(uname -m)" in
    arm64) ARCH=arm64; MM_ARCH=osx-arm64 ;;
    x86_64) ARCH=x64; MM_ARCH=osx-64 ;;
    *) die "Unknown processor: $(uname -m)" ;;
  esac
  ok "macOS $(sw_vers -productVersion), $( [ $ARCH = arm64 ] && echo 'Apple Silicon' || echo 'Intel')"
  for name in "$APP_NAME" "$OLD_APP_NAME"; do
    [ -n "${SOS_FROM_APP:-}" ] && break   # the app's own Update button: it stages the new app and swaps it after quitting
    if [ "$(osascript -e "application \"$name\" is running" 2>/dev/null)" = "true" ]; then
      die "Quit $name first (⌘Q), then run this again."
    fi
  done
  mkdir -p "$CACHE"

  # ---- 2. the asset pack: styles, templates, music, sounds, the hub ----
  step "Styles and sounds"
  local manifest latest have
  manifest="$CACHE/sos-pack.json"
  curl -fsSL -o "$manifest" "$DL/sos-pack.json" || die "Couldn't reach the release ($DL). Check the internet connection and try again."
  latest="$(json "$manifest" version)"
  have="$(cat "$SOS_HOME/VERSION" 2>/dev/null || echo none)"
  if [ "$have" = "$latest" ]; then
    ok "up to date ($latest)"
  else
    install_pack "$manifest" "$latest"
    ok "installed $latest (was $have)"
  fi

  # ---- 3. fonts (free ones; SF Pro needs Apple's installer, listed at the end) ----
  step "Fonts"
  mkdir -p "$HOME/Library/Fonts"
  for f in InstrumentSerif-Regular.ttf InstrumentSerif-Italic.ttf; do
    if [ ! -f "$HOME/Library/Fonts/$f" ] && [ ! -f "/Library/Fonts/$f" ]; then
      curl -fsSL -o "$HOME/Library/Fonts/$f" "https://raw.githubusercontent.com/google/fonts/main/ofl/instrumentserif/$f"
    fi
  done
  ok "Instrument Serif"

  # ---- 4. the app ----
  step "The app"
  local dest="${SOS_APP_DEST:-/Applications}"
  [ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
  # from the app's Update button (SOS_APP_STAGE): the new copy goes beside it, the app swaps it in once it has quit
  local into="$dest"
  [ -n "${SOS_APP_STAGE:-}" ] && { into="$SOS_APP_STAGE"; mkdir -p "$into"; }
  local dmg="$CACHE/SOS-$ARCH.dmg" mnt
  local app_have app_latest
  app_latest="$(json "$manifest" app_version)"
  app_have="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$dest/$APP_NAME.app/Contents/Info.plist" 2>/dev/null || echo none)"
  if [ "$app_have" = "$app_latest" ]; then
    ok "up to date ($app_latest)"
  else
    curl -fL --retry 3 -C - -o "$dmg" "$DL/SOS-$ARCH.dmg" 2>/dev/null || curl -fL --retry 3 -o "$dmg" "$DL/SOS-$ARCH.dmg"
    mnt="$(mktemp -d /tmp/sos-dmg.XXXXXX)"
    hdiutil attach -nobrowse -quiet -mountpoint "$mnt" "$dmg"
    rm -rf "$into/$APP_NAME.app"
    ditto "$mnt/$APP_NAME.app" "$into/$APP_NAME.app"
    hdiutil detach -quiet "$mnt" || true
    rm -f "$dmg"
    # no Apple Developer ID (the user's call): clear every quarantine flag and sign ad hoc, so Gatekeeper never asks
    xattr -cr "$into/$APP_NAME.app" 2>/dev/null || true
    codesign --force --deep --sign - "$into/$APP_NAME.app" 2>/dev/null || true
    if [ "$into" = "$dest" ]; then ok "installed $app_latest in $dest"; else ok "downloaded $app_latest (SoloOS restarts into it)"; fi
  fi
  [ -d "$dest/$APP_NAME.app" ] && xattr -dr com.apple.quarantine "$dest/$APP_NAME.app" 2>/dev/null || true
  if [ -d "$dest/$OLD_APP_NAME.app" ]; then             # the renamed app: one copy in Applications, not two
    rm -rf "$dest/$OLD_APP_NAME.app"
    ok "removed the old $OLD_APP_NAME.app (it's SoloOS now)"
  fi

  # ---- 5. what the member still installs themselves ----
  step "Checking After Effects, Blender and fonts"
  local missing=0
  if ls -d /Applications/Adobe\ After\ Effects\ 20* >/dev/null 2>&1; then ok "After Effects"; else warn "After Effects: install it from Adobe Creative Cloud."; missing=1; fi
  if [ -x /Applications/Blender.app/Contents/MacOS/Blender ]; then ok "Blender"; else warn "Blender (Voltage Cut uses it): https://www.blender.org/download/"; missing=1; fi
  if compgen -G "$HOME/Library/Fonts/SF-Pro-Display-*" >/dev/null || compgen -G "/Library/Fonts/SF-Pro-Display-*" >/dev/null \
    || compgen -G "$HOME/Library/Fonts/SFPRODISPLAY*" >/dev/null || compgen -G "/Library/Fonts/SFPRODISPLAY*" >/dev/null; then
    ok "SF Pro Display"
  else
    warn "SF Pro (Apple's free font): https://developer.apple.com/fonts/ → SF Pro → open the .pkg."; missing=1
  fi

  # ---- 6. the editing tools: only when asked (SOS_WITH_TOOLS=1); otherwise the app's Setup screen installs them ----
  if [ -n "${SOS_WITH_TOOLS:-}" ]; then
    step "Editing tools"
    local tools="$CACHE/install-tools.sh"
    curl -fsSL -o "$tools" "$DL/install-tools.sh" || die "Couldn't download install-tools.sh from the release."
    bash "$tools" || warn "some tools didn't install: the app's Setup screen shows which, with Retry"
  fi

  [ -n "${SOS_FROM_APP:-}" ] && return 0   # the app's Update button: it restarts into the new version itself
  printf '\n\033[1m✓ SoloOS is installed.\033[0m\n'
  if [ -z "${SOS_NO_OPEN:-}" ] && open "$dest/$APP_NAME.app" 2>/dev/null; then
    echo "SoloOS is open. Finish setup inside the app (it installs the editing tools while you look around)."
  else
    echo "Open “${APP_NAME}”: it signs you in, then finishes setup by itself."
  fi
  [ "$missing" = 1 ] && echo "Install what's marked ! above when you can (the app's Setup button shows the same list)."
  return 0
}

# json <file> <key> → a top-level string value of the release manifest (plutil reads JSON on macOS 12+; no Python yet)
json() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

# Downloads the pack parts named in the manifest (resume-safe, checksummed), unpacks it beside the old one, carries
# the member's own files over (style logs, MISTAKES/WINS logs, presets, brand kit), then swaps it in.
install_pack() {
  local manifest="$1" version="$2"
  local parts="" i=0 name
  while name="$(json "$manifest" "parts.$i.name")" && [ -n "$name" ]; do
    parts+="$name $(json "$manifest" "parts.$i.sha256")"$'\n'
    i=$((i + 1))
  done
  [ -n "$parts" ] || die "The release list (sos-pack.json) couldn't be read. Run the installer again."
  while read -r name sum; do
    [ -n "$name" ] || continue
    if [ -f "$CACHE/$name" ] && [ "$(shasum -a 256 "$CACHE/$name" | cut -d' ' -f1)" = "$sum" ]; then continue; fi
    echo "  downloading $name…"
    curl -fL --retry 3 -C - -o "$CACHE/$name" "$DL/$name" || curl -fL --retry 3 -o "$CACHE/$name" "$DL/$name"
    [ "$(shasum -a 256 "$CACHE/$name" | cut -d' ' -f1)" = "$sum" ] || { rm -f "$CACHE/$name"; die "$name didn't download correctly. Run the installer again."; }
  done <<<"$parts"

  local new="$SUPPORT/sos.new"
  rm -rf "$new" && mkdir -p "$new"
  # shellcheck disable=SC2046
  (cd "$CACHE" && cat $(echo "$parts" | cut -d' ' -f1)) | tar -xzf - -C "$new"
  echo "$version" >"$new/VERSION"

  if [ -d "$SOS_HOME" ]; then
    (
      cd "$SOS_HOME"
      for f in MISTAKES-LOG.md WINS-LOG.md SOLO_OPERATOR/presets.json motion-library/editing-styles/*/LOG.md; do
        [ -f "$f" ] && [ -d "$new/$(dirname "$f")" ] && cp -p "$f" "$new/$f"
      done
      [ -d SOLO_OPERATOR/brand ] && rm -rf "$new/SOLO_OPERATOR/brand" && cp -Rp SOLO_OPERATOR/brand "$new/SOLO_OPERATOR/brand"
    )
    rm -rf "$SUPPORT/sos.old" && mv "$SOS_HOME" "$SUPPORT/sos.old"
  fi
  mv "$new" "$SOS_HOME"
  rm -rf "$SUPPORT/sos.old"
  (cd "$CACHE" && rm -f $(echo "$parts" | cut -d' ' -f1))
}

main "$@"
