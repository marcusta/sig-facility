@echo off
REM SimGolf Startup Launcher — place a shortcut to this in shell:startup
REM Master copy of the GSPro desktop shortcut lives at C:\SimGolf\GSPro.lnk

set SHORTCUT_MASTER=C:\SimGolf\GSPro.lnk
set SHORTCUT_DESKTOP=%USERPROFILE%\Desktop\GSPro.lnk
set OVERLAY_SCRIPT=C:\SimGolf\sig-facility\scripts\startup-overlay.ps1

REM Remove desktop shortcut during update
if exist "%SHORTCUT_DESKTOP%" del "%SHORTCUT_DESKTOP%"

REM Show "please wait" overlay
start /min powershell.exe -ExecutionPolicy Bypass -File "%OVERLAY_SCRIPT%"

echo Starting SimGolf supervisor...
start /min powershell.exe -ExecutionPolicy Bypass -File "C:\SimGolf\supervisor.ps1"

echo Waiting for supervisor to finish initial update...
timeout /t 30 /nobreak >nul

REM Close the overlay
taskkill /fi "WINDOWTITLE eq Vänligen*" /f >nul 2>&1
powershell.exe -Command "Get-Process powershell | Where-Object { $_.CommandLine -like '*startup-overlay*' } | Stop-Process -Force" >nul 2>&1

REM Restore desktop shortcut
if exist "%SHORTCUT_MASTER%" copy "%SHORTCUT_MASTER%" "%SHORTCUT_DESKTOP%" >nul

echo Starting GSPro automation...
start "" "C:\SimGolf\sig-facility\scripts\gspro-automation\gspro-start-v2.ahk"
