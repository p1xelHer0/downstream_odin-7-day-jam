@echo off
setlocal

set OUT_DIR=.\build\release

set GAME_NAME=odin-7-day-jam
set EXE_NAME=%GAME_NAME%-Win-x64.exe

set SOKOL_ROOT=.\src\third_party\sokol-odin\sokol
set SOKOL_SHDC_PATH=.\bin\sokol-tools-bin\bin\win32\sokol-shdc.exe

REM Check for git submodule dependencies
REM - sokol-odin: bindings to Sokol
REM - sokol-shdc Shader-code-generator for sokol_gfx.h
if not exist %SOKOL_ROOT%\c\sokol.c (
  echo Submodules not initialized. Initializing and updating git submodules...
  git submodule update --init --recursive
  icacls %SOKOL_SHDC_PATH% /grant "%USERNAME%:F"
)

REM Compile Sokol C libraries
if not exist %SOKOL_ROOT%\gfx\sokol_gfx_windows_x64_d3d11_release.lib (
  echo Sokol C libraries not built. Building them...
  pushd %SOKOL_ROOT%
  cmd /c build_clibs_windows
  popd
)

REM Compile shaders with sokol-shdc
%SOKOL_SHDC_PATH% -i src\shaders\shader.glsl -o src\shaders\shader.glsl.odin -l hlsl5 -f sokol_odin

REM Build it
if not exist %OUT_DIR% mkdir %OUT_DIR%
pushd %OUT_DIR%
odin.exe build ..\..\src\main_release -out:%EXE_NAME% -vet -o:speed -no-bounds-check -show-timings -subsystem:windows

endlocal
