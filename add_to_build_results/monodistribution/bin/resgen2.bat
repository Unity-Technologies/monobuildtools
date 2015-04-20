@"%~dp0cli.bat" %MONO_OPTIONS% "%~dp0..\lib\mono\2.0\resgen.exe" %*
exit /b %ERRORLEVEL%
