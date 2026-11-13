@echo off
setlocal enabledelayedexpansion
title CCTV Control Panel
color 0A

:: Navigate to project folder dynamically and ensure clean path without trailing slash
cd /d "%~dp0"
set "PROJ_DIR=%~dp0"
set "PROJ_DIR=%PROJ_DIR:~0,-1%"

:: Ensure project directory structure exists
if not exist "bin" mkdir bin
if not exist "tmp" mkdir tmp
if not exist "log" mkdir log

:: Handle CLI arguments (allows non-interactive SSH automation)
set "IS_CLI=0"
if not "%~1"=="" set "IS_CLI=1"
if /i "%1"=="--autostart" goto :auto_start
if /i "%1"=="--start" goto :cli_start
if /i "%1"=="--background" goto :cli_minimize
if /i "%1"=="--minimize" goto :cli_minimize
if /i "%1"=="--stop" goto :cli_stop
if /i "%1"=="--status" goto :cli_status
if /i "%1"=="--snapshot" goto :cli_snapshot
if /i "%1"=="--enable-autostart" goto :cli_enable_autostart
if /i "%1"=="--disable-autostart" goto :cli_disable_autostart

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
    echo   STATUS: [ RUNNING ] [PID: !PID!]
) else (
    echo   STATUS: [ STOPPED ]
)

:: Check autostart status
set "AUTOSTART_LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\CCTV_Autostart.lnk"
set "LEGACY_AUTOSTART_BAT=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\start_cctv.bat"
if exist "!AUTOSTART_LNK!" (
    echo   AUTOSTART: [ ENABLED ]
) else if exist "!LEGACY_AUTOSTART_BAT!" (
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
if "%choice%"=="0" (
    ping 127.0.0.1 -n 2 >nul 2>&1
    goto :menu
)
goto :menu

:: ==========================================
:: CLI Handlers for Headless / SSH control
:: ==========================================
:cli_status
call :check_running
if "!SERVER_RUNNING!"=="1" (
    echo CCTV Server is RUNNING [PID: !PID!]
    exit /b 0
) else (
    echo CCTV Server is STOPPED
    exit /b 1
)

:cli_start
call :check_running
if "!SERVER_RUNNING!"=="1" (
    echo CCTV Server is already running [PID: !PID!].
    exit /b 0
)
call :check_deps
if "!DEPS_OK!"=="0" exit /b 1
if exist tmp\stop.marker del tmp\stop.marker >nul 2>&1
start "CCTV_Server_Running" cmd /k ""!PYTHON_EXE!" bin\cctv.py"
call :wait_start
if "!SERVER_RUNNING!"=="1" (
    echo CCTV Server started [PID: !PID!].
    exit /b 0
) else (
    echo Failed to start CCTV Server.
    exit /b 1
)

:cli_minimize
call :check_running
if "!SERVER_RUNNING!"=="1" (
    echo CCTV Server is already running [PID: !PID!].
    exit /b 0
)
call :check_deps
if "!DEPS_OK!"=="0" exit /b 1
if exist tmp\stop.marker del tmp\stop.marker >nul 2>&1
:: ponytail: uses pythonw/WMI; if running as Windows Service across all sessions is needed, wrap with NSSM or WinSW.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow = [UInt16]0}; Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine = '\"!PYTHON_RUN_EXE!\" -u bin\cctv.py'; CurrentDirectory = '!PROJ_DIR!'; ProcessStartupInformation = $s}" >nul 2>&1
call :wait_start
if "!SERVER_RUNNING!"=="1" (
    echo CCTV Server started in background [PID: !PID!].
    exit /b 0
) else (
    echo Failed to start CCTV Server. Check log\cctv_console_err.log.
    exit /b 1
)

:cli_enable_autostart
call :do_enable_autostart
exit /b !AUTOSTART_RESULT!

:cli_disable_autostart
call :do_disable_autostart
exit /b 0

:cli_stop
call :stop_internal
exit /b 0

:cli_snapshot
call :check_running
if "!SERVER_RUNNING!"=="0" (
    echo Server is not running!
    exit /b 1
)
call :do_snapshot
exit /b 0

:start
call :check_running
if "!SERVER_RUNNING!"=="1" (
    echo.
    echo Server is already running! Please stop it first.
    ping 127.0.0.1 -n 3 >nul 2>&1
    goto :menu
)
call :check_deps
if "!DEPS_OK!"=="0" goto :menu

if exist tmp\stop.marker del tmp\stop.marker >nul 2>&1
echo Starting server...
start "CCTV_Server_Running" cmd /k ""!PYTHON_EXE!" bin\cctv.py"
call :wait_start
goto :menu

:minimize
call :check_running
if "!SERVER_RUNNING!"=="1" (
    echo.
    echo Server is already running! Please stop it first.
    ping 127.0.0.1 -n 3 >nul 2>&1
    goto :menu
)
call :check_deps
if "!DEPS_OK!"=="0" goto :menu

if exist tmp\stop.marker del tmp\stop.marker >nul 2>&1
echo Starting server completely hidden in the background...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow = [UInt16]0}; Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine = '\"!PYTHON_RUN_EXE!\" -u bin\cctv.py'; CurrentDirectory = '!PROJ_DIR!'; ProcessStartupInformation = $s}" >nul 2>&1
call :wait_start
goto :menu

:wait_start
set /a WAIT_TRIES=0
:wait_start_loop
ping 127.0.0.1 -n 2 >nul 2>&1
call :check_running
if "!SERVER_RUNNING!"=="1" goto :eof
set /a WAIT_TRIES+=1
if !WAIT_TRIES! lss 5 goto :wait_start_loop
goto :eof

:stop
echo.
call :stop_internal
goto :menu

:stop_internal
echo Stopping CCTV Server...
>tmp\stop.marker echo STOP

:: Wait up to 4 seconds for graceful shutdown
set /a STOP_TRIES=0
:wait_stop_loop
ping 127.0.0.1 -n 2 >nul 2>&1
call :check_running
if "!SERVER_RUNNING!"=="0" goto :stop_done
set /a STOP_TRIES+=1
if !STOP_TRIES! lss 4 goto :wait_stop_loop

:: Fallback kill if process did not exit gracefully
set PID=
if exist tmp\cctv.pid set /p PID=<tmp\cctv.pid
if not "%PID%"=="" (
    taskkill /F /PID !PID! /T >nul 2>&1
    del tmp\cctv.pid >nul 2>&1
)
taskkill /F /FI "WINDOWTITLE eq CCTV_Server_Running*" /T >nul 2>&1

:stop_done
if exist tmp\stop.marker del tmp\stop.marker >nul 2>&1
echo Server stopped.
ping 127.0.0.1 -n 2 >nul 2>&1
goto :eof

:snapshot
call :check_running
if "!SERVER_RUNNING!"=="0" (
    echo.
    echo Server is not running! Please start it first to take a snapshot.
    ping 127.0.0.1 -n 3 >nul 2>&1
    goto :menu
)
echo.
call :do_snapshot
ping 127.0.0.1 -n 3 >nul 2>&1
goto :menu

:do_snapshot
echo Taking snapshot...
set "TS=%DATE:/=-%_%TIME::=-%"
set "TS=!TS: =0!"
set "TS=!TS:,=-!"
set "SNAPSHOT_FILE=log\snapshot_!TS!.jpg"

where curl.exe >nul 2>&1
if !errorlevel! equ 0 (
    curl.exe -s -f -o "!SNAPSHOT_FILE!" "http://localhost:5000/snapshot"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'http://localhost:5000/snapshot' -OutFile '!SNAPSHOT_FILE!' -UseBasicParsing" >nul 2>&1
)

if exist "!SNAPSHOT_FILE!" (
    echo Snapshot saved to !SNAPSHOT_FILE!
    if not "!IS_CLI!"=="1" start "" "!SNAPSHOT_FILE!"
) else (
    echo Failed to take snapshot. Check server logs.
)
goto :eof

:log
if exist log\cctv_server.log (
    start notepad log\cctv_server.log
) else (
    echo.
    echo No logs found! Start the server in Hidden mode to generate logs.
    ping 127.0.0.1 -n 3 >nul 2>&1
)
goto :menu

:enable_autostart
call :do_enable_autostart
ping 127.0.0.1 -n 3 >nul 2>&1
goto :menu

:disable_autostart
call :do_disable_autostart
ping 127.0.0.1 -n 3 >nul 2>&1
goto :menu

:do_enable_autostart
set "AUTOSTART_LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\CCTV_Autostart.lnk"
set "LEGACY_AUTOSTART_BAT=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\start_cctv.bat"
if exist "!AUTOSTART_LNK!" (
    echo.
    echo Autostart is already ENABLED.
    set AUTOSTART_RESULT=0
    goto :eof
)
call :resolve_python
if not defined PYTHON_EXE (
    echo.
    echo [ERROR] Python not found. Cannot configure autostart.
    set AUTOSTART_RESULT=1
    goto :eof
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $sc = $ws.CreateShortcut('!AUTOSTART_LNK!'); $sc.TargetPath = '!PYTHON_RUN_EXE!'; $sc.Arguments = 'bin\cctv.py'; $sc.WorkingDirectory = '!PROJ_DIR!'; $sc.WindowStyle = 7; $sc.Save()" >nul 2>&1
if exist "!AUTOSTART_LNK!" (
    if exist "!LEGACY_AUTOSTART_BAT!" del "!LEGACY_AUTOSTART_BAT!" >nul 2>&1
    echo.
    echo Autostart ENABLED. Server will start silently in background on next Windows login.
    set AUTOSTART_RESULT=0
) else (
    echo.
    echo Failed to enable autostart. Check folder permissions.
    set AUTOSTART_RESULT=1
)
goto :eof

:do_disable_autostart
set "AUTOSTART_LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\CCTV_Autostart.lnk"
set "LEGACY_AUTOSTART_BAT=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\start_cctv.bat"
set REMOVED=0
if exist "!AUTOSTART_LNK!" (
    del "!AUTOSTART_LNK!" >nul 2>&1
    set REMOVED=1
)
if exist "!LEGACY_AUTOSTART_BAT!" (
    del "!LEGACY_AUTOSTART_BAT!" >nul 2>&1
    set REMOVED=1
)
if "!REMOVED!"=="1" (
    echo.
    echo Autostart DISABLED. Server will no longer start on login.
) else (
    echo.
    echo Autostart is already DISABLED.
)
goto :eof

:auto_start
:: Executed ONLY when triggered by Windows Startup
call :check_running
if "!SERVER_RUNNING!"=="1" exit /b

if not exist "bin" mkdir bin
if not exist "tmp" mkdir tmp
if not exist "log" mkdir log

if exist tmp\stop.marker del tmp\stop.marker >nul 2>&1
call :resolve_python
if not defined PYTHON_EXE exit /b

powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow = [UInt16]0}; Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine = '\"!PYTHON_RUN_EXE!\" -u bin\cctv.py'; CurrentDirectory = '!PROJ_DIR!'; ProcessStartupInformation = $s}" >nul 2>&1
exit /b

:exit
exit /b


:: ==========================================
:: Subroutine: resolve Python executable
:: ==========================================
:resolve_python
set "PYTHON_EXE="
set "PYTHONW_EXE="
:: 1. Search PATH for valid python.exe (excluding broken WindowsApps alias)
for /f "delims=" %%I in ('where.exe python.exe 2^>nul') do (
    if not defined PYTHON_EXE (
        "%%I" -c "import sys; sys.exit(0)" >nul 2>&1
        if !errorlevel! equ 0 set "PYTHON_EXE=%%I"
    )
)
:: 2. Search py launcher
if not defined PYTHON_EXE (
    where.exe py.exe >nul 2>&1
    if !errorlevel! equ 0 (
        py.exe -3 -c "import sys; sys.exit(0)" >nul 2>&1
        if !errorlevel! equ 0 set "PYTHON_EXE=py.exe"
    )
)
:: 3. Check standard Python installation directories if PATH is missing Python
if not defined PYTHON_EXE (
    for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python3*") do (
        if exist "%%D\python.exe" if not defined PYTHON_EXE (
            "%%D\python.exe" -c "import sys; sys.exit(0)" >nul 2>&1
            if !errorlevel! equ 0 set "PYTHON_EXE=%%D\python.exe"
        )
    )
)
if not defined PYTHON_EXE (
    for /d %%D in ("%ProgramFiles%\Python3*") do (
        if exist "%%D\python.exe" if not defined PYTHON_EXE (
            "%%D\python.exe" -c "import sys; sys.exit(0)" >nul 2>&1
            if !errorlevel! equ 0 set "PYTHON_EXE=%%D\python.exe"
        )
    )
)

:: Resolve pythonw.exe for windowless background execution
if defined PYTHON_EXE (
    set "CANDIDATE_W=!PYTHON_EXE:python.exe=pythonw.exe!"
    if exist "!CANDIDATE_W!" set "PYTHONW_EXE=!CANDIDATE_W!"
)
if not defined PYTHONW_EXE (
    for /f "delims=" %%I in ('where.exe pythonw.exe 2^>nul') do (
        if not defined PYTHONW_EXE set "PYTHONW_EXE=%%I"
    )
)
if defined PYTHONW_EXE (
    set "PYTHON_RUN_EXE=!PYTHONW_EXE!"
) else (
    set "PYTHON_RUN_EXE=!PYTHON_EXE!"
)
goto :eof


:: ==========================================
:: Subroutine: verify Python and dependencies
:: ==========================================
:check_deps
set DEPS_OK=1
call :resolve_python
if not defined PYTHON_EXE (
    echo.
    echo [ERROR] Python not found or points to Microsoft Store alias.
    echo Please install Python 3.9+ and ensure 'Add Python to PATH' is checked.
    set DEPS_OK=0
    if not "!IS_CLI!"=="1" pause
    goto :eof
)
"%PYTHON_EXE%" -c "import flask, cv2" >nul 2>&1
if !errorlevel! neq 0 (
    echo.
    echo [ERROR] Required dependencies are missing!
    echo Please run: pip install flask opencv-python
    set DEPS_OK=0
    if not "!IS_CLI!"=="1" pause
    goto :eof
)
goto :eof


:: ==========================================
:: Subroutine: check if server process is alive
:: Sets SERVER_RUNNING=1 if alive, 0 if not
:: ==========================================
:check_running
set SERVER_RUNNING=0
set PID=
if not exist tmp\cctv.pid goto :eof
set /p PID=<tmp\cctv.pid
if "%PID%"=="" goto :eof

:: Fast native Windows tasklist check (15ms, no PowerShell overhead)
tasklist /FI "PID eq !PID!" /NH 2>nul | findstr /i "python" >nul
if !errorlevel! equ 0 (
    set SERVER_RUNNING=1
) else (
    del tmp\cctv.pid >nul 2>&1
)
goto :eof
