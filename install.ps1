# Claude Usage Widget - installer
# Copies the widget to a stable per-user location, clears the "downloaded from
# the internet" flag (so nothing gets blocked or nags), creates a Desktop
# shortcut with the icon, and launches it. Safe to re-run to update.
$ErrorActionPreference = 'Stop'
$src  = $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA 'Claude Usage Widget'

Write-Host ''
Write-Host '  Installing Claude Usage Widget...' -ForegroundColor Cyan

# stop any running copy so we can update cleanly (only the widget - matches the
# hidden -File launch signature, never a normal PowerShell window)
try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -match 'WindowStyle Hidden -File.*usage-widget\.ps1' } |
      ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }
} catch {}

# copy the widget into place
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item (Join-Path $src '*') -Destination $dest -Recurse -Force

# remove Mark-of-the-Web from every copied file so Windows won't block/warn
Get-ChildItem $dest -Recurse -File | ForEach-Object { try { Unblock-File -LiteralPath $_.FullName } catch {} }

# Desktop shortcut (custom icon, no console flash via wscript + the .vbs)
$wsh = New-Object -ComObject WScript.Shell
$lnk = $wsh.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Claude Usage Widget.lnk'))
$lnk.TargetPath       = 'C:\Windows\System32\wscript.exe'
$lnk.Arguments        = '"' + (Join-Path $dest 'Start Widget.vbs') + '"'
$lnk.WorkingDirectory = $dest
$lnk.IconLocation     = (Join-Path $dest 'widget.ico') + ',0'
$lnk.Description       = "Start the Claude Usage Widget (today's Claude Code usage)"
$lnk.WindowStyle      = 7
$lnk.Save()

# launch it now
Start-Process 'C:\Windows\System32\wscript.exe' -ArgumentList ('"' + (Join-Path $dest 'Start Widget.vbs') + '"')

Write-Host ''
Write-Host '  Done! The widget is running (bottom-left of your screen), and there is now' -ForegroundColor Green
Write-Host '  a "Claude Usage Widget" icon on your Desktop to start it anytime.' -ForegroundColor Green
Write-Host ''
Write-Host '  It shows your Claude CODE usage for today. If you do not use Claude Code,' -ForegroundColor DarkGray
Write-Host '  it will simply show no usage yet.' -ForegroundColor DarkGray
Write-Host ''
