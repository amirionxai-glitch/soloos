#!/bin/bash
# SoloOS (was Solo Operator System) installer: installs and updates everything SOS needs on a Mac, with no password prompts, so a
# member's own Claude Code can run it (README.md). Re-running it updates / repairs; finished steps are skipped.
#
#   curl -fsSL https://raw.githubusercontent.com/amirionxai-glitch/soloos/main/install.sh | bash
#
# What goes where (nothing needs sudo):
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
  BIN="$SUPPORT/bin"
  PY_ENV="$SUPPORT/python"
  SOS_HOME="$SUPPORT/sos"
  CACHE="$SUPPORT/downloads"
  APP_NAME="SoloOS"
  OLD_APP_NAME="Solo Operator System"           # the name before 0.4.0: replaced by SoloOS.app
  export MAMBA_ROOT_PREFIX="$SUPPORT/mamba"
  export HF_HOME="$SUPPORT/models"

  step() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
  ok() { printf '  ✓ %s\n' "$*"; }
  warn() { printf '  ! %s\n' "$*"; }
  die() { printf '\n✕ %s\n' "$*" >&2; exit 1; }

  # ---- 1. this Mac ----
  step "Checking this Mac"
  [ "$(uname -s)" = "Darwin" ] || die "SoloOS runs on macOS only."
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
  mkdir -p "$BIN" "$CACHE" "$HF_HOME"

  # ---- 2. tools: Python, ffmpeg, node, WhisperX, yt-dlp (no Homebrew, no password) ----
  step "Installing the editing tools"
  if [ ! -x "$BIN/micromamba" ]; then
    curl -fsSL -o "$BIN/micromamba.tmp" "https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-$MM_ARCH"
    chmod +x "$BIN/micromamba.tmp" && mv "$BIN/micromamba.tmp" "$BIN/micromamba"
  fi
  ok "micromamba $("$BIN/micromamba" --version)"
  if [ ! -x "$PY_ENV/bin/python" ] || [ ! -x "$PY_ENV/bin/ffprobe" ] || [ ! -x "$PY_ENV/bin/node" ]; then
    if [ "$ARCH" = x64 ]; then
      # PyPI has no macOS-Intel torch wheels for current WhisperX: take torch from conda-forge instead
      "$BIN/micromamba" create -y -q -p "$PY_ENV" -c conda-forge python=3.11 ffmpeg nodejs pytorch torchaudio
    else
      "$BIN/micromamba" create -y -q -p "$PY_ENV" -c conda-forge python=3.11 ffmpeg nodejs
    fi
  fi
  "$BIN/micromamba" clean -a -y -q >/dev/null 2>&1 || true   # drop the package downloads (~0.8 GB)
  ok "Python $("$PY_ENV/bin/python" -V 2>&1 | cut -d' ' -f2), $("$PY_ENV/bin/ffmpeg" -version | head -1 | cut -d' ' -f1-3), node $("$PY_ENV/bin/node" -v)"
  # only what's missing: one absent tool used to reinstall everything (6+ min on an update, 2026-10-24)
  if ! "$PY_ENV/bin/python" -c "import whisperx, cv2, scipy, PIL, numpy" >/dev/null 2>&1; then
    "$PY_ENV/bin/python" -m pip install -q --upgrade pip
    "$PY_ENV/bin/python" -m pip install -q whisperx numpy scipy pillow opencv-python-headless yt-dlp
  elif [ ! -x "$PY_ENV/bin/yt-dlp" ]; then
    "$PY_ENV/bin/python" -m pip install -q yt-dlp
  fi
  ok "WhisperX, OpenCV, yt-dlp"
  # the speech model the edits use (pipeline/reel.py: medium.en); resumes if interrupted
  if ! "$PY_ENV/bin/python" -c "from faster_whisper import download_model as d; d('medium.en', local_files_only=True)" >/dev/null 2>&1; then
    echo "  downloading the speech model (about 1.5 GB, once)…"
    "$PY_ENV/bin/python" -c "from faster_whisper import download_model as d; d('medium.en')" >/dev/null
  fi
  # WhisperX's word-alignment model (torchaudio, ~360 MB), otherwise fetched in the middle of the first edit
  "$PY_ENV/bin/python" -c "import torchaudio; torchaudio.pipelines.WAV2VEC2_ASR_BASE_960H.get_model()" >/dev/null 2>&1 \
    || warn "the alignment model will download during the first edit"
  ok "speech model"

  # ---- 3. Claude Code (Anthropic's own installer; never modified) ----
  step "Claude Code"
  if command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ]; then
    ok "already installed"
  else
    curl -fsSL https://claude.ai/install.sh | bash
    ok "installed"
  fi

  # ---- 4. the asset pack: styles, templates, music, sounds, the hub ----
  step "Styles and sounds"
  local manifest latest have
  manifest="$CACHE/sos-pack.json"
  curl -fsSL -o "$manifest" "$DL/sos-pack.json" || die "Couldn't reach the release ($DL). Check the internet connection and try again."
  latest="$("$PY_ENV/bin/python" -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$manifest")"
  have="$(cat "$SOS_HOME/VERSION" 2>/dev/null || echo none)"
  if [ "$have" = "$latest" ]; then
    ok "up to date ($latest)"
  else
    install_pack "$manifest" "$latest"
    ok "installed $latest (was $have)"
  fi

  # ---- 5. fonts (free ones; SF Pro needs Apple's installer, listed at the end) ----
  step "Fonts"
  mkdir -p "$HOME/Library/Fonts"
  for f in InstrumentSerif-Regular.ttf InstrumentSerif-Italic.ttf; do
    if [ ! -f "$HOME/Library/Fonts/$f" ] && [ ! -f "/Library/Fonts/$f" ]; then
      curl -fsSL -o "$HOME/Library/Fonts/$f" "https://raw.githubusercontent.com/google/fonts/main/ofl/instrumentserif/$f"
    fi
  done
  ok "Instrument Serif"

  # ---- 6. the app ----
  step "The app"
  local dest="${SOS_APP_DEST:-/Applications}"
  [ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
  # from the app's Update button (SOS_APP_STAGE): the new copy goes beside it, the app swaps it in once it has quit
  local into="$dest"
  [ -n "${SOS_APP_STAGE:-}" ] && { into="$SOS_APP_STAGE"; mkdir -p "$into"; }
  local dmg="$CACHE/SOS-$ARCH.dmg" mnt
  local app_have app_latest
  app_latest="$("$PY_ENV/bin/python" -c "import json,sys; print(json.load(open(sys.argv[1]))['app_version'])" "$manifest")"
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

  # ---- 7. what the member still installs themselves ----
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
  SOS_HOME="$SOS_HOME" PATH="$PY_ENV/bin:$PATH" "$PY_ENV/bin/python" "$SOS_HOME/pipeline/sos.py" doctor >/dev/null 2>&1 || true

  printf '\n\033[1m✓ SoloOS is installed.\033[0m\n'
  echo "Next:"
  [ "$missing" = 1 ] && echo "  • Install what's marked ! above (the app's Setup button shows the same list)."
  echo "  • In After Effects: Settings → Scripting & Expressions → tick “Allow Scripts to Write Files and Access Network”;"
  echo "    Settings → General → untick “Show Home Screen at Startup”."
  echo "  • Open “$APP_NAME” and press “Sign in with Claude”."
  [ -n "${SOS_NO_OPEN:-}" ] || open "$dest/$APP_NAME.app" 2>/dev/null || true
}

# Downloads the pack parts named in the manifest (resume-safe, checksummed), unpacks it beside the old one, carries
# the member's own files over (style logs, MISTAKES/WINS logs, presets, brand kit), then swaps it in.
install_pack() {
  local manifest="$1" version="$2" py="$PY_ENV/bin/python"
  local parts
  parts="$("$py" -c "import json,sys; [print(p['name'], p['sha256']) for p in json.load(open(sys.argv[1]))['parts']]" "$manifest")"
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
