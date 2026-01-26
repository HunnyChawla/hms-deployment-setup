@echo off
REM ========================================
REM HMS Docker Deployment - Windows Setup
REM ========================================
REM Double-click this file to start the HMS deployment menu
REM This script auto-detects its location - no configuration needed

cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -NoProfile -File "orchestrator.ps1" %*
pause
