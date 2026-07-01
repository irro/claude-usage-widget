@echo off
title Claude Usage Widget - Installer
rem One-click installer: runs install.ps1 next to this file (policy-bypassed so it
rem works on locked-down machines; install.ps1 also unblocks the copied files).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
