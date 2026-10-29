@echo off
setlocal enabledelayedexpansion

echo [INFO] Running automated IPA downloader...
python download_ipa.py
if %ERRORLEVEL% EQU 0 (
    echo [SUCCESS] IPA download completed successfully.
) else (
    echo [ERROR] IPA download failed.
)
pause
