@echo off
SETLOCAL
set MONO_PREFIX=%~dp0..
set MONO=%MONO_PREFIX%\bin\mono
set MONO_CFG_DIR=%MONO_PREFIX%\etc
"%MONO%" %*
exit /b %ERRORLEVEL%
ENDLOCAL
