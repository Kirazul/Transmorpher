@echo off
echo ========================================
echo Building StealthMorpher DLL
echo ========================================
echo.

if not exist build mkdir build
cd build

echo Running CMake configuration...
cmake .. -DCMAKE_BUILD_TYPE=Release -A Win32
if %errorlevel% neq 0 (
    echo.
    echo ERROR: CMake configuration failed!
    echo Make sure you have CMake and a C++ compiler installed.
    exit /b 1
)

echo.
echo Building Release configuration...
cmake --build . --config Release
if %errorlevel% neq 0 (
    echo.
    echo ERROR: Build failed!
    exit /b 1
)

echo.
echo ========================================
echo Build completed successfully!
echo ========================================
echo.

copy Release\Release\dinput8.dll ..\dinput8.dll >nul 2>&1
if not exist ..\dinput8.dll copy Release\dinput8.dll ..\dinput8.dll >nul 2>&1

echo The compiled DLL has been copied to:
echo %~dp0dinput8.dll
echo.

REM ---- Auto-deploy to the WoW client (DLL + addon Lua) -------------------------
REM Override the game path by setting WOWDIR before running, e.g.:
REM    set "WOWDIR=D:\Games\WoW335" ^&^& build.bat
if "%WOWDIR%"=="" set "WOWDIR=C:\Users\KIRA\Desktop\world of warcraft 3.3.5a hd"

if exist "%WOWDIR%\Wow.exe" (
    echo Deploying to: %WOWDIR%
    copy /Y "%~dp0dinput8.dll" "%WOWDIR%\dinput8.dll" >nul 2>&1
    if errorlevel 1 (
        echo   [!] Could not replace dinput8.dll ^(is WoW running? close it and re-run^).
    ) else (
        echo   [OK] dinput8.dll deployed.
    )
    REM Mirror the addon Lua/TOC so in-game code matches the repo (Lua isn't locked).
    robocopy "%~dp0..\Transmorpher" "%WOWDIR%\Interface\AddOns\Transmorpher" /E /NFL /NDL /NJH /NJS /NP >nul 2>&1
    echo   [OK] Transmorpher addon synced to AddOns.
) else (
    echo WOWDIR not found ^(%WOWDIR%^) - copy %~dp0dinput8.dll to your WoW folder manually.
)
echo.
pause
