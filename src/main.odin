package game

import "core:fmt"
import "core:time"

import sapp "third_party/sokol-odin/sokol/app"
import sdtx "third_party/sokol-odin/sokol/debugtext"
import sg "third_party/sokol-odin/sokol/gfx"
import sglue "third_party/sokol-odin/sokol/glue"
import slog "third_party/sokol-odin/sokol/log"

// import "assets"
import "shaders"

GAME_NAME :: "Downstream"

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
  DOWN,
  LEFT,
  RIGHT,
  R,
  SPACE,
  RETURN,
  ESC,
}

Input :: struct
{
  keys: bit_set[Key],
}

Timer :: struct
{
  tick:        u64,
  speed:       int,
  elapsed:     f64,
  current:     time.Time,
  accumulator: f64,
}

TICK :: 1.0 / 4

GAME_WIDTH  :: f32(320)
GAME_HEIGHT :: f32(180)

HOT_RELOAD :: #config(HOT_RELOAD, false) && ODIN_DEBUG

G: ^Game_Mem

@(export)
game_app_desc :: proc() -> sapp.Desc
{
  window_title: cstring = "hot!" when HOT_RELOAD else GAME_NAME

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
  G.TIMER.speed = 1

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

  sdtx.canvas(GAME_WIDTH, GAME_HEIGHT)
  sdtx.origin(1, 1)
  sdtx.font(0)

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

  gameplay_init(&G.GAME)
  gameplay_start_level(&G.GAME, 0)

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
  G.TIMER.current = new_time

  gameplay_handle_input(&G.GAME, G.INPUT, &G.TIMER)

  timer_tick -= frame_time * f64(G.TIMER.speed)
  if timer_tick <= 0
  {
    G.TIMER.tick += 1
    timer_tick += TICK

    gameplay_loop(&G.GAME, &G.INPUT)
  }

  // Sprite batch
  G.RENDERER.sprite_batch.len = 0

  gameplay_render(renderer = &G.RENDERER, game = &G.GAME, tick = G.TIMER.tick)

  if G.RENDERER.sprite_batch.len > 0
  {
    sprite_batch := G.RENDERER.sprite_batch.instances[:G.RENDERER.sprite_batch.len]
    sg.update_buffer(G.RENDERER.game.bindings.vertex_buffers[1], as_range(sprite_batch))
  }


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
  dpi_scale := sapp.dpi_scale()
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
    case .S, .DOWN:
      G.INPUT.keys += {.DOWN}

    case .A, .LEFT:
      G.INPUT.keys += {.LEFT}

    case .D, .RIGHT:
      G.INPUT.keys += {.RIGHT}

    ////////////////////////////////////////

    // Interactions
    case .SPACE:
      G.INPUT.keys += {.SPACE}

    case .ENTER:
      G.INPUT.keys += {.RETURN}

    case .ESCAPE:
      G.INPUT.keys += {.ESC}

    case .R:
      G.INPUT.keys += {.R}

    case .F:
      sapp.toggle_fullscreen()

    case .Q:
      when ODIN_DEBUG
      {
        sapp.quit()
      }

    ////////////////////////////////////////

    case .J:
      when ODIN_DEBUG
      {
        gameplay_start_level(&G.GAME, (G.GAME.level_cur - 1) %% G.GAME.level_len)
      }

    case .K:
      when ODIN_DEBUG
      {
        gameplay_start_level(&G.GAME, (G.GAME.level_cur + 1) %% G.GAME.level_len)
      }
    }
  }
  else if ev.type == .KEY_UP
  {
    #partial switch ev.key_code
    {
    // Movement
    case .S, .DOWN:
      G.INPUT.keys -= {.DOWN}

    case .A, .LEFT:
      G.INPUT.keys -= {.LEFT}

    case .D, .RIGHT:
      G.INPUT.keys -= {.RIGHT}

    ////////////////////////////////////////

    // Interactions
    case .SPACE:
      G.INPUT.keys -= {.SPACE}

    case .ENTER:
      G.INPUT.keys -= {.RETURN}

    case .ESCAPE:
      G.INPUT.keys -= {.ESC}

    case .R:
      G.INPUT.keys -= {.R}

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
  gameplay_hot_reloaded(&G.GAME)
}
