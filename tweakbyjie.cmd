@echo off
rem tweakbyjie launcher: prefer PowerShell 7 (pwsh), fall back to built-in Windows PowerShell 5.1.
rem Keep this file ASCII-only: cmd parses batch files in the OEM codepage.
where pwsh >nul 2>&1
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0tweakbyjie.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tweakbyjie.ps1"
)
