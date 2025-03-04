#!/usr/bin/env bash

set -eou pipefail

OUT_DIR="./build/release"

GAME_NAME="odin-7-day-jam"

OS_NAME=$(uname -s)
OS_ARCH=$(uname -m)
START_PATH="$PWD"

SOKOL_ROOT="$START_PATH/src/third_party/sokol-odin/sokol"

case "$OS_NAME" in
  Linux)
    EXE_NAME=$GAME_NAME-Linux-x64
    SOKOL_SHDC_OS="linux"
    SOKOL_CLIBS_OS="linux"
    SOKOL_CLIBS_SUFFIX="x64_gl_release.so"
    ;;
  Darwin)
    SOKOL_CLIBS_OS="macos"
    case "$OS_ARCH" in
      arm64)
        EXE_NAME=$GAME_NAME-macOS-ARM64.bin
        SOKOL_SHDC_OS="osx_arm64"
        SOKOL_CLIBS_SUFFIX="arm64_metal_release.a"
        ;;
      *)
        EXE_NAME=$GAME_NAME-macOS-x64.bin
        SOKOL_SHDC_OS="osx"
        SOKOL_CLIBS_SUFFIX="x64_release.a"
        ;;
    esac
    ;;
  *) echo "Unsupported OS: $OS_NAME-$OS_ARCH" && exit 1
    ;;
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
SOKOL_CLIBS_PATH="$SOKOL_ROOT/gfx/sokol_gfx_${SOKOL_CLIBS_OS}_${SOKOL_CLIBS_SUFFIX}"

if [[ ! -f $SOKOL_CLIBS_PATH ]]; then
  echo "Sokol C libraries not built. Building them..."
  cd $SOKOL_ROOT
  ./build_clibs_${SOKOL_CLIBS_OS}.sh
  cd $START_PATH
fi

# Compile shaders with sokol-shdc
case "$OS_NAME" in
  Linux)  SHADER_LANG="glsl430"
    ;;
  Darwin) SHADER_LANG="metal_macos"
    ;;
  *) echo "Unsupported OS: $OS_NAME" && exit 1
    ;;
esac

$SOKOL_SHDC_PATH -i src/shaders/shader.glsl -o src/shaders/shader.glsl.odin -l "$SHADER_LANG" -f sokol_odin

# Build release
rm -rf $OUT_DIR && mkdir -p $OUT_DIR && cd $OUT_DIR
odin build ../../src/main_release -out=$EXE_NAME -vet -o:speed -no-bounds-check -show-timings
# odin build ../../src/main_release -out=$EXE_NAME -vet -o:speed -no-bounds-check -show-timings -define:USE_TRACKING_ALLOCATOR=true

if [ $# -ge 1 ] && [ $1 == "run" ]; then
  ./$EXE_NAME
fi
