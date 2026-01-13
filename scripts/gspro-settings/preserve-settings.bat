@echo off
setlocal enabledelayedexpansion

set "SOURCE_DIR=%USERPROFILE%\AppData\LocalLow\GSPro\GSPro"
set "FILE1=dpsV2x3.gss"
set "FILE2=Settings.vgs"

if not exist "%SOURCE_DIR%" (
    echo Error: Source directory does not exist.
    echo %SOURCE_DIR%
    goto :EOF
)

for %%F in (%FILE1% %FILE2%) do (
    if exist "%SOURCE_DIR%\%%F" (
        copy "%SOURCE_DIR%\%%F" "%SOURCE_DIR%\%%F.orig"
        if !errorlevel! equ 0 (
            echo Successfully copied %%F to %%F.orig
        ) else (
            echo Failed to copy %%F
        )
    ) else (
        echo Warning: %%F does not exist in the source directory.
    )
)

pause