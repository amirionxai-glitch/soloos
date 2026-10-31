# SoloOS installer for Windows, app first (0.11.0): installs the app and the styles pack, then opens SoloOS within a
# minute or two; the heavy editing tools (Git Bash, Claude Code, Python, WhisperX, the speech model) install inside the
# app's Setup screen with progress and Retry, from install-tools.ps1 (the one place the tool steps live). No admin
# rights except the one Visual C++ runtime prompt. Re-running it updates / repairs; finished steps are skipped. Same
# steps as install.sh (the Mac one); keep the two in step. $env:SOS_WITH_TOOLS=1 also installs the tools here.
#
#   powershell -ExecutionPolicy Bypass -c "iex ((irm https://raw.githubusercontent.com/amirionxai-glitch/soloos/main/install.ps1) -join [char]10)"
#   (one string into iex: Windows PowerShell 5.1 sometimes hands `irm | iex` the script line by line, 2026-10-31)
#
# What goes where (nothing needs admin; bin\, python\, git\, models\ and Claude Code come from install-tools.ps1):
#   %LOCALAPPDATA%\SOS\bin\       micromamba
#   %LOCALAPPDATA%\SOS\python\    Python 3.11 + ffmpeg/ffprobe + node + WhisperX + yt-dlp (conda-forge/pip)
#   %LOCALAPPDATA%\SOS\git\       Git for Windows (portable): Claude Code runs its commands in Git Bash
#   %LOCALAPPDATA%\SOS\models\    WhisperX model cache (HF_HOME)
#   %LOCALAPPDATA%\SOS\sos\       the asset pack (SOS_HOME): styles, templates, music, sounds, the hub
#   %LOCALAPPDATA%\Programs\SoloOS\   the app (Start menu + desktop shortcut)
#   %USERPROFILE%\.local\bin\claude.exe   Claude Code, by Anthropic's own installer (skipped if present)
#   per-user fonts                Instrument Serif, Poppins (free, OFL)
# ASCII only: Windows PowerShell 5.1 reads a file without a BOM as ANSI.

function Install-SoloOS {
  # "Continue", not "Stop": Windows PowerShell 5.1 turns any stderr line of a native tool (curl's progress, a probe's
  # ImportError) into a fatal error under "Stop". Failures are checked by exit code and thrown below.
  $ErrorActionPreference = "Continue"
  $ProgressPreference = "SilentlyContinue"   # PowerShell 5.1's progress bar slows downloads 10x
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  $Repo = if ($env:SOS_REPO) { $env:SOS_REPO } else { "amirionxai-glitch/soloos" }
  $DL = if ($env:SOS_DOWNLOAD) { $env:SOS_DOWNLOAD } else { "https://github.com/$Repo/releases/latest/download" }
  $Support = Join-Path $env:LOCALAPPDATA "SOS"
  $SosHome = Join-Path $Support "sos"
  $Cache = Join-Path $Support "downloads"
  $AppName = "SoloOS"

  function Step($t) { Write-Host ""; Write-Host "> $t" -ForegroundColor White }
  function Ok($t) { Write-Host "  OK $t" }
  function Warn($t) { Write-Host "  ! $t" -ForegroundColor Yellow }
  function Get-File($url, $out) {
    # curl.exe ships with Windows 10 1803+: resumes and retries big downloads
    & curl.exe -fL --retry 3 -C - -o $out $url 2>$null
    if ($LASTEXITCODE -ne 0) { & curl.exe -fL --retry 3 -o $out $url; if ($LASTEXITCODE -ne 0) { throw "Couldn't download $url" } }
  }

  # ---- 1. this PC ----
  Step "Checking this PC"
  if (-not [Environment]::Is64BitOperatingSystem) { throw "SoloOS needs 64-bit Windows 10 or 11." }
  $build = [Environment]::OSVersion.Version.Build
  if ($build -lt 17763) { throw "Windows 10 (1809) or newer is needed." }
  if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { Warn "Windows on ARM: the x64 app runs in emulation (slower)." }
  if (-not $env:SOS_FROM_APP -and (Get-Process -Name $AppName -ErrorAction SilentlyContinue)) { throw "Quit $AppName first, then run this again." }
  Ok "Windows build $build"
  New-Item -ItemType Directory -Force -Path $Cache | Out-Null

  # ---- 2. the Microsoft Visual C++ runtime (small; the editing tools need it) ----
  # micromamba 2.x (installed by the app's Setup) needs the Visual C++ runtime (a fresh Windows often lacks it: micromamba then exits 0xC0000135 with no
  # output). Microsoft's own redistributable, once per PC; the only step that asks for admin (one Windows prompt).
  if (-not ((Test-Path "$env:SystemRoot\System32\vcruntime140_1.dll") -and (Test-Path "$env:SystemRoot\System32\msvcp140.dll"))) {
    Write-Host "  installing the Microsoft Visual C++ runtime (Windows asks to allow it)..."
    $vc = Join-Path $Cache "vc_redist.x64.exe"
    Get-File "https://aka.ms/vs/17/release/vc_redist.x64.exe" $vc
    try { $p = Start-Process -FilePath $vc -ArgumentList "/install", "/quiet", "/norestart" -Verb RunAs -Wait -PassThru -ErrorAction Stop }
    catch { throw "SoloOS needs the Microsoft Visual C++ runtime: run the installer again and press Yes when Windows asks." }
    # 3010 = installed, restart pending (the DLLs work at once); 1638 = a newer one is already there
    if ($p.ExitCode -notin 0, 3010, 1638) { throw "The Microsoft Visual C++ runtime didn't install (code $($p.ExitCode))." }
    Remove-Item -Force $vc -ErrorAction SilentlyContinue
    Ok "Microsoft Visual C++ runtime"
  }

  # ---- 3. the asset pack: styles, templates, music, sounds, the hub ----
  Step "Styles and sounds"
  $manifestFile = Join-Path $Cache "sos-pack.json"
  # never resumed: curl -C - glued the new manifest onto the last release's copy ("Invalid JSON primitive", 2026-10-31)
  Remove-Item -Force $manifestFile -ErrorAction SilentlyContinue
  try { Get-File "$DL/sos-pack.json" $manifestFile } catch { throw "Couldn't reach the release ($DL). Check the internet connection and try again." }
  $manifest = Get-Content -Raw $manifestFile | ConvertFrom-Json
  $have = if (Test-Path "$SosHome\VERSION") { (Get-Content -Raw "$SosHome\VERSION").Trim() } else { "none" }
  if ($have -eq $manifest.version) { Ok "up to date ($have)" }
  else {
    # each part is cached under its checksum: a resume only continues the same file, never an older release's part
    function PartFile($p) { Join-Path $Cache ($p.sha256.Substring(0, 12) + "-" + $p.name) }
    foreach ($p in $manifest.parts) {
      $f = PartFile $p
      if ((Test-Path $f) -and ((Get-FileHash -Algorithm SHA256 $f).Hash.ToLower() -eq $p.sha256)) { continue }
      Write-Host "  downloading $($p.name)..."
      Get-File "$DL/$($p.name)" $f
      if ((Get-FileHash -Algorithm SHA256 $f).Hash.ToLower() -ne $p.sha256) { Remove-Item -Force $f; throw "$($p.name) didn't download correctly. Run the installer again." }
    }
    $tgz = Join-Path $Cache "sos-pack.tar.gz"
    $out = [IO.File]::Create($tgz)
    try { foreach ($p in $manifest.parts) { $in = [IO.File]::OpenRead((PartFile $p)); $in.CopyTo($out); $in.Close() } } finally { $out.Close() }
    $new = Join-Path $Support "sos.new"
    if (Test-Path $new) { Remove-Item -Recurse -Force $new }
    New-Item -ItemType Directory -Force -Path $new | Out-Null
    & "$env:SystemRoot\System32\tar.exe" -xzf $tgz -C $new
    if ($LASTEXITCODE -ne 0) { throw "The styles pack didn't unpack. Run the installer again." }
    Set-Content -NoNewline -Path "$new\VERSION" -Value $manifest.version
    if (Test-Path $SosHome) {
      # the member's own files carry over (style logs, MISTAKES/WINS logs, presets, brand kit)
      $keep = @("MISTAKES-LOG.md", "WINS-LOG.md", "SOLO_OPERATOR\presets.json")
      $keep += Get-ChildItem -Path "$SosHome\motion-library\editing-styles\*\LOG.md" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($SosHome.Length + 1) }
      foreach ($k in $keep) {
        $src = Join-Path $SosHome $k; $dst = Join-Path $new $k
        if ((Test-Path $src) -and (Test-Path (Split-Path $dst))) { Copy-Item -Force $src $dst }
      }
      if (Test-Path "$SosHome\SOLO_OPERATOR\brand") {
        Remove-Item -Recurse -Force "$new\SOLO_OPERATOR\brand" -ErrorAction SilentlyContinue
        Copy-Item -Recurse "$SosHome\SOLO_OPERATOR\brand" "$new\SOLO_OPERATOR\brand"
      }
      if (Test-Path "$Support\sos.old") { Remove-Item -Recurse -Force "$Support\sos.old" }
      Rename-Item $SosHome "sos.old" -ErrorAction Stop
    }
    Rename-Item $new "sos" -ErrorAction Stop
    Remove-Item -Recurse -Force "$Support\sos.old" -ErrorAction SilentlyContinue
    Remove-Item -Force $tgz
    foreach ($p in $manifest.parts) { Remove-Item -Force (PartFile $p) -ErrorAction SilentlyContinue }
    Ok "installed $($manifest.version) (was $have)"
  }

  # ---- 4. fonts (free ones, per user: no admin) ----
  Step "Fonts"
  $fontDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
  New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
  $reg = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
  if (-not (Test-Path $reg)) { New-Item -Path $reg -Force | Out-Null }
  Get-ChildItem "$SosHome\fonts\*.ttf" -ErrorAction SilentlyContinue | ForEach-Object {
    $dst = Join-Path $fontDir $_.Name
    if (-not (Test-Path $dst) -and -not (Test-Path "$env:SystemRoot\Fonts\$($_.Name)")) {
      Copy-Item $_.FullName $dst
      New-ItemProperty -Path $reg -Name "$($_.BaseName) (TrueType)" -Value $dst -PropertyType String -Force | Out-Null
    }
  }
  Ok "Instrument Serif, Poppins"

  # ---- 5. the app ----
  Step "The app"
  $dest = if ($env:SOS_APP_DEST) { $env:SOS_APP_DEST } else { Join-Path $env:LOCALAPPDATA "Programs" }
  # from the app's Update button (SOS_APP_STAGE): the new copy goes beside it, the app swaps it in once it has quit
  $into = if ($env:SOS_APP_STAGE) { $env:SOS_APP_STAGE } else { $dest }
  New-Item -ItemType Directory -Force -Path $into | Out-Null
  $appExe = Join-Path $dest "$AppName\$AppName.exe"
  $appHave = if (Test-Path $appExe) { (Get-Item $appExe).VersionInfo.FileVersion } else { "none" }
  # app_version_win: a Windows-only app build (made on the PC); without it the Windows app follows app_version
  $appWant = if ($manifest.app_version_win) { $manifest.app_version_win } else { $manifest.app_version }
  if ($appHave -eq $appWant) { Ok "up to date ($appHave)" }
  else {
    $zip = Join-Path $Cache "SOS-win-x64.zip"
    Remove-Item -Force $zip -ErrorAction SilentlyContinue   # a leftover from another release must not be resumed into
    Get-File "$DL/SOS-win-x64.zip" $zip
    $target = Join-Path $into $AppName
    if (Test-Path $target) { Remove-Item -Recurse -Force $target }
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    & "$env:SystemRoot\System32\tar.exe" -xf $zip -C $target       # bsdtar reads zip, much faster than Expand-Archive
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$target\$AppName.exe")) { throw "The app didn't unpack. Run the installer again." }
    Remove-Item -Force $zip
    Get-ChildItem -Recurse $target | Unblock-File -ErrorAction SilentlyContinue
    if ($into -eq $dest) { Ok "installed $appWant in $dest\$AppName" } else { Ok "downloaded $appWant (SoloOS restarts into it)" }
  }
  $exe = Join-Path $dest "$AppName\$AppName.exe"
  $shell = New-Object -ComObject WScript.Shell
  foreach ($lnkDir in @([Environment]::GetFolderPath("Programs"), [Environment]::GetFolderPath("Desktop"))) {
    $lnk = $shell.CreateShortcut((Join-Path $lnkDir "$AppName.lnk"))
    $lnk.TargetPath = $exe
    $lnk.WorkingDirectory = Split-Path $exe
    $lnk.IconLocation = "$(Join-Path $dest "$AppName\resources\icon.ico"),0"
    $lnk.Save()
  }
  Ok "Start menu and desktop shortcut"

  # ---- 6. what the member still installs themselves ----
  Step "Checking Blender and After Effects"
  $blender = Get-ChildItem "$env:ProgramFiles\Blender Foundation\Blender*\blender.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
  $missing = $false
  if ($blender) { Ok "Blender ($($blender.FullName))" } else { Warn "Blender (Toon Story 3D uses it): https://www.blender.org/download/"; $missing = $true }
  Warn "After Effects styles are Mac only for now (the Windows version comes soon)."

  # ---- 7. the editing tools: only when asked; otherwise the app's Setup screen installs them ----
  if ($env:SOS_WITH_TOOLS) {
    Step "Editing tools"
    $tools = Join-Path $Cache "install-tools.ps1"
    Remove-Item -Force $tools -ErrorAction SilentlyContinue
    Get-File "$DL/install-tools.ps1" $tools
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tools
    if ($LASTEXITCODE -ne 0) { Warn "some tools didn't install: the app's Setup screen shows which, with Retry" }
  }

  if ($env:SOS_FROM_APP) { return }   # the app's Update button: it restarts into the new version itself
  Write-Host ""
  Write-Host "SoloOS is installed." -ForegroundColor Green
  if (-not $env:SOS_NO_OPEN) {
    Start-Process -FilePath $exe -ErrorAction SilentlyContinue
    Write-Host "SoloOS is open. Finish setup inside the app (it installs the editing tools while you look around)."
  } else { Write-Host "Open $AppName (Start menu or desktop): it signs you in, then finishes setup by itself." }
  Write-Host "If Windows says 'Windows protected your PC': More info -> Run anyway (the app isn't signed yet)."
  if ($missing) { Write-Host "Install what's marked ! above when you can (the app's Setup button shows the same list)." }
}

try { Install-SoloOS }
catch {
  Write-Host ""
  Write-Host "x $($_.Exception.Message)" -ForegroundColor Red
  if ($PSCommandPath) { exit 1 } else { throw }
}
