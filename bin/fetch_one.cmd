@echo off
if "%~1"=="" (
  echo Usage: fetch_one PMCxxxxxxx
  exit /b 1
)
python "C:\Users\James\OneDrive\Desktop\science\pmc_pull.py" %1
