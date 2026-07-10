@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

:: ============================================================
:: 权限检查
:: ============================================================
net session >nul 2>&1
if !errorlevel! neq 0 (
    echo [ERROR] Administrator privileges required!
    pause
    exit /b 1
)

:: ============================================================
:: 用户输入安装目录
:: ============================================================
set "INSTALL_DIR="
set /p INSTALL_DIR="Enter installation directory: "
if "!INSTALL_DIR!"=="" exit /b 1
if "!INSTALL_DIR:~-1!"=="\" set "INSTALL_DIR=!INSTALL_DIR:~0,-1!"
if not exist "!INSTALL_DIR!" mkdir "!INSTALL_DIR!"
echo [INFO] Target path confirmed: !INSTALL_DIR!

:: ============================================================
:: GitHub 代理选择
:: ============================================================
echo.
echo Please select a GitHub proxy:
echo 1] No Proxy
echo 2] v4.gh-proxy.org (Default)
echo 3] v6.gh-proxy.org
set "PROXY_CHOICE="
set /p PROXY_CHOICE="Enter selection [1-3] (Default is 2): "
if "!PROXY_CHOICE!"=="" set "PROXY_CHOICE=2"

if "!PROXY_CHOICE!"=="1" (
    set "PROXY_PREFIX="
) else if "!PROXY_CHOICE!"=="2" (
    set "PROXY_PREFIX=https://v4.gh-proxy.org/"
) else if "!PROXY_CHOICE!"=="3" (
    set "PROXY_PREFIX=https://v6.gh-proxy.org/"
) else (
    echo [WARN] Invalid input. Falling back to v4 proxy.
    set "PROXY_PREFIX=https://v4.gh-proxy.org/"
)

:: ============================================================
:: 下载目录（使用 %TEMP%）
:: ============================================================
set "DOWNLOAD_DIR=%TEMP%\singbox_upgrade"
if not exist "!DOWNLOAD_DIR!" mkdir "!DOWNLOAD_DIR!"
cd /d "!DOWNLOAD_DIR!"

set "RAW_BASE_URL=https://raw.githubusercontent.com/is928joe-jpg/sing-box-with-nanoswift/refs/heads/main/2026-06-27"
set "BINARY_NAME=sing-box-windows-amd64.exe"
set "SHA_NAME=sing-box-windows-amd64.exe.sha256"
set "FINAL_BIN_URL=!PROXY_PREFIX!!RAW_BASE_URL!/!BINARY_NAME!"
set "FINAL_SHA_URL=!PROXY_PREFIX!!RAW_BASE_URL!/!SHA_NAME!"

:: ============================================================
:: 下载核心组件（含 HTTP 状态码检查）
:: ============================================================
echo.
echo [INFO] Downloading core binary...
curl -L -k --ssl-no-revoke -w "HTTP=%{http_code}" -o "!BINARY_NAME!" "!FINAL_BIN_URL!" >curl_status.txt
findstr /i "HTTP=200" curl_status.txt >nul || exit /b 1

echo [INFO] Downloading checksum file...
curl -L -k --ssl-no-revoke -w "HTTP=%{http_code}" -o "!SHA_NAME!" "!FINAL_SHA_URL!" >curl_status.txt
findstr /i "HTTP=200" curl_status.txt >nul || exit /b 1

:: ============================================================
:: SHA256 校验（含 TAB 修复）
:: ============================================================
echo.
echo [INFO] Performing SHA256 integrity check...

set "EXPECTED_HASH="
for /f "usebackq tokens=1" %%H in ("!SHA_NAME!") do (
    set "EXPECTED_HASH=%%H"
    goto got_expected_hash
)
:got_expected_hash

set "EXPECTED_HASH=!EXPECTED_HASH: =!"
set "EXPECTED_HASH=!EXPECTED_HASH:  =!"

set "LOCAL_HASH="
for /f "skip=1 tokens=* delims=" %%i in ('
    certutil -hashfile "!BINARY_NAME!" SHA256 ^
    ^| findstr /v /i "certutil"
') do (
    set "LOCAL_HASH=%%i"
    goto got_local_hash
)
:got_local_hash

set "LOCAL_HASH=!LOCAL_HASH: =!"
set "LOCAL_HASH=!LOCAL_HASH:    =!"

for %%A in (A=a B=b C=c D=d E=e F=f G=g H=h I=i J=j K=k L=l M=m N=n O=o P=p Q=q R=r S=s T=t U=u V=v W=w X=x Y=y Z=z) do (
    for /f "tokens=1,2 delims==" %%X in ("%%A") do (
        set "EXPECTED_HASH=!EXPECTED_HASH:%%X=%%Y!"
        set "LOCAL_HASH=!LOCAL_HASH:%%X=%%Y!"
    )
)

echo     Expected Hash: !EXPECTED_HASH!
echo     Calculated Hash: !LOCAL_HASH!

if "!LOCAL_HASH!" neq "!EXPECTED_HASH!" exit /b 1
echo [SUCCESS] SHA256 check passed.

:: ============================================================
:: 杀进程（修复逻辑）
:: ============================================================
echo.
echo [INFO] Terminating running processes...

set /a PROCESS_POLL=0
:poll_loop
timeout /t 1 >nul

tasklist /fi "imagename eq sing-box.exe" | findstr /i "sing-box.exe" >nul
if !errorlevel! == 0 (
    taskkill /f /im sing-box.exe >nul 2>&1
    set /a PROCESS_POLL+=1
)

tasklist /fi "imagename eq nanoswift.exe" | findstr /i "nanoswift.exe" >nul
if !errorlevel! == 0 (
    taskkill /f /im nanoswift.exe >nul 2>&1
    set /a PROCESS_POLL+=1
)

if !PROCESS_POLL! gtr 0 if !PROCESS_POLL! lss 6 goto poll_loop
echo [INFO] Process termination verified.

:: ============================================================
:: 切换目录
:: ============================================================
cd /d "!INSTALL_DIR!"

:: ============================================================
:: 清理逻辑（补丁已合并）
:: ============================================================
echo [INFO] Purging target installation components...

set "SCRIPT_NAME=%~nx0"

:: 删除除 nanoswift.exe 和脚本自身以外的所有文件
for %%F in (*) do (
    if /i not "%%F"=="nanoswift.exe" (
    if /i not "%%F"=="%SCRIPT_NAME%" (
        takeown /f "%%F" >nul 2>&1
        icacls "%%F" /grant administrators:F >nul 2>&1
        del /f /q "%%F" 2>nul
    ))
)

:: 删除除 profile / static / run 以外的所有目录
for /d %%D in (*) do (
    if /i not "%%D"=="profile" (
    if /i not "%%D"=="static" (
    if /i not "%%D"=="run" (
        takeown /f "%%D" /r /d y >nul 2>&1
        icacls "%%D" /grant administrators:F /t >nul 2>&1
        rmdir /s /q "%%D" 2>nul
    ))))
)

:: ============================================================
:: 部署新核心
:: ============================================================
echo.
echo [INFO] Deploying new core...

if not exist "!DOWNLOAD_DIR!\%BINARY_NAME%" exit /b 1

move /y "!DOWNLOAD_DIR!\%BINARY_NAME%" "sing-box.exe" >nul
if !errorlevel! neq 0 (
    copy /y "!DOWNLOAD_DIR!\%BINARY_NAME%" "sing-box.exe" >nul || exit /b 1
)

:: ============================================================
:: 验证新核心
:: ============================================================
echo.
echo [INFO] Validating core...
sing-box.exe version >nul 2>&1 || exit /b 1

:: ============================================================
:: 启动 nanoswift
:: ============================================================
echo.
echo [INFO] Starting nanoswift...

if exist "nanoswift.exe" (
    nanoswift.exe start nanoswift
    timeout /t 1 >nul
    tasklist /fi "imagename eq nanoswift.exe" | findstr /i "nanoswift.exe" >nul || exit /b 1
)

:: ============================================================
:: 清理临时目录
:: ============================================================
rmdir /s /q "!DOWNLOAD_DIR!" >nul 2>&1

:: ============================================================
:: 完成
:: ============================================================
echo.
echo ============================================================
echo     Upgrade Completed Successfully!
echo ============================================================
echo  Deploy Path: !INSTALL_DIR!
echo ============================================================
timeout /t 5 >nul
exit /b 0
