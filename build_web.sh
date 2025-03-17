#!/usr/bin/env bash

set -eou pipefail

ODIN_ROOT=$(odin root)

OUT_DIR="./build/web"

GAME_NAME="downstream"
EXE_NAME=$GAME_NAME

OS=$(uname)
START_PATH="$PWD"

SOKOL_ROOT="$START_PATH/src/third_party/sokol-odin/sokol"

case "$OS" in
  Linux)  SOKOL_SHDC_OS="linux" ;;
  Darwin) SOKOL_SHDC_OS="osx_arm64" ;;
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

# Compile Sokol WASM libraries
SOKOL_CLIBS_PATH="$SOKOL_ROOT/gfx/sokol_gfx_wasm_gl_release.a"

if [[ ! -f $SOKOL_CLIBS_PATH ]]; then
  echo "Sokol WASM libraries not built. Building them..."
  cd $SOKOL_ROOT
  ./build_clibs_wasm.sh
  cd $START_PATH
fi

$SOKOL_SHDC_PATH -i src/shaders/shader.glsl -o src/shaders/shader.glsl.odin -l glsl300es -f sokol_odin

# Build web release
rm -rf $OUT_DIR && mkdir -p $OUT_DIR && cd $OUT_DIR
odin build ../../src/main_web -out=$EXE_NAME -target:js_wasm32 -build-mode:obj -vet -o:speed -no-bounds-check -show-timings
# odin build ../../src/main_web -out=$EXE_NAME -target:js_wasm32 -build-mode:obj -vet -debug
cp ../../src/main_web/style.css .
cp ../../src/main_web/sfx.js .
for ogg in ../../src/assets/sounds/*.ogg; do
  if [ -f "$ogg" ]; then
    cp "$ogg" .
  fi
done
cp $ODIN_ROOT/core/sys/wasm/js/odin.js .

files="./$EXE_NAME.wasm.o $SOKOL_ROOT/app/sokol_app_wasm_gl_release.a $SOKOL_ROOT/glue/sokol_glue_wasm_gl_release.a $SOKOL_ROOT/log/sokol_log_wasm_gl_release.a $SOKOL_ROOT/gfx/sokol_gfx_wasm_gl_release.a $SOKOL_ROOT/audio/sokol_audio_wasm_gl_release.a $SOKOL_ROOT/debugtext/sokol_debugtext_wasm_gl_release.a"

flags="-sWASM_BIGINT -sWARN_ON_UNDEFINED_SYMBOLS=0 -sMAX_WEBGL_VERSION=2 -sASSERTIONS -sALLOW_MEMORY_GROWTH --shell-file ../../src/main_web/index.html"

emcc -o ./index.html $files $flags
# emcc -og ./index.html $files $flags

rm ./$EXE_NAME.wasm.o

if [ $# -ge 1 ] && [ $1 == "run" ]; then
  emrun --browser chrome ./index.html
fi
