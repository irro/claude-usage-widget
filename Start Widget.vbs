' Starts the Claude Usage Widget with no console window (no flash).
' Double-click this file to launch the widget.
Dim fso, sh, dir, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\usage-widget.ps1"""
sh.Run cmd, 0, False
