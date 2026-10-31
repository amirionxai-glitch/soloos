# SoloOS editing tools for Windows: the heavy part of the install, run by the app's Setup screen (lib/setup.js) after
# install.ps1 has put the app and the styles pack in place. One source of truth for the tool steps: the app runs this
# file (bundled in the app; also a release asset); `$env:SOS_WITH_TOOLS=1` makes install.ps1 run it from a terminal.
# Same steps as install-tools.sh (the Mac one); keep the two in step.
#
#   install-tools.ps1                  every step, in order (finished ones are skipped)
#   install-tools.ps1 whisperx model   only those steps (Setup's Retry)
#
# Steps: git (portable Git Bash, Claude Code runs its commands in it) - claude - micromamba - python (Python 3.11 +
# ffmpeg + node) - whisperx (WhisperX, OpenCV, yt-dlp) - model
# Each step prints "::sos step <id> start|done|skip|fail [text]" for the app; full output goes to SOS\logs\setup.log.
# A failed step doesn't stop the others; a step whose base failed is marked failed too. Never touches downloaded
# models, styles or projects.
#
# Windows PowerShell 5.1: a native tool's stderr line becomes a NativeCommandError record, fatal under "Stop" and noisy
# when redirected (a hidden run died at the WhisperX check, 2026-10-31). So every native command runs through cmd.exe
# with 2>&1 merged there (plain text lines, never error records), and success is read from $LASTEXITCODE only.
# ASCII only: Windows PowerShell 5.1 reads a file without a BOM as ANSI.

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Support = Join-Path $env:LOCALAPPDATA "SOS"
$Bin = Join-Path $Support "bin"
$PyEnv = Join-Path $Support "python"
$Py = Join-Path $PyEnv "python.exe"
$Cache = Join-Path $Support "downloads"
$Logs = Join-Path $Support "logs"
$Log = Join-Path $Logs "setup.log"
$Mm = Join-Path $Bin "micromamba.exe"
$GitBash = Join-Path $Support "git\bin\bash.exe"
$env:MAMBA_ROOT_PREFIX = Join-Path $Support "mamba"
$env:HF_HOME = Join-Path $Support "models"
$env:HF_HUB_DISABLE_XET = "1"   # Hugging Face's Xet downloader stalled at 0 bytes on Windows; plain HTTPS works
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"
$env:PATH = "$PyEnv;$PyEnv\Scripts;$PyEnv\Library\bin;$Bin;$env:USERPROFILE\.local\bin;$env:PATH"
New-Item -ItemType Directory -Force -Path $Bin, $Cache, $Logs, $env:HF_HOME | Out-Null

$All = @("git", "claude", "micromamba", "python", "whisperx", "model")
$Steps = if ($args.Count) { @($args) } else { $All }
$Failed = @()

function LogLine($t) { Add-Content -Path $Log -Value $t -Encoding UTF8 -ErrorAction SilentlyContinue }
function Mark($id, $state, $text) {
  $line = "::sos step $id $state" + $(if ($text) { " $text" } else { "" })
  Write-Host $line
  LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] step $id $state $text"
}
# Runs a native command; its output (stdout + stderr, merged by cmd.exe) goes to the screen and the log.
# Returns the exit code.
function Run([string]$exe, [string[]]$argv) {
  $q = { param($a) if ($a -match '[\s"&|<>^]') { '"' + ($a -replace '"', '\"') + '"' } else { $a } }
  $cmdline = '"' + $exe + '"' + (($argv | ForEach-Object { " " + (& $q $_) }) -join "")
  & cmd.exe /d /s /c "`"$cmdline 2>&1`"" | ForEach-Object { $l = "$_"; Write-Host $l; LogLine $l }
  return $LASTEXITCODE
}
function Quiet([string]$exe, [string[]]$argv) {
  $cmdline = '"' + $exe + '"' + (($argv | ForEach-Object { " `"$_`"" }) -join "")
  & cmd.exe /d /s /c "`"$cmdline >nul 2>&1`""
  return ($LASTEXITCODE -eq 0)
}
function Get-File($url, $out) {
  # curl.exe ships with Windows 10 1803+; --retry for flaky connections
  return ((Run "$env:SystemRoot\System32\curl.exe" @("-fL", "--retry", "3", "-sS", "-o", $out, $url)) -eq 0)
}

function SysBash { @("$env:ProgramFiles\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1 }
function ClaudeOk { (Test-Path "$env:USERPROFILE\.local\bin\claude.exe") -or [bool](Get-Command claude.exe -ErrorAction SilentlyContinue) }
function PythonOk { (Test-Path $Py) -and (Test-Path "$PyEnv\Library\bin\ffprobe.exe") -and (Test-Path "$PyEnv\node.exe") -and (Quiet $Py @("-c", "import sys")) }
function WhisperxOk { (Quiet $Py @("-c", "import whisperx, cv2, scipy, PIL, numpy")) -and (Test-Path "$PyEnv\Scripts\yt-dlp.exe") }
function ModelOk {
  $th = if ($env:TORCH_HOME) { $env:TORCH_HOME } else { Join-Path $env:USERPROFILE ".cache\torch" }
  (Quiet $Py @("-c", "from faster_whisper import download_model as d; d('medium.en', local_files_only=True)")) -and (Test-Path "$th\hub\checkpoints\wav2vec2_fairseq_base_ls960_asr_ls960.pth")
}

# each step returns "skip", $true (done) or $false (failed)
function Step-git {
  if ((SysBash) -or (Test-Path $GitBash)) { return "skip" }
  $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest" -Headers @{ "User-Agent" = "SoloOS" } -ErrorAction Stop
  $asset = $rel.assets | Where-Object { $_.name -match '^PortableGit-.*-64-bit\.7z\.exe$' } | Select-Object -First 1
  if (-not $asset) { Write-Host "Couldn't find Git for Windows' portable download."; return $false }
  $sfx = Join-Path $Cache $asset.name
  if (-not (Get-File $asset.browser_download_url $sfx)) { return $false }
  Write-Host "unpacking Git..."
  # a GUI self-extractor: Start-Process -Wait, or PowerShell moves on before it has unpacked
  Start-Process -FilePath $sfx -ArgumentList @("-y", "-o`"$(Join-Path $Support 'git')`"") -Wait -WindowStyle Hidden
  Remove-Item -Force $sfx -ErrorAction SilentlyContinue
  return (Test-Path $GitBash)
}
function Step-claude {
  if (ClaudeOk) { return "skip" }
  if (-not (SysBash)) { $env:CLAUDE_CODE_GIT_BASH_PATH = $GitBash }
  # Anthropic's own installer, never modified
  $f = Join-Path $Cache "claude-install.ps1"
  if (-not (Get-File "https://claude.ai/install.ps1" $f)) { return $false }
  $null = Run "powershell.exe" @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $f)
  Remove-Item -Force $f -ErrorAction SilentlyContinue
  return (ClaudeOk)
}
function Step-micromamba {
  if ((Test-Path $Mm) -and (Quiet $Mm @("--version"))) { return "skip" }
  if (-not (Get-File "https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-win-64" "$Mm.tmp")) { return $false }
  Move-Item -Force "$Mm.tmp" $Mm
  # micromamba 2.x needs the Visual C++ runtime (install.ps1 installs it): without it it exits 0xC0000135 silently
  if ((Run $Mm @("--version")) -ne 0) { Write-Host "micromamba doesn't start: run the SoloOS install command again (it adds the Microsoft Visual C++ runtime)."; return $false }
  return $true
}
function Step-python {
  if (PythonOk) { return "skip" }
  if (Test-Path $PyEnv) {
    # a half-made env (e.g. only conda-meta after a stopped run): remove just that folder and make it again
    Write-Host "repairing an incomplete Python folder"
    Remove-Item -Recurse -Force $PyEnv -ErrorAction SilentlyContinue
  }
  if ((Run $Mm @("create", "-y", "-p", $PyEnv, "-c", "conda-forge", "python=3.11", "ffmpeg", "nodejs")) -ne 0) { return $false }
  $null = Quiet $Mm @("clean", "-a", "-y", "-q")
  return (PythonOk)
}
function Step-whisperx {
  if (WhisperxOk) { return "skip" }
  if (-not (Quiet $Py @("-c", "import whisperx, cv2, scipy, PIL, numpy"))) {
    if ((Run $Py @("-m", "pip", "install", "--upgrade", "pip")) -ne 0) { return $false }
    if ((Run $Py @("-m", "pip", "install", "--progress-bar", "off", "whisperx", "numpy", "scipy", "pillow", "opencv-python-headless", "yt-dlp")) -ne 0) { return $false }
  } else {
    if ((Run $Py @("-m", "pip", "install", "--progress-bar", "off", "yt-dlp")) -ne 0) { return $false }
  }
  return (WhisperxOk)
}
function Step-model {
  if (ModelOk) { return "skip" }
  # the speech model the edits use (medium.en, ~1.5 GB; resumes) + WhisperX's word-timing model (~360 MB)
  if ((Run $Py @("-c", "from faster_whisper import download_model as d; print(d('medium.en'))")) -ne 0) { return $false }
  if ((Run $Py @("-c", "import torchaudio; torchaudio.pipelines.WAV2VEC2_ASR_BASE_960H.get_model(); print('word-timing model ready')")) -ne 0) { return $false }
  return (ModelOk)
}

$Needs = @{ claude = "git"; python = "micromamba"; whisperx = "python"; model = "whisperx" }
LogLine ""
LogLine "==== SoloOS tools $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $($Steps -join ' ') ===="
foreach ($s in $Steps) {
  if ($All -notcontains $s) { Write-Host "unknown step $s"; continue }
  if ($Needs[$s] -and ($Failed -contains $Needs[$s])) { Mark $s "fail" "waiting for $($Needs[$s])"; $Failed += $s; continue }
  Mark $s "start"
  try { $r = & "Step-$s" } catch { Write-Host $_.Exception.Message; LogLine $_.Exception.Message; $r = $false }
  # a step's own output lines can end up in $r: the verdict is its last value
  $r = @($r)[-1]
  if ($r -eq "skip") { Mark $s "skip" "already installed" }
  elseif ($r -eq $true) { Mark $s "done" }
  else { Mark $s "fail" "see $Log"; $Failed += $s }
}
if ($Failed.Count) { exit 1 } else { exit 0 }
