# Claude Usage Widget - installer
# Copies the widget to a stable per-user location, clears the "downloaded from
# the internet" flag (so nothing gets blocked or nags), optionally creates
# Desktop and/or Start Menu shortcuts (it asks), and launches it. Re-run to update.
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

# --- shortcuts (ask; default Yes; non-interactive falls back to the default) ---
function Ask-YesNo($q, $def=$true){
    $sfx = if($def){ ' [Y/n] ' } else { ' [y/N] ' }
    try { $a = Read-Host ('  ' + $q + $sfx) } catch { return $def }
    if([string]::IsNullOrWhiteSpace($a)){ return $def }
    return ($a.Trim().ToLower() -in @('y','yes'))
}
function New-WidgetShortcut($lnkPath, $dest){
    $wsh = New-Object -ComObject WScript.Shell
    $lnk = $wsh.CreateShortcut($lnkPath)
    $lnk.TargetPath       = 'C:\Windows\System32\wscript.exe'
    $lnk.Arguments        = '"' + (Join-Path $dest 'Start Widget.vbs') + '"'
    $lnk.WorkingDirectory = $dest
    $lnk.IconLocation     = (Join-Path $dest 'widget.ico') + ',0'
    $lnk.Description       = "Start the Claude Usage Widget (today's Claude Code usage)"
    $lnk.WindowStyle      = 7
    $lnk.Save()
}

Write-Host ''
$mkDesktop = Ask-YesNo 'Add a Desktop shortcut?'    $true
$mkStart   = Ask-YesNo 'Add a Start Menu shortcut?' $true
if($mkDesktop){
    try { New-WidgetShortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Claude Usage Widget.lnk') $dest; Write-Host '  + Desktop shortcut created' -ForegroundColor Green } catch { Write-Host '  ! could not create Desktop shortcut' -ForegroundColor Yellow }
}
if($mkStart){
    try { New-WidgetShortcut (Join-Path ([Environment]::GetFolderPath('Programs')) 'Claude Usage Widget.lnk') $dest; Write-Host '  + Start Menu shortcut created' -ForegroundColor Green } catch { Write-Host '  ! could not create Start Menu shortcut' -ForegroundColor Yellow }
}

# launch it now
Start-Process 'C:\Windows\System32\wscript.exe' -ArgumentList ('"' + (Join-Path $dest 'Start Widget.vbs') + '"')

Write-Host ''
Write-Host '  Done! The widget is running (bottom-left of your screen).' -ForegroundColor Green
if($mkDesktop -or $mkStart){ Write-Host '  Launch it anytime from the shortcut(s) you chose.' -ForegroundColor Green }
Write-Host ''
Write-Host '  It shows your Claude CODE usage for today. If you do not use Claude Code,' -ForegroundColor DarkGray
Write-Host '  it will simply show no usage yet.' -ForegroundColor DarkGray
Write-Host ''
