@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "BOOTSTRAP_PS1=%SCRIPT_DIR%install.ps1"

echo [AI-VIDEO] Starting Windows bootstrap...

if not exist "%BOOTSTRAP_PS1%" (
  echo [AI-VIDEO] ERROR: install.ps1 was not found next to install.cmd.
  pause
  exit /b 1
)

where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo [AI-VIDEO] ERROR: Windows PowerShell is required but was not found.
  pause
  exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%BOOTSTRAP_PS1%" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo [AI-VIDEO] Bootstrap failed with exit code %EXIT_CODE%.
  pause
)

exit /b %EXIT_CODE%
