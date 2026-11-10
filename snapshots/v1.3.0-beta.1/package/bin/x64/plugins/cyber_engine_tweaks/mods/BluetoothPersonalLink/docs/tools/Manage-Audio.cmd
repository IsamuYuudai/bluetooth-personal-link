@echo off
setlocal
rem Optional visible audio-manager window; readable PowerShell, no encoded commands.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Manage-Audio.ps1"
endlocal
