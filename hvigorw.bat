@echo off
REM ----------------------------------------------------------------------------
REM Hvigor thin wrapper (Windows variant, GOV-001).
REM Invokes the hvigor wrapper bundled with DevEco Studio instead of
REM downloading the engine from the network. Requires DevEco Studio and
REM the build node to be installed.
REM PATH-PORTABLE-104 (2026-11-21): DEVECO_HOME must not be hardcoded to a
REM single drive -- hosts install DevEco on C: or D:; resolution order is
REM environment override -> drive candidates with node.exe probe -> bare dir.
REM The SDK home is the PARENT of the instance dir (matches the bash wrapper:
REM hvigor's SDK scanner expects <DEVECO_SDK_HOME>/<subdir>/sdk-pkg.json).
REM ----------------------------------------------------------------------------
setlocal
if defined DEVECO_HOME (
  if not exist "%DEVECO_HOME%\tools\node\node.exe" (
    echo WARN: DEVECO_HOME is set but node.exe not found there; probing drives.
    set "DEVECO_HOME="
  )
)
if not defined DEVECO_HOME if exist "C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" set "DEVECO_HOME=C:\Program Files\Huawei\DevEco Studio"
if not defined DEVECO_HOME if exist "D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" set "DEVECO_HOME=D:\Program Files\Huawei\DevEco Studio"
if not defined DEVECO_HOME if exist "C:\Program Files\Huawei\DevEco Studio" set "DEVECO_HOME=C:\Program Files\Huawei\DevEco Studio"
if not defined DEVECO_HOME if exist "D:\Program Files\Huawei\DevEco Studio" set "DEVECO_HOME=D:\Program Files\Huawei\DevEco Studio"
if not defined DEVECO_HOME (
  echo ERROR: DevEco Studio not found on C:/D: drives. Set DEVECO_HOME env var.
  exit /b 1
)
set "NODE=%DEVECO_HOME%\tools\node\node.exe"
if not exist "%NODE%" (
  where node >nul 2>nul
  if errorlevel 1 (
    echo ERROR: no node found. Install DevEco Studio or node.
    exit /b 1
  )
  set "NODE=node"
)
if not defined DEVECO_SDK_HOME set "DEVECO_SDK_HOME=%DEVECO_HOME%\sdk"
"%NODE%" "%DEVECO_HOME%\tools\hvigor\bin\hvigorw.js" %*
endlocal
