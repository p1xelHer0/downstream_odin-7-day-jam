package main_web

import "base:runtime"

import "core:log"

import sapp "../third_party/sokol-odin/sokol/app"

import game ".."

g_ctx: runtime.Context

main :: proc()
{
  context.allocator = emscripten_allocator()
  runtime.init_global_temporary_allocator(1 * runtime.Megabyte)

  context.logger = log.create_console_logger(lowest = .Info, opt = {.Level, .Short_File_Path, .Line, .Procedure})

  g_ctx = context

  app_desc, _ := game.game_app_desc()
  app_desc.init_cb = init
  app_desc.frame_cb = frame
  app_desc.event_cb = event
  app_desc.cleanup_cb = cleanup
  app_desc.html5_update_document_title = true

  sapp.run(app_desc)

  free_all(context.temp_allocator)
}

init :: proc "c" ()
{
  context = g_ctx

  game.game_init()
}

frame :: proc "c" ()
{
  context = g_ctx

  game.game_frame()
}

event :: proc "c" (event: ^sapp.Event)
{
  context = g_ctx

  game.game_event(event)
}

cleanup :: proc "c" ()
{
  context = g_ctx

  game.game_cleanup()

  log.destroy_console_logger(context.logger)
}

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
