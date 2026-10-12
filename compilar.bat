@echo off
rem ============================================================
rem  CompiladorFreezeezyPeak - Compila la calculadora ASM
rem  Uso: doble clic en compilar.bat
rem  - Descarga FASM 1.73.35 automaticamente si falta
rem  - Ensambla calculadora.asm -> CalculadoraFreezeezyPeak.exe
rem ============================================================
chcp 65001 >nul
title Compilador FreezeezyPeak
cd /d "%~dp0"

set "SRC=calculadora.asm"
set "OUT=CalculadoraFreezeezyPeak.exe"
set "FASM_URL=https://flatassembler.net/fasmw17335.zip"
set "FASM_URL2=https://files.flatassembler.net/fasmw17335.zip"
set "FASM_DIR=%~dp0tools\FASM"
set "FASM_EXE=%FASM_DIR%\FASM.EXE"
set "FASM_ZIP=%~dp0tools\fasmw.zip"

echo.
echo  ===============================================
echo   Compilador FreezeezyPeak  (FASM + Win32 API)
echo  ===============================================
echo.

if not exist "%SRC%" (
  echo  [ERROR] No se encuentra "%SRC%" en esta carpeta.
  echo          Ejecuta este .bat junto a calculadora.asm
  pause
  exit /b 1
)

rem ---------- 1. Conseguir FASM ----------
if exist "%FASM_EXE%" goto :compilar

echo  [1/2] FASM no encontrado. Descargando FASM 1.73.35...
if not exist "%~dp0tools" mkdir "%~dp0tools"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "try { Invoke-WebRequest -Uri '%FASM_URL%' -OutFile '%FASM_ZIP%' -UseBasicParsing; exit 0 }" ^
  "catch { try { Invoke-WebRequest -Uri '%FASM_URL2%' -OutFile '%FASM_ZIP%' -UseBasicParsing; exit 0 } catch { exit 1 } }"
if errorlevel 1 (
  echo.
  echo  [ERROR] No se pudo descargar FASM.
  echo          Revisa tu conexion e intentalo de nuevo.
  echo          URL: %FASM_URL%
  pause
  exit /b 1
)

echo  [1/2] Descomprimiendo FASM...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "Expand-Archive -Path '%FASM_ZIP%' -DestinationPath '%FASM_DIR%\_tmp' -Force;" ^
  "$e = Get-ChildItem '%FASM_DIR%\_tmp' -Recurse -Filter FASM.EXE | Select-Object -First 1;" ^
  "if (-not $e) { exit 1 };" ^
  "$src = Split-Path $e.FullName;" ^
  "Copy-Item \"$src\*\" '%FASM_DIR%\' -Recurse -Force;" ^
  "Remove-Item '%FASM_DIR%\_tmp' -Recurse -Force;" ^
  "Remove-Item '%FASM_ZIP%' -Force -ErrorAction SilentlyContinue"
if errorlevel 1 (
  echo.
  echo  [ERROR] No se pudo descomprimir FASM.
  pause
  exit /b 1
)

if not exist "%FASM_EXE%" (
  echo.
  echo  [ERROR] FASM.EXE sigue sin aparecer en "%FASM_DIR%".
  pause
  exit /b 1
)
echo  [1/2] FASM listo: %FASM_EXE%
echo.

rem ---------- 2. Compilar ----------
:compilar
echo  [2/2] Ensamblando %SRC% ...
set "INCLUDE=%FASM_DIR%\INCLUDE;%INCLUDE%"
"%FASM_EXE%" "%SRC%" "%OUT%"
if errorlevel 1 (
  echo.
  echo  [ERROR] Fallo la compilacion. Revisa los mensajes de FASM.
  pause
  exit /b 1
)

echo.
echo  [OK] Compilacion correcta.
for %%F in ("%OUT%") do echo       EXE: %%~nxF  (%%~zF bytes)
echo       Ruta: %~dp0%OUT%
echo.
echo  Pulsa una tecla para ejecutar la calculadora o cierra esta ventana.
pause >nul
if exist "%OUT%" start "" "%OUT%"
exit /b 0
