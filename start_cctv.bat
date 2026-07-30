@echo off
setlocal enabledelayedexpansion
title CCTV Control Panel
color 0A

:: Navigate to project folder first
cd /d "C:\CCTV"

:: Ensure project directory structure exists
if not exist "bin" mkdir bin
if not exist "tmp" mkdir tmp
if not exist "log" mkdir log


:: Detect if running from Windows Startup folder
echo "%~dp0" | find /I "Startup" >nul
if %errorlevel% equ 0 goto :auto_start

:menu
cls
echo ==========================================
echo       CCTV SERVER CONTROL PANEL
echo ==========================================
echo.
:: Check server status
call :check_running
if "!SERVER_RUNNING!"=="1" (
    echo   STATUS: [ RUNNING ]
) else (
    echo   STATUS: [ STOPPED ]
)
:: Check autostart status
set AUTOSTART_FILE=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\start_cctv.bat
if exist "%AUTOSTART_FILE%" (
    echo   AUTOSTART: [ ENABLED ]
) else (
    echo   AUTOSTART: [ DISABLED ]
)
echo.
echo ==========================================
echo   1. Start CCTV Server (Normal)
echo   2. Start CCTV Server (Background)
echo   3. Stop CCTV Server
echo   4. Take Snapshot (Photo)
echo   5. Enable Autostart
echo   6. Disable Autostart
echo   7. View Logs
echo   8. Exit
echo ==========================================
echo.
echo (Press ENTER without command to refresh STATUS)
set choice=0
set /p choice="Select an option (1-8): "

if "%choice%"=="1" goto :start
if "%choice%"=="2" goto :minimize
if "%choice%"=="3" goto :stop
if "%choice%"=="4" goto :snapshot
if "%choice%"=="5" goto :enable_autostart
if "%choice%"=="6" goto :disable_autostart
if "%choice%"=="7" goto :log
if "%choice%"=="8" goto :exit
if "%choice%"=="0" goto :menu
goto :menu

:start
call :check_running
if "!SERVER_RUNNING!"=="1" (
    echo.
    echo Server is already running! Please stop it first.
    timeout /t 2 >nul
    goto :menu
)
if exist tmp\stop.marker del tmp\stop.marker
echo Starting server...
start "CCTV_Server_Running" cmd /c "python bin\cctv.py"
:: Wait briefly for PID file to be created
timeout /t 2 >nul
goto :menu

:minimize
call :check_running
if "!SERVER_RUNNING!"=="1" (
    echo.
    echo Server is already running! Please stop it first.
    timeout /t 2 >nul
    goto :menu
)
if exist tmp\stop.marker del tmp\stop.marker
echo Starting server completely hidden in the background...
:: Start process via PowerShell BackgroundJob (bulletproof for Windows backgrounding, immune to SSH restriction)
powershell -Command "Start-Process python -ArgumentList '-u bin\cctv.py' -RedirectStandardOutput 'log\cctv_console_out.log' -RedirectStandardError 'log\cctv_console_err.log' -WindowStyle Hidden"
:: Wait briefly for PID file to be created
timeout /t 2 >nul
goto :menu

:stop
echo.
echo Stopping CCTV Server...
>tmp\stop.marker echo STOP
:: Wait up to 3 seconds for graceful shutdown
timeout /t 3 >nul

set PID=
if exist tmp\cctv.pid set /p PID=<tmp\cctv.pid
if not "%PID%"=="" (
    taskkill /F /PID !PID! /T >nul 2>&1
    del tmp\cctv.pid >nul 2>&1
)
:: Fallback brute-force to kill any orphaned processes on Windows 11
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | ? { $_.CommandLine -match 'cctv\.py' } | Invoke-CimMethod -MethodName Terminate" >nul 2>&1
taskkill /F /FI "WINDOWTITLE eq CCTV_Server_Running*" /T >nul 2>&1
if exist tmp\stop.marker del tmp\stop.marker
timeout /t 1 >nul
goto :menu

:snapshot
call :check_running
if "!SERVER_RUNNING!"=="0" (
    echo.
    echo Server is not running! Please start it first to take a snapshot.
    timeout /t 2 >nul
    goto :menu
)
echo.
echo Taking snapshot...
set SNAPSHOT_FILE=log\snapshot_!date:/=-!_!time::=-!.jpg
set SNAPSHOT_FILE=!SNAPSHOT_FILE: =0!
powershell -Command "Invoke-WebRequest -Uri 'http://localhost:5000/snapshot' -OutFile '!SNAPSHOT_FILE!' -ErrorAction Stop" >nul 2>&1
if !errorlevel! equ 0 (
    echo Snapshot saved to !SNAPSHOT_FILE!
    start "" "!SNAPSHOT_FILE!"
) else (
    echo Failed to take snapshot. Check server logs.
)
timeout /t 2 >nul
goto :menu

:log
if exist log\cctv_server.log (
    start notepad log\cctv_server.log
) else (
    echo.
    echo No logs found! Start the server in Hidden mode to generate logs.
    timeout /t 2 >nul
)
goto :menu

:enable_autostart
set AUTOSTART_FILE=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\start_cctv.bat
if exist "%AUTOSTART_FILE%" (
    echo.
    echo Autostart is already ENABLED.
    timeout /t 2 >nul
    goto :menu
)
copy "%~f0" "%AUTOSTART_FILE%" >nul
if errorlevel 1 (
    echo.
    echo Failed to enable autostart. Check folder permissions.
) else (
    echo.
    echo Autostart ENABLED. Server will start hidden on next Windows login.
)
timeout /t 2 >nul
goto :menu

:disable_autostart
set AUTOSTART_FILE=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\start_cctv.bat
if not exist "%AUTOSTART_FILE%" (
    echo.
    echo Autostart is already DISABLED.
    timeout /t 2 >nul
    goto :menu
)
del "%AUTOSTART_FILE%" >nul
if errorlevel 1 (
    echo.
    echo Failed to disable autostart. Check folder permissions.
) else (
    echo.
    echo Autostart DISABLED. Server will no longer start on login.
)
timeout /t 2 >nul
goto :menu

:auto_start
:: Executed ONLY if launched by Windows Startup
call :check_running
if "!SERVER_RUNNING!"=="1" exit

if not exist "bin" mkdir bin
if not exist "tmp" mkdir tmp
if not exist "log" mkdir log

if exist tmp\stop.marker del tmp\stop.marker
powershell -Command "Start-Process python -ArgumentList '-u bin\cctv.py' -RedirectStandardOutput 'log\cctv_console_out.log' -RedirectStandardError 'log\cctv_console_err.log' -WindowStyle Hidden"
exit

:exit
exit


:: ==========================================
:: Subroutine: check if server process is alive
:: Sets SERVER_RUNNING=1 if alive, 0 if not
:: Works on Win 7/10/11 regardless of Python exe name
:: ==========================================
:check_running
set SERVER_RUNNING=0
set PID=
if not exist tmp\cctv.pid goto :eof
set /p PID=<tmp\cctv.pid
if "%PID%"=="" goto :eof
:: Use tasklist with exact PID filter; check if PID appears in output
tasklist /FI "PID eq %PID%" /NH 2>nul | findstr /I "%PID%" >nul 2>&1
if !errorlevel! equ 0 (
    set SERVER_RUNNING=1
) else (
    :: PID is dead, cleanup
    del tmp\cctv.pid >nul 2>&1
)
goto :eof

