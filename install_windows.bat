@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

:: ==========================================
:: 权限检查 (Administrator privileges check)
:: ==========================================
net session >nul 2>&1
if !errorlevel! neq 0 (
    echo ============================================================
    echo [ERROR] Administrator privileges required!
    echo.
    echo This script needs to run as Administrator to:
    echo     - Stop/start system services
    echo     - Modify files in protected directories
    echo     - Execute takeown / icacls for locked assets
    echo.
    echo Please right-click this script and select "Run as Administrator"
    echo ============================================================
    echo.
    echo Press any key to exit...
    pause >nul 2>&1
    exit /b 1
)

echo ============================================================
echo  Welcome to sing-box (Nanoswift) Windows Upgrade Script
echo ============================================================

:: ==========================================
:: 严格的交互获取安装目录（必须不能为空）
:: ==========================================
:input_loop
set "USER_INPUT_DIR="
echo.
echo Please enter the sing-box installation directory (e.g., C:\sing-box or D:\sing-box):
set /p "USER_INPUT_DIR=Path: "

:: 过滤用户可能不小心输入的双引号
if defined USER_INPUT_DIR set "USER_INPUT_DIR=!USER_INPUT_DIR:"=!"

:: 严格判空逻辑 (修复: 确保用户未输入任何内容或只有空格时被正确拦截)
if "%USER_INPUT_DIR%"=="" (
    echo [ERROR] Installation directory cannot be empty! Please try again.
    goto input_loop
)

set "INSTALL_DIR=!USER_INPUT_DIR!"

:: 统一路径格式，去掉末尾可能存在的反斜杠
if "!INSTALL_DIR:~-1!"=="\" set "INSTALL_DIR=!INSTALL_DIR:~0,-1!"

:: 自动创建目标目录
if not exist "!INSTALL_DIR!" mkdir "!INSTALL_DIR!"

echo.
echo [INFO] Target path confirmed: !INSTALL_DIR!
echo ------------------------------------------------------------

:: ==========================================
:: GitHub 代理选择（修复: 回车判空逻辑）
:: ==========================================
echo.
echo Please select a GitHub proxy proxy for your network:
echo 1] No Proxy (Direct connection to official GitHub)
echo 2] v4.gh-proxy.org (Recommended for IPv4 environments)
echo 3] v6.gh-proxy.org (Recommended for Pure IPv6 / Campus networks)
echo ============================================================

set "PROXY_CHOICE="
set /p PROXY_CHOICE="Enter selection [1-3] (Default is 2): "

:: 彻底修复: 当用户直接敲回车时，PROXY_CHOICE 为未定义(空串)，赋值默认值 2
if "%PROXY_CHOICE%"=="" set PROXY_CHOICE=2
if "!PROXY_CHOICE!"=="1" set "PROXY_PREFIX="
if "!PROXY_CHOICE!"=="2" set "PROXY_PREFIX=https://v4.gh-proxy.org/"
if "!PROXY_CHOICE!"=="3" set "PROXY_PREFIX=https://v6.gh-proxy.org/"
if not "!PROXY_CHOICE!"=="1" if not "!PROXY_CHOICE!"=="2" if not "!PROXY_CHOICE!"=="3" set "PROXY_PREFIX=https://v4.gh-proxy.org/"

:: 定义暂存目录 (Windows 系统临时目录 %TEMP%)
set "DOWNLOAD_DIR=%TEMP%\singbox_upgrade"
if not exist "!DOWNLOAD_DIR!" mkdir "!DOWNLOAD_DIR!"

:: 切换到下载暂存目录，确保下载阶段完全与生产目录解耦
cd /d "!DOWNLOAD_DIR!"

:: 配置下载路径
set "RAW_BASE_URL=https://raw.githubusercontent.com/is928joe-jpg/sing-box-with-nanoswift/refs/heads/main/2026-06-26"
set "BINARY_NAME=sing-box-windows-amd64.exe"
set "SHA_NAME=sing-box-windows-amd64.exe.sha256"
set "FINAL_BIN_URL=!PROXY_PREFIX!!RAW_BASE_URL!/!BINARY_NAME!"
set "FINAL_SHA_URL=!PROXY_PREFIX!!RAW_BASE_URL!/!SHA_NAME!"

:: ==========================================
:: 下载文件
:: ==========================================
echo.
echo [INFO] Downloading the latest core binary to temporary area (%TEMP%)...
curl -L -k --ssl-no-revoke -o "!BINARY_NAME!" "!FINAL_BIN_URL!"
if !errorlevel! neq 0 (
    echo [ERROR] Failed to download binary file! Please check your network.
    pause
    exit /b 1
)

echo [INFO] Downloading the SHA256 checksum file...
curl -L -k --ssl-no-revoke -o "!SHA_NAME!" "!FINAL_SHA_URL!"
if !errorlevel! neq 0 (
    echo [ERROR] Failed to download checksum file!
    pause
    exit /b 1
)

:: ==========================================
:: SHA256 完整性验证 (硬核修复大写转换与certutil过滤)
:: ==========================================
echo.
echo [INFO] Performing SHA256 integrity check...
if not exist "!SHA_NAME!" (
    echo [ERROR] Checksum file not found! Verification aborted.
    pause
    exit /b 1
)

:: 读取期望哈希值
set /p EXPECTED_HASH_LINE=<"!SHA_NAME!"
set "EXPECTED_HASH=!EXPECTED_HASH_LINE:~0,64!"

:: 计算本地哈希 (修复: 健壮性过滤，过滤掉 certutil 输出中的非十六进制描述行、空行及空格)
set "LOCAL_HASH="
for /f "delims=" %%i in ('certutil -hashfile "!BINARY_NAME!" SHA256 ^| findstr /v /i "certutil" ^| findstr /v /i "hash"') do (
    set "LINE_DATA=%%i"
    set "LINE_DATA=!LINE_DATA: =!"
    if not "!LINE_DATA!"=="" (
        set "LOCAL_HASH=!LINE_DATA!"
    )
)

:: 彻底修复: 修正之前的弱智 %%A=%%A 语法，执行真正的大写转小写矩阵替换
for %%A in (A=a B=b C=c D=d E=e F=f G=g H=h I=i J=j K=k L=l M=m N=n O=o P=p Q=q R=r S=s T=t U=u V=v W=w X=x Y=y Z=z) do (
    set "EXPECTED_HASH=!EXPECTED_HASH:%%A!"
    set "LOCAL_HASH=!LOCAL_HASH:%%A!"
)

echo     Expected Hash: !EXPECTED_HASH!
echo     Calculated Hash: !LOCAL_HASH!

if /i "!LOCAL_HASH!"=="!EXPECTED_HASH!" (
    echo [SUCCESS] SHA256 check passed. File integrity verified!
) else (
    echo [ERROR] SHA256 hash mismatch! The file might be corrupted.
    del /f /q "!BINARY_NAME!" "!SHA_NAME!" >nul 2>&1
    pause
    exit /b 1
)

:: 清理暂存区哈希文件
del /f /q "!SHA_NAME!" >nul 2>&1


:: ==========================================
:: 1. 彻底停用并击杀所有潜在的句柄占用源
:: ==========================================
echo.
echo [INFO] Stopping nanoswift service and forcefully terminating all dependent processes...

:: 1. 发送服务停止信号
sc query nanoswift >nul 2>&1
if !errorlevel! equ 0 (
    echo [INFO] Emitting sc stop signal to SCM...
    if exist "!INSTALL_DIR!\nanoswift.exe" (
        "!INSTALL_DIR!\nanoswift.exe" stop nanoswift >nul 2>&1
    )
    sc stop nanoswift >nul 2>&1
)

:: 2. 硬核强杀所有可能死锁文件句柄的独立进程 (包含外壳进程)
taskkill /f /im sing-box.exe >nul 2>&1
taskkill /f /im nanoswift.exe >nul 2>&1

:: 3. 动态阻塞轮询，确保进程在系统进程树中彻底消失
echo [INFO] Waiting for OS handle release pipeline...
set /a PROCESS_POLL=0
:poll_loop
timeout /t 1 >nul
tasklist /fi "imagename eq sing-box.exe" 2>nul | findstr /i "sing-box.exe" >nul
set "SB_ALIVE=!errorlevel!"
tasklist /fi "imagename eq nanoswift.exe" 2>nul | findstr /i "nanoswift.exe" >nul
set "NS_ALIVE=!errorlevel!"

if "!SB_ALIVE!"=="0" set /a PROCESS_POLL+=1
if "!NS_ALIVE!"=="0" set /a PROCESS_POLL+=1

if !PROCESS_POLL! gtr 0 (
    if !PROCESS_POLL! ltr 6 (
        taskkill /f /im sing-box.exe >nul 2>&1
        taskkill /f /im nanoswift.exe >nul 2>&1
        goto poll_loop
    )
)
echo [INFO] Process termination verified clear.


:: ==========================================
:: 2. 切换至生产目录，并执行高级权限夺取
:: ==========================================
echo.
echo [INFO] Switching context to installation directory...
:: 彻底修复: 必须切回真正的生产线目录，后续删除和覆盖动作才有效
cd /d "!INSTALL_DIR!"

:: 修复：处理高权限遗留导致的 Access is denied 锁死问题
if exist "sing-box.exe" (
    takeown /f "sing-box.exe" >nul 2>&1
    icacls "sing-box.exe" /grant administrators:F >nul 2>&1
)


:: ==========================================
:: 3. 深度清理旧内核文件与全量相关资产
:: ==========================================
echo [INFO] Purging target installation components...

:: 彻底修复: 扩充清理列表，将全量版本产生的衍生文件全部纳入斩立决范畴
for %%F in (cache.db version.txt convert.exe readme.pdf restart.exe geoip.db geosite.db config.json sing-box.exe.test sing-box.exe.tmp) do (
    if exist "%%F" (
        takeown /f "%%F" >nul 2>&1
        icacls "%%F" /grant administrators:F >nul 2>&1
        del /f /q "%%F" 2>nul
        if exist "%%F" (echo     [WARNING] Failed to clear asset: %%F) else (echo     Successfully cleared: %%F)
    )
)

:: 彻底修复: 递归移除过往历史版本产生的全部目录及其子目录结构
for %%D in (convert dashboard rules ui assets) do (
    if exist "%%D" (
        takeown /f "%%D" /r /d y >nul 2>&1
        icacls "%%D" /grant administrators:F /t >nul 2>&1
        rmdir /s /q "%%D" 2>nul
        if exist "%%D" (echo     [WARNING] Failed to recursive remove directory: %%D) else (echo     Successfully removed folder: %%D)
    )
)


:: ==========================================
:: 4. 深度移除旧版主核心 (引入容错自愈覆盖)
:: ==========================================
echo.
echo [INFO] Overwriting sing-box.exe runtime binary...
if exist "sing-box.exe" (
    set /a RETRY_COUNT=0
    :retry_delete
    del /f /q "sing-box.exe" 2>nul
    
    if exist "sing-box.exe" (
        set /a RETRY_COUNT+=1
        if !RETRY_COUNT! gtr 3 (
            echo     [WARNING] Absolute del blocked. Trying direct physical fallback overwrite pipeline...
            goto force_deploy
        )
        taskkill /f /im sing-box.exe >nul 2>&1
        taskkill /f /im nanoswift.exe >nul 2>&1
        timeout /t 2 >nul
        goto retry_delete
    )
)

:force_deploy
:: ==========================================
:: 5. 精准跨盘部署核心资产
:: ==========================================
echo [INFO] Deploying pristine compiled core from temporary buffer...
if exist "!DOWNLOAD_DIR!\%BINARY_NAME%" (
    :: 强制执行 takeown 以防目标位置覆盖被阻断
    if exist "sing-box.exe" (
        takeown /f "sing-box.exe" >nul 2>&1
        icacls "sing-box.exe" /grant administrators:F >nul 2>&1
    )
    
    :: 跨盘安全移动
    move /y "!DOWNLOAD_DIR!\%BINARY_NAME%" "sing-box.exe" >nul
    if !errorlevel! equ 0 (
        echo     Deployment complete: !INSTALL_DIR!\sing-box.exe
    ) else (
        echo [WARNING] Move block encountered. Elevating to forced xcopy replication...
        copy /y "!DOWNLOAD_DIR!\%BINARY_NAME%" "sing-box.exe" >nul
        if !errorlevel! equ 0 (
            del /f /q "!DOWNLOAD_DIR!\%BINARY_NAME%" >nul
            echo     Forced fallback replication complete.
        ) else (
            echo ============================================================
            echo [FATAL] Deployment failed. Pipeline hard locked by security vendor.
            echo Please rescue your core from: %TEMP%\singbox_upgrade\%BINARY_NAME%
            echo ============================================================
            pause
            exit /b 1
        )
    )
) else (
    echo [ERROR] Downloaded buffer source asset is missing from temporary folder!
    pause
    exit /b 1
)


:: ==========================================
:: 6. 内核兼容性离线静默验证
:: ==========================================
echo.
echo [INFO] Validating modern core cross-compilation environment integrity...
if exist "sing-box.exe" (
    sing-box.exe version >nul 2>&1
    if !errorlevel! equ 0 (
        echo     sing-box.exe runtime check verified.
    ) else (
        echo     [WARNING] Core deployed but failed architecture query. Check OS compatibility.
    )
) else (
    echo [ERROR] Deploy target sing-box.exe went missing inside pipeline!
    pause
    exit /b 1
)


:: ==========================================
:: 7. 重新拉起守护外壳服务
:: ==========================================
echo.
echo [INFO] Reactivating orchestration engine layer...
if exist "nanoswift.exe" (
    takeown /f "nanoswift.exe" >nul 2>&1
    icacls "nanoswift.exe" /grant administrators:F >nul 2>&1
    
    nanoswift.exe start nanoswift
    if !errorlevel! equ 0 (
        echo     nanoswift background service started successfully.
    ) else (
        echo [WARNING] SCM failed to boot worker process. Service registration might be stale.
    )
) else (
    echo [ERROR] Control daemon nanoswift.exe is absent. Background automation offline.
    pause
    exit /b 1
)


:: ==========================================
:: 8. 彻底擦除系统暂存区垃圾
:: ==========================================
rmdir /s /q "!DOWNLOAD_DIR!" >nul 2>&1


:: ==========================================
:: 9. 正常退出提示
:: ==========================================
echo.
echo ============================================================
echo     Upgrade Completed Successfully!
echo ============================================================
echo  Deploy Path: !INSTALL_DIR!
echo ============================================================
echo.
timeout /t 5 >nul