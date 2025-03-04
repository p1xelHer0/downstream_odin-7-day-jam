package main_hot_reload

import "base:runtime"

import "core:c/libc"
import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os/os2"
import "core:path/filepath"
import "core:time"

import sapp "../third_party/sokol-odin/sokol/app"

import ta "../tracking_allocator"

when ODIN_OS == .Windows
{
  DLL_EXT :: ".dll"
}
else when ODIN_OS == .Darwin
{
  DLL_EXT :: ".dylib"
}
else
{
  DLL_EXT :: ".so"
}

GAME_DLL_DIR :: "./"
GAME_DLL_PATH :: GAME_DLL_DIR + "game" + DLL_EXT

Game_DLL :: struct
{
  __handle:          dynlib.Library,
  init:              proc(),
  app_desc:          proc() -> sapp.Desc,
  frame:             proc(),
  event:             proc(event: ^sapp.Event),
  cleanup:           proc(),
  mem:               proc() -> rawptr,
  size_of_mem:       proc() -> int,
  hot_reloaded:      proc(mem: rawptr),
  modification_time: time.Time,
  generation:        int,
}

g_ctx: runtime.Context
tracking_allocator: mem.Tracking_Allocator

game_dll: Game_DLL
old_game_dlls: [dynamic]Game_DLL
game_dll_generation: int

copy_dll :: proc(to: string) -> bool
{
  copy_err := os2.copy_file(to, GAME_DLL_PATH)

  if copy_err != nil
  {
    log.errorf("Failed to copy " + GAME_DLL_PATH + " to {0}: %v", to, copy_err)
    return false
  }

  return true
}

load_game_dll :: proc(generation: int) -> (dll: Game_DLL, ok: bool)
{
  mod_time, mod_time_error := os2.modification_time_by_path(GAME_DLL_PATH)
  if mod_time_error != os2.ERROR_NONE
  {
    log.errorf("Failed getting last write time of " + GAME_DLL_PATH + ", error code: {1}", mod_time_error)
    return
  }

  game_dll_name := fmt.tprintf(GAME_DLL_DIR + "game_{0}" + DLL_EXT, generation)
  copy_dll(game_dll_name) or_return

  _, ok = dynlib.initialize_symbols(&dll, game_dll_name, "game_")
  if !ok
  {
    log.errorf("Failed initializing symbols: {0}", dynlib.last_error())
  }

  dll.generation = generation
  dll.modification_time = mod_time
  ok = true

  return
}

unload_game_dll :: proc(dll: ^Game_DLL)
{
  if dll.__handle != nil
  {
    if !dynlib.unload_library(dll.__handle)
    {
      log.errorf("Failed unloading lib: {0}", dynlib.last_error())
    }
  }

  if os2.remove(fmt.tprintf(GAME_DLL_DIR + "game_{0}" + DLL_EXT, dll.generation)) != nil
  {
    log.errorf("Failed to remove {0}game_{1}" + DLL_EXT + " copy", GAME_DLL_DIR, dll.generation)
  }
}

main :: proc()
{
  exe_dir, exe_dir_err := os2.get_executable_directory(context.temp_allocator)
  if exe_dir_err == nil
  {
    os2.set_working_directory(exe_dir)
  }

  context.logger = log.create_console_logger()

  mem.tracking_allocator_init(&tracking_allocator, context.allocator)
  context.allocator = mem.tracking_allocator(&tracking_allocator)

  g_ctx = context

  game_dll_ok: bool
  game_dll, game_dll_ok = load_game_dll(game_dll_generation)
  if !game_dll_ok
  {
    log.errorf("Failed to load Game API")
    return
  }

  game_dll_generation += 1
  old_game_dlls = make([dynamic]Game_DLL)

  app_desc := game_dll.app_desc()
  app_desc.init_cb = init
  app_desc.frame_cb = frame
  app_desc.event_cb = event
  app_desc.cleanup_cb = cleanup

  sapp.run(app_desc)

  free_all(context.temp_allocator)
}

init :: proc "c" ()
{
  context = g_ctx

  ta.tracking_allocator_reset(&tracking_allocator)

  game_dll.init()
}

frame :: proc "c" ()
{
  context = g_ctx

  reload := false
  game_dll_mod, game_dll_mod_err := os2.modification_time_by_path(GAME_DLL_PATH)
  if game_dll_mod_err == os2.ERROR_NONE && game_dll.modification_time != game_dll_mod
  {
    reload = true
  }

  if reload
  {
    new_game_dll, new_game_dll_ok := load_game_dll(game_dll_generation)

    if new_game_dll_ok
    {
      force_quit := new_game_dll.size_of_mem() != game_dll.size_of_mem()

      if !force_quit
      {
        log.debug("HOT RELOAD")

        append(&old_game_dlls, game_dll)
        game_memory := game_dll.mem()

        game_dll = new_game_dll
        game_dll.hot_reloaded(game_memory)
      }
      else
      {
        log.debug("RESTART")

        game_dll.cleanup()

        ta.tracking_allocator_reset(&tracking_allocator)

        for &g in old_game_dlls {
          unload_game_dll(&g)
        }
        clear(&old_game_dlls)

        unload_game_dll(&game_dll)

        // FIXME: make this work?
        // game_dll = new_game_dll
        // game_dll.init()
        os2.exit(1)
      }

      game_dll_generation += 1
    }
  }

  game_dll.frame()

  ta.tracking_allocator_reset(&tracking_allocator)
}

event :: proc "c" (event: ^sapp.Event)
{
  context = g_ctx

  game_dll.event(event)

  ta.tracking_allocator_reset(&tracking_allocator)
}

cleanup :: proc "c" ()
{
  context = g_ctx

  game_dll.cleanup()
  unload_game_dll(&game_dll)

  for &g in old_game_dlls
  {
    unload_game_dll(&g)
  }
  delete(old_game_dlls)

  ta.tracking_allocator_end(&tracking_allocator)
}

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
