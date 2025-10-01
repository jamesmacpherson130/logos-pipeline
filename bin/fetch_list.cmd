@echo off
setlocal
if "%~1"=="" (
  echo Usage: fetch_list ids.txt
  exit /b 1
)
for /f "usebackq delims=" %%I in ("%~1") do call "%%~dp0fetch_one.cmd" %%I
