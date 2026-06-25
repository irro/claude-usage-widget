@echo off
rem Makes the widget launch automatically every time you sign in to Windows.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=New-Object -ComObject WScript.Shell; $l=$s.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Usage Widget.lnk')); $l.TargetPath=(Join-Path '%~dp0' 'Start Widget.vbs'); $l.WorkingDirectory='%~dp0'; $l.Save(); Write-Host ''; Write-Host '  Done. The widget will now start automatically when you sign in.' -ForegroundColor Green"
echo.
pause
