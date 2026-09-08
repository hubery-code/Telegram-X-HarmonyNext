@echo off
REM ----------------------------------------------------------------------------
REM Hvigor thin wrapper (Windows variant, GOV-001).
REM Invokes the hvigor wrapper bundled with DevEco Studio instead of
REM downloading the engine from the network. Requires DevEco Studio and
REM the build node to be installed; adjust DEVECO_HOME below if needed.
REM Primary development host is macOS — this file exists for parity/CI.
REM ----------------------------------------------------------------------------
setlocal
set "DEVECO_HOME=C:\Program Files\Huawei\DevEco Studio"
if exist "%DEVECO_HOME%\tools\node\node.exe" (
  set "NODE=%DEVECO_HOME%\tools\node\node.exe"
) else (
  where node >nul 2>nul
  if errorlevel 1 (
    echo ERROR: no node found. Install DevEco Studio or node.
    exit /b 1
  )
  set "NODE=node"
)
if not defined DEVECO_SDK_HOME set "DEVECO_SDK_HOME=%DEVECO_HOME%\sdk\default\openharmony"
"%NODE%" "%DEVECO_HOME%\tools\hvigor\bin\hvigorw.js" %*
endlocal
