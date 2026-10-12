@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\preview-voice-vote.ps1" %*
exit /b %ERRORLEVEL%
