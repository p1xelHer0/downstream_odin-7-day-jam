package main_release

import "base:runtime"

import "core:log"
import "core:mem"
import "core:os"
import "core:os/os2"

import sapp "../third_party/sokol-odin/sokol/app"

import game ".."
import ta "../tracking_allocator"

_ :: mem
_ :: ta

USE_TRACKING_ALLOCATOR :: #config(USE_TRACKING_ALLOCATOR, false)

when USE_TRACKING_ALLOCATOR
{
  tracking_allocator: mem.Tracking_Allocator
}


logh: os.Handle
logh_err: os.Error

g_ctx: runtime.Context

main :: proc()
{
  exe_dir, exe_dir_err := os2.get_executable_directory(context.temp_allocator)
  if exe_dir_err == nil
  {
    os2.set_working_directory(exe_dir)
  }

  logger: log.Logger

  when USE_TRACKING_ALLOCATOR
  {
    mem.tracking_allocator_init(&tracking_allocator, context.allocator)
    context.allocator = mem.tracking_allocator(&tracking_allocator)

    logger = log.create_console_logger()
  }
  else
  {
    mode: int = 0
    when ODIN_OS == .Linux || ODIN_OS == .Darwin
    {
      mode = os.S_IRUSR | os.S_IWUSR | os.S_IRGRP | os.S_IROTH
    }

    logh, logh_err = os.open("log.txt", (os.O_CREATE | os.O_TRUNC | os.O_RDWR), mode)

    if logh_err == os.ERROR_NONE
    {
      os.stdout = logh
      os.stderr = logh
    }

    logger = logh_err == os.ERROR_NONE ? log.create_file_logger(logh) : log.create_console_logger()
  }

  context.logger = logger

  g_ctx = context

  app_desc, _ := game.game_app_desc()
  app_desc.init_cb = init
  app_desc.frame_cb = frame
  app_desc.event_cb = event
  app_desc.cleanup_cb = cleanup

  sapp.run(app_desc)

  free_all(context.temp_allocator)

  if logh_err == os.ERROR_NONE
  {
    log.destroy_file_logger(context.logger)
  }
  else
  {
    log.destroy_console_logger(context.logger)
  }

  when USE_TRACKING_ALLOCATOR
  {
    ta.tracking_allocator_end(&tracking_allocator)
  }
}

init :: proc "c" ()
{
  context = g_ctx

  when USE_TRACKING_ALLOCATOR
  {
    ta.tracking_allocator_reset(&tracking_allocator)
  }

  game.game_init()
}

frame :: proc "c" ()
{
  context = g_ctx

  game.game_frame()

  when USE_TRACKING_ALLOCATOR
  {
    ta.tracking_allocator_reset(&tracking_allocator)
  }
}

event :: proc "c" (event: ^sapp.Event)
{
  context = g_ctx

  game.game_event(event)

  when USE_TRACKING_ALLOCATOR
  {
    ta.tracking_allocator_reset(&tracking_allocator)
  }
}

cleanup :: proc "c" ()
{
  context = g_ctx

  game.game_cleanup()
}

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
