@echo off
set MONO_PREFIX=%~dp0/..
set MONO=%MONO_PREFIX%/bin/mono
set MONO_PATH=%MONO_PREFIX%/lib/mono/2.0;%MONO_PREFIX%/lib/mono/3.5
set MONO_CFG_DIR=%MONO_PREFIX%/etc
"%MONO%" %*
