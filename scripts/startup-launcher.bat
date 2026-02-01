@echo off
REM SimGolf Startup Launcher — place a shortcut to this in shell:startup
REM Master copy of the GSPro desktop shortcut lives at C:\SimGolf\GSPro.lnk

set REPO=C:\SimGolf\sig-facility
set SHORTCUT_MASTER=C:\SimGolf\GSPro.lnk
set SHORTCUT_DESKTOP=%USERPROFILE%\Desktop\GSPro.lnk
set OVERLAY_SCRIPT=%REPO%\scripts\startup-overlay.ps1

REM Remove desktop shortcut during update
if exist "%SHORTCUT_DESKTOP%" del "%SHORTCUT_DESKTOP%"

REM Show "please wait" overlay
start /min powershell.exe -ExecutionPolicy Bypass -File "%OVERLAY_SCRIPT%"

REM Update supervisor from repo before starting it
if exist "%REPO%\install\supervisor.ps1" copy /Y "%REPO%\install\supervisor.ps1" "C:\SimGolf\supervisor.ps1" >nul

echo Starting SimGolf supervisor...
start /min powershell.exe -ExecutionPolicy Bypass -File "C:\SimGolf\supervisor.ps1"

echo Waiting for supervisor to finish initial update...
timeout /t 30 /nobreak >nul

REM Close the overlay using saved PID
powershell.exe -Command "if (Test-Path 'C:\SimGolf\overlay.pid') { $p = Get-Content 'C:\SimGolf\overlay.pid'; Stop-Process -Id $p -Force -ErrorAction SilentlyContinue; Remove-Item 'C:\SimGolf\overlay.pid' -Force }"

REM Restore desktop shortcut
if exist "%SHORTCUT_MASTER%" copy "%SHORTCUT_MASTER%" "%SHORTCUT_DESKTOP%" >nul

echo Starting monitoring...
start /min powershell.exe -ExecutionPolicy Bypass -File "%REPO%\scripts\monitoring\check-status.ps1"

echo Starting booking popup...
start "" "%REPO%\scripts\popup\download-show-dialog.ahk"

REM Write config flags for AHK scripts
powershell.exe -ExecutionPolicy Bypass -Command ". '%REPO%\lib\Config.ps1'; $c = Get-SimGolfConfig; if ($c.hasRelay -eq $false) { Set-Content 'C:\SimGolf\no-relay' '' -Force } else { Remove-Item 'C:\SimGolf\no-relay' -Force -ErrorAction SilentlyContinue }"

echo Starting GSPro automation...
start "" "%REPO%\scripts\gspro-automation\gspro-start-v2.ahk"
