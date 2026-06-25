@echo off
rem Stops the widget from launching automatically at sign-in.
rem (Does not close it if it is currently running - use the x or right-click - Exit for that.)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=(Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Usage Widget.lnk'); if(Test-Path $p){ Remove-Item $p -Force; Write-Host ''; Write-Host '  Removed from startup.' -ForegroundColor Yellow } else { Write-Host ''; Write-Host '  It was not in startup - nothing to remove.' }"
echo.
pause
