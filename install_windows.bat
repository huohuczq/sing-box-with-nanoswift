::#
@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

cd /d "%~dp0"

:: ==========================================
:: Admin check
:: ==========================================
net session >nul 2>&1
if !errorlevel! neq 0 (
    echo [ERROR] Administrator privileges required!
    pause
    exit /b 1
)

:: ==========================================
:: Installation directory input (新增)
:: ==========================================
echo.
set "INSTALL_DIR="
set /p INSTALL_DIR="Enter installation directory: "
if "!INSTALL_DIR!"=="" exit /b 1
if "!INSTALL_DIR:~-1!"=="\" set "INSTALL_DIR=!INSTALL_DIR:~0,-1!"
if not exist "!INSTALL_DIR!" mkdir "!INSTALL_DIR!"

echo [INFO] Using installation directory: !INSTALL_DIR!

:: 切换到安装目录（新增）
cd /d "!INSTALL_DIR!"

:: ==========================================
:: Proxy selection
:: ==========================================
echo 1] No Proxy
echo 2] v4.gh-proxy.org (Default)
echo 3] v6.gh-proxy.org
set /p PROXY_CHOICE="Enter selection [1-3] (Default is 2): "

if "!PROXY_CHOICE!"=="" set "PROXY_CHOICE=2"
if "!PROXY_CHOICE!"=="1" set "PROXY_PREFIX="
if "!PROXY_CHOICE!"=="2" set "PROXY_PREFIX=https://v4.gh-proxy.org/"
if "!PROXY_CHOICE!"=="3" set "PROXY_PREFIX=https://v6.gh-proxy.org/"
if "!PROXY_CHOICE!" neq "1" if "!PROXY_CHOICE!" neq "2" if "!PROXY_CHOICE!" neq "3" set "PROXY_PREFIX=https://v4.gh-proxy.org/"

:: ==========================================
:: Download URLs
:: ==========================================
set "RAW_BASE_URL=https://raw.githubusercontent.com/is928joe-jpg/sing-box-with-nanoswift/refs/heads/main/2026-06-27"
set "BINARY_NAME=sing-box-windows-amd64.exe"
set "SHA_NAME=sing-box-windows-amd64.exe.sha256"

set "FINAL_BIN_URL=!PROXY_PREFIX!!RAW_BASE_URL!/!BINARY_NAME!"
set "FINAL_SHA_URL=!PROXY_PREFIX!!RAW_BASE_URL!/!SHA_NAME!"

:: ==========================================
:: Download
:: ==========================================
echo [INFO] Downloading core binary...
curl -L -k --ssl-no-revoke -o "!BINARY_NAME!" "!FINAL_BIN_URL!"
if !errorlevel! neq 0 exit /b 1

echo [INFO] Downloading checksum...
curl -L -k --ssl-no-revoke -o "!SHA_NAME!" "!FINAL_SHA_URL!"
if !errorlevel! neq 0 exit /b 1

:: ==========================================
:: SHA256 verification
:: ==========================================
set "EXPECTED_HASH="
for /f "usebackq tokens=1" %%H in ("!SHA_NAME!") do set "EXPECTED_HASH=%%H"
set "EXPECTED_HASH=!EXPECTED_HASH: =!"

set "LOCAL_HASH="
for /f "skip=1 tokens=* delims=" %%i in ('
    certutil -hashfile "!BINARY_NAME!" SHA256 ^
    ^| findstr /v /i "certutil"
') do (
    if not defined LOCAL_HASH (
        set "LOCAL_HASH=%%i"
        set "LOCAL_HASH=!LOCAL_HASH: =!"
    )
)

if /i not "!LOCAL_HASH!"=="!EXPECTED_HASH!" (
    echo [ERROR] SHA256 mismatch!
    exit /b 1
)

del /f /q "!SHA_NAME!" >nul 2>&1

:: ==========================================
:: Stop services
:: ==========================================
taskkill /f /im sing-box.exe >nul 2>&1
taskkill /f /im nanoswift.exe >nul 2>&1
timeout /t 2 >nul

:: ==========================================
:: Remove old binary
:: ==========================================
if exist "version.txt" del /f /q "version.txt"
if exist "sing-box.exe" del /f /q "sing-box.exe"

:: ==========================================
:: Deploy new binary
:: ==========================================
move /y "!BINARY_NAME!" "sing-box.exe" >nul
if !errorlevel! neq 0 (
    copy /y "!BINARY_NAME!" "sing-box.exe" >nul || exit /b 1
)

if exist "sing-box.exe" sing-box.exe

:: ==========================================
:: Start nanoswift
:: ==========================================
if exist "nanoswift.exe" nanoswift.exe start nanoswift

echo [SUCCESS] Upgrade completed.
echo %date%
exit /b 0
