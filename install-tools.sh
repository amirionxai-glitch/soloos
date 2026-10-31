#!/bin/bash
# SoloOS editing tools for macOS: the heavy part of the install, run by the app's Setup screen (lib/setup.js) after
# install.sh has put the app and the styles pack in place. One source of truth for the tool steps: the app runs this
# file (bundled in the app; also a release asset), and `SOS_WITH_TOOLS=1 install.sh` runs it from a terminal.
#
#   install-tools.sh                 every step, in order (finished ones are skipped)
#   install-tools.sh whisperx model  only those steps (Setup's Retry)
#
# Steps: claude · micromamba · python (Python 3.11 + ffmpeg + node) · whisperx (WhisperX, OpenCV, yt-dlp) · model
# Each step prints "::sos step <id> start|done|skip|fail [text]" for the app, and its full output goes to
# SOS/logs/setup.log. A failed step doesn't stop the others; a step whose base failed is marked failed too.
# Never touches models already downloaded, styles or projects.

set -uo pipefail

SUPPORT="$HOME/Library/Application Support/SOS"
BIN="$SUPPORT/bin"
PY_ENV="$SUPPORT/python"
PY="$PY_ENV/bin/python"
LOGS="$SUPPORT/logs"
LOG="$LOGS/setup.log"
export MAMBA_ROOT_PREFIX="$SUPPORT/mamba"
export HF_HOME="$SUPPORT/models"
export PATH="$PY_ENV/bin:$BIN:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
mkdir -p "$BIN" "$LOGS" "$HF_HOME"

case "$(uname -m)" in
  arm64) ARCH=arm64; MM_ARCH=osx-arm64 ;;
  *) ARCH=x64; MM_ARCH=osx-64 ;;
esac

ALL=(claude micromamba python whisperx model)
STEPS=("$@")
[ ${#STEPS[@]} -eq 0 ] && STEPS=("${ALL[@]}")
FAILED=" "

mark() { echo "::sos step $1 $2${3:+ $3}"; echo "[$(date '+%F %T')] step $1 $2${3:+ $3}" >>"$LOG"; }
# runs a command with its output in the log and on screen (the app shows the last lines)
run() { "$@" 2>&1 | tee -a "$LOG"; return "${PIPESTATUS[0]}"; }
needs() { # needs <step> <base>: the base failed in this run → this one can't run
  case "$FAILED" in *" $2 "*) mark "$1" fail "waiting for $2"; FAILED="$FAILED$1 "; return 1 ;; esac
}

claude_ok() { command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ] || [ -x /usr/local/bin/claude ] || [ -x /opt/homebrew/bin/claude ]; }
python_ok() { [ -x "$PY" ] && [ -x "$PY_ENV/bin/ffprobe" ] && [ -x "$PY_ENV/bin/node" ] && "$PY" -c "import sys" >/dev/null 2>&1; }
whisperx_ok() { "$PY" -c "import whisperx, cv2, scipy, PIL, numpy" >/dev/null 2>&1 && [ -x "$PY_ENV/bin/yt-dlp" ]; }
model_ok() {
  "$PY" -c "from faster_whisper import download_model as d; d('medium.en', local_files_only=True)" >/dev/null 2>&1 \
    && [ -f "${TORCH_HOME:-$HOME/.cache/torch}/hub/checkpoints/wav2vec2_fairseq_base_ls960_asr_ls960.pth" ]
}

step_claude() {
  claude_ok && return 10
  # Anthropic's own installer, never modified
  local f="$SUPPORT/downloads/claude-install.sh"
  mkdir -p "$SUPPORT/downloads"
  run curl -fsSL -o "$f" https://claude.ai/install.sh && run bash "$f"
  local rc=$?; rm -f "$f"
  [ $rc -eq 0 ] && claude_ok
}

step_micromamba() {
  [ -x "$BIN/micromamba" ] && "$BIN/micromamba" --version >/dev/null 2>&1 && return 10
  run curl -fsSL --retry 3 -o "$BIN/micromamba.tmp" "https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-$MM_ARCH" || return 1
  chmod +x "$BIN/micromamba.tmp" && mv "$BIN/micromamba.tmp" "$BIN/micromamba" && run "$BIN/micromamba" --version
}

step_python() {
  python_ok && return 10
  # a half-made env (e.g. only conda-meta after a stopped run): remove just that folder and make it again
  [ -d "$PY_ENV" ] && { echo "  repairing an incomplete Python folder" | tee -a "$LOG"; rm -rf "$PY_ENV"; }
  local pkgs=(python=3.11 ffmpeg nodejs)
  # PyPI has no macOS-Intel torch wheels for current WhisperX: take torch from conda-forge instead
  [ "$ARCH" = x64 ] && pkgs+=(pytorch torchaudio)
  run "$BIN/micromamba" create -y -p "$PY_ENV" -c conda-forge "${pkgs[@]}" || return 1
  "$BIN/micromamba" clean -a -y -q >/dev/null 2>&1 || true   # drop the package downloads (~0.8 GB)
  python_ok
}

step_whisperx() {
  whisperx_ok && return 10
  if ! "$PY" -c "import whisperx, cv2, scipy, PIL, numpy" >/dev/null 2>&1; then
    run "$PY" -m pip install --upgrade pip || return 1
    run "$PY" -m pip install --progress-bar off whisperx numpy scipy pillow opencv-python-headless yt-dlp || return 1
  else
    run "$PY" -m pip install --progress-bar off yt-dlp || return 1
  fi
  whisperx_ok
}

step_model() {
  model_ok && return 10
  # the speech model the edits use (pipeline/reel.py: medium.en, ~1.5 GB; resumes) + WhisperX's word-timing model
  run "$PY" -c "from faster_whisper import download_model as d; print(d('medium.en'))" || return 1
  run "$PY" -c "import torchaudio; torchaudio.pipelines.WAV2VEC2_ASR_BASE_960H.get_model(); print('word-timing model ready')" || return 1
  model_ok
}

echo "" >>"$LOG"
echo "==== SoloOS tools $(date '+%F %T') · ${STEPS[*]} ====" >>"$LOG"
for s in "${STEPS[@]}"; do
  case "$s" in
    claude | micromamba) ;;
    python) needs python micromamba || continue ;;
    whisperx) needs whisperx python || continue ;;
    model) needs model whisperx || continue ;;
    *) echo "unknown step $s" >&2; continue ;;
  esac
  mark "$s" start
  "step_$s"
  rc=$?
  if [ $rc -eq 10 ]; then mark "$s" skip "already installed"
  elif [ $rc -eq 0 ]; then mark "$s" done
  else mark "$s" fail "see $LOG"; FAILED="$FAILED$s "; fi
done
[ "$FAILED" = " " ]
