#!/usr/bin/env bash

set -eou pipefail

RUNNING=false

OUT_DIR="./build/hot_reload"
EXE_NAME="game-hot-reload"

if pgrep -f $EXE_NAME > /dev/null; then
  RUNNING=true
fi

OS=$(uname)
PROJECT_ROOT="$PWD"

SOKOL_ROOT="$PROJECT_ROOT/src/third_party/sokol-odin/sokol"

case "$OS" in
  Linux)  SOKOL_SHDC_OS="linux" ;
    SOKOL_CLIBS_OS="linux" ;
    SOKOL_CLIBS_SUFFIX="x64_gl_release.so" ;
    DLL_EXTENSION=".so" ;;
  Darwin) SOKOL_SHDC_OS="osx_arm64" ;
    SOKOL_CLIBS_OS="macos_dylib" ;
    SOKOL_CLIBS_SUFFIX="arm64_metal_release.a" ;
    DLL_EXTENSION=".dylib" ;;
  *) echo "Unsupported OS: $OS" && exit 1 ;;
esac

SOKOL_SHDC_PATH="./bin/sokol-tools-bin/bin/${SOKOL_SHDC_OS}/sokol-shdc"

# Check for git submodule dependencies
# - sokol-odin: bindings to Sokol
# - sokol-shdc Shader-code-generator for sokol_gfx.h
if [[ ! -f "$SOKOL_ROOT/c/sokol.c" || ! -f $SOKOL_SHDC_PATH ]]; then
  echo "Submodules not initialized. Initializing and updating git submodules..."
  git submodule update --init --recursive
  chmod +x $SOKOL_SHDC_PATH
fi

# Compile Sokol C libraries
case "$OS" in
  Linux)  SOKOL_CLIBS_PATH="$SOKOL_ROOT/gfx/sokol_gfx_${SOKOL_CLIBS_OS}_${SOKOL_CLIBS_SUFFIX}" ;;
  Darwin) SOKOL_CLIBS_PATH="$SOKOL_ROOT/dylib/sokol_dylib_macos_arm64_metal_debug.dylib" ;;
  *) echo "Unsupported OS: $OS" && exit 1 ;;
esac

if [[ ! -f $SOKOL_CLIBS_PATH ]]; then
  echo "Sokol C libraries not built. Building them..."
  cd $SOKOL_ROOT
  ./build_clibs_${SOKOL_CLIBS_OS}.sh
  cd $PROJECT_ROOT
fi

# Compile shaders with sokol-shdc
case "$OS" in
  Linux)  SHADER_LANG="glsl430" ;;
  Darwin) SHADER_LANG="metal_macos" ;;
  *) echo "Unsupported OS: $OS" && exit 1 ;;
esac

$SOKOL_SHDC_PATH -i src/shaders/shader.glsl -o src/shaders/shader.glsl.odin -l "$SHADER_LANG" -f sokol_odin

# Build game DLL
if [[ ! $RUNNING = true ]]; then
  echo "First build, emptying ./build"
  rm -rf ./build
fi
mkdir -p $OUT_DIR && cd $OUT_DIR
odin build ../../src -out=game_tmp$DLL_EXTENSION -build-mode:dll -debug -define:SOKOL_DLL=true -define:HOT_RELOAD=true -use-single-module
mv ./game_tmp$DLL_EXTENSION ./game$DLL_EXTENSION

if [[ $RUNNING = true ]]; then
  echo "Hot reloading..."
  exit 0
fi

# Build hot reload EXE
cp -R $SOKOL_ROOT/dylib ./dylib
odin build ../../src/main_hot_reload -out:$EXE_NAME -debug -define:SOKOL_DLL=true -use-single-module

if [ $# -ge 1 ] && [ $1 == "run" ]; then
  echo "Running $EXE_NAME"
  ./$EXE_NAME
fi
