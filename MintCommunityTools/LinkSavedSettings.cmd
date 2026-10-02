@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem One-time fix for the WoW Forever beta bug where the client writes addon data but never
rem loads them again. It links the game's MintCommunityTools save file into the addon as Saved.lua, which
rem the client does load.
rem
rem Run it once, with the game closed, after the addon has saved at least once (log in with it
rem enabled, then /exit). Windows only lets file links be made from an administrator prompt or
rem with Developer Mode on, so right-click this file and choose "Run as administrator".
rem It finds the game folder from its own location, so run the copy that is installed in
rem   <World of Warcraft>\_classic_beta_\Interface\AddOns\MintCommunityTools\
rem
rem Once Blizzard fixes the loader the real settings load after Saved.lua and take over.

set "ADDON=%~dp0"
set "ADDON=%ADDON:~0,-1%"
for %%I in ("%ADDON%\..\..\..") do set "GAME=%%~fI"

if not exist "%GAME%\WTF\Account\" (
    echo Could not find the game's WTF folder above:
    echo   !ADDON!
    echo Run the copy of this file that is inside Interface\AddOns\MintCommunityTools in the game folder.
    pause
    exit /b 1
)

set "SAVE="
for /f "delims=" %%F in ('dir /b /s /o-d "%GAME%\WTF\Account\MintCommunityTools.lua" 2^>nul') do (
    if not defined SAVE set "SAVE=%%F"
)
if not defined SAVE (
    echo No MintCommunityTools.lua save found under !GAME!\WTF\Account.
    echo Log in with the addon enabled, type /exit, then run this again.
    pause
    exit /b 1
)

if exist "%ADDON%\Saved.lua" del "%ADDON%\Saved.lua"
mklink "%ADDON%\Saved.lua" "%SAVE%"
if errorlevel 1 (
    echo.
    echo Could not make the link. Right-click this file and choose "Run as administrator",
    echo or turn on Developer Mode in Windows Settings ^(Privacy ^& security ^> For developers^).
    pause
    exit /b 1
)

echo.
echo Linked Saved.lua to your save file:
echo   %SAVE%
echo Start the game: the login line should say the saved data was restored from the linked save file.
pause
