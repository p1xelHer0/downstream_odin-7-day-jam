package game

import "core:fmt"
import "core:time"

import sapp "third_party/sokol-odin/sokol/app"
import sdtx "third_party/sokol-odin/sokol/debugtext"
import sg "third_party/sokol-odin/sokol/gfx"
import sglue "third_party/sokol-odin/sokol/glue"
import slog "third_party/sokol-odin/sokol/log"

import "assets"
import "shaders"

Game_Mem :: struct
{
  RENDERER: GFX_Renderer,
  TIMER:    Timer,
  INPUT:    Input,
  GAME:     Game,
}

Key :: enum
{
  NONE,
  UP,
  DOWN,
  LEFT,
  RIGHT,
  SPACE,
}

Input :: struct
{
  key_current: Maybe(Key),
  keys:        bit_set[Key],
}

Timer :: struct
{
  tick:        u64,
  elapsed:     f64,
  current:     time.Time,
  accumulator: f64,
}

TICK     :: 1.0 / 60.0
TICK_MAX :: 0.25

GAME_WIDTH  :: f32(320)
GAME_HEIGHT :: f32(180)

HOT_RELOAD :: #config(HOT_RELOAD, false) && ODIN_DEBUG

G: ^Game_Mem

@(export)
game_app_desc :: proc() -> sapp.Desc
{
  window_title: cstring = "hot!" when HOT_RELOAD else "game"

  return {
    width = 320,
    height = 180,
    sample_count = 4,
    window_title = window_title,
    icon = { sokol_default = true },
    logger = { func = slog.func },
    high_dpi = true,
  }
}

@(export)
game_init :: proc()
{
  G = new(Game_Mem)

  G.TIMER.elapsed = 0
  G.TIMER.current = time.now()

  sg.setup({
    environment = sglue.environment(),
    logger = { func = slog.func },
    buffer_pool_size = BUDGET_BUFFER_POOL,
    image_pool_size = BUDGET_IMAGE_POOL,
    sampler_pool_size = BUDGET_SAMPLER_POOL,
    shader_pool_size = BUDGET_SHADER_POOL,
    pipeline_pool_size = BUDGET_PIPELINE_POOL,
    attachments_pool_size = BUDGET_ATTACHMENT_POOL,
  })

  sdtx.setup({
    fonts = sdtx.font_oric(),
    logger = { func = slog.func },
  })

  gfx_init_success := gfx_init(&G.RENDERER)
  if !gfx_init_success
  {
    fmt.eprintfln("failed to init gfx")
    return
  }

  sfx_init_success := sfx_init()
  if !sfx_init_success
  {
    fmt.eprintfln("failed to init sfx")
    return
  }

  start_level(idx = 2, game = &G.GAME)

  when HOT_RELOAD
  {
    game_hot_reloaded(G)
  }
}

@(export)
game_frame :: proc()
{
  defer free_all(context.temp_allocator)

  // Timers
  @(static)
  timer_tick := TICK

  new_time := time.now()
  frame_time := time.duration_seconds(time.diff(G.TIMER.current, new_time))
  if frame_time > TICK_MAX
  {
    frame_time = TICK_MAX
  }
  G.TIMER.current = new_time

  timer_tick -= frame_time
  if timer_tick <= 0
  {
    G.TIMER.tick += 1
    timer_tick += TICK
  }

  // Sprite batch
  G.RENDERER.sprite_batch.len = 0

  fmt.printfln("%v", G.GAME.player)

  render_level(&G.RENDERER, &G.GAME.level)

  gfx_draw_sprite(
    &G.RENDERER.sprite_batch,
    location = {22, 5},
    position = G.GAME.player * assets.ATLAS_TILE_SIZE,
    size = {16, 16},
  )

  if G.RENDERER.sprite_batch.len > 0
  {
    sprite_batch := G.RENDERER.sprite_batch.instances[:G.RENDERER.sprite_batch.len]
    sg.update_buffer(G.RENDERER.game.bindings.vertex_buffers[1], as_range(sprite_batch))
  }

  // Text rendering
  dpi_scale := sapp.dpi_scale()
  sdtx.canvas(GAME_WIDTH, GAME_HEIGHT)
  sdtx.origin(0, 0)
  sdtx.font(0)
  sdtx.color3b(255, 255, 255)
  sdtx.printf("Some sample text for the game\n")

  // Game rendering pass
  vertex_shader_uniforms := shaders.Vs_Params {
    pixel_to_ndc = G.RENDERER.game.pixel_to_ndc,
    sprite_atlas_size = {
      f32(G.RENDERER.game.sprite_atlas_size.x),
      f32(G.RENDERER.game.sprite_atlas_size.y),
    },
  }

  sg.begin_pass(G.RENDERER.game.pass)

  sg.apply_pipeline(G.RENDERER.game.pipeline)
  sg.apply_bindings(G.RENDERER.game.bindings)
  sg.apply_uniforms(shaders.UB_vs_params, {ptr = &vertex_shader_uniforms, size = size_of(vertex_shader_uniforms)})
  sg.draw(0, QUAD_INDEX_SIZE, G.RENDERER.sprite_batch.len)

  sg.end_pass()

  // Swapchain rendering pass
  // Setup resolution scale depending on current window size
  window_width := sapp.widthf()
  window_height := sapp.heightf()
  resolution_scale := gfx_get_resolution_scaling(window_width, window_height, dpi_scale)

  sg.begin_pass({action = G.RENDERER.swapchain.pass_action, swapchain = sglue.swapchain(), label = "swapchain-pass"})
  sg.apply_pipeline(G.RENDERER.swapchain.pipeline)
  sg.apply_bindings(G.RENDERER.swapchain.bindings)
  vp := gfx_get_pixel_perfect_viewport(window_width, window_height, dpi_scale, resolution_scale)
  sg.apply_viewport(vp.x, vp.y, vp.z, vp.w, false)

  sg.draw(0, QUAD_INDEX_SIZE, 1)
  sdtx.draw()

  sg.end_pass()
  sg.commit()
}

@(export)
game_event :: proc(ev: ^sapp.Event)
{
  /**/ if ev.type == .KEY_DOWN
  {
    #partial switch ev.key_code
    {
    case .SPACE:
      G.INPUT.keys += {.SPACE}

    case .W, .UP:
      G.INPUT.keys += {.UP}
    case .S, .DOWN:
      G.INPUT.keys += {.DOWN}
    case .A, .LEFT:
      G.INPUT.keys += {.LEFT}
    case .D, .RIGHT:
      G.INPUT.keys += {.RIGHT}

    case .Q:
      sapp.quit()

    case .F:
      sapp.toggle_fullscreen()
    }
  }
  else if ev.type == .KEY_UP
  {
    #partial switch ev.key_code
    {
    case .SPACE:
      G.INPUT.keys -= {.SPACE}

    case .W, .UP:
      G.INPUT.keys -= {.UP}
      if G.INPUT.key_current == .UP
      {
        G.INPUT.key_current = nil
      }

    case .S, .DOWN:
      G.INPUT.keys -= {.DOWN}
      if G.INPUT.key_current == .DOWN
      {
        G.INPUT.key_current = nil
      }

    case .A, .LEFT:
      G.INPUT.keys -= {.LEFT}
      if G.INPUT.key_current == .LEFT
      {
        G.INPUT.key_current = nil
      }

    case .D, .RIGHT:
      G.INPUT.keys -= {.RIGHT}
      if G.INPUT.key_current == .RIGHT
      {
        G.INPUT.key_current = nil
      }
    }
  }
  else if ev.type == .MOUSE_DOWN
  {
  }
  else if ev.type == .MOUSE_UP
  {
  }
  else if ev.type == .FOCUSED
  {
  }
  else if ev.type == .UNFOCUSED
  {
  }
  else if ev.type == .RESIZED
  {
    G.RENDERER.game.pixel_to_ndc = gfx_get_pixel_to_ndc(GAME_WIDTH, GAME_HEIGHT)
  }
}

// Convert sokol_app event keycodes to our own keycodes
sapp_keycode_to_key :: proc(keycode: sapp.Keycode) -> Maybe(Key)
{
  #partial switch keycode
  {
  case .SPACE:
    return .SPACE
  case .W, .UP:
    return .UP
  case .S, .DOWN:
    return .DOWN
  case .A, .LEFT:
    return .LEFT
  case .D, .RIGHT:
    return .RIGHT

  case:
    return nil
  }
}

@(export)
game_cleanup :: proc()
{
  sdtx.shutdown()
  sg.shutdown()

  // free(G)
}

@(export)
game_mem :: proc() -> rawptr
{
  return G
}

@(export)
game_size_of_mem :: proc() -> int
{
  return size_of(Game_Mem)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr)
{
  G = (^Game_Mem)(mem)

  gfx_hot_reload(&G.RENDERER)
}
