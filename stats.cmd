@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\release-stats.ps1" %*
exit /b %ERRORLEVEL%
