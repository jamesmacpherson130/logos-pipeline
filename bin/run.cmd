@echo off
setlocal
REM Pass everything verbatim to PowerShell using --% (stop parsing)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" --% %*
endlocal
