package game

import "core:c"
import "core:fmt"
import "core:image/png"
import "core:slice"

import sg "third_party/sokol-odin/sokol/gfx"

import "assets"
import "shaders"

QUAD_INDEX_SIZE :: 6

GAME_PIXEL_FORMAT :: sg.Pixel_Format.RGBA8
GAME_SAMPLE_COUNT :: 1

CLEAR_COLOR :: sg.Color{14.0 / 255.0, 4.0 / 255.0, 37.0 / 255.0, 1}

Sprite_Shader :: struct
{
  location: [2]f32,
  size:     [2]f32,
  position: [2]f32,
  scale:    [2]f32,
  color:    [4]f32,
}

Sprite_Batch :: struct
{
  instances: [BUDGET_GFX_SPRITES]Sprite_Shader,
  len:       int,
}

GFX_Swapchain :: struct
{
  pass_action:   sg.Pass_Action,
  pipeline:      sg.Pipeline,
  shader:        sg.Shader,
  bindings:      sg.Bindings,
  vertex_buffer: sg.Buffer,
  index_buffer:  sg.Buffer,
  sampler:       sg.Sampler,
}

GFX_Game :: struct
{
  pixel_to_ndc:      [2]f32,
  sprite_atlas_size: [2]i32,
  pass:              sg.Pass,
  attachments:       sg.Attachments,
  pipeline:          sg.Pipeline,
  shader:            sg.Shader,
  bindings:          sg.Bindings,
  render_target:     sg.Image,
  vertex_buffer:     sg.Buffer,
  index_buffer:      sg.Buffer,
  instance_buffer:   sg.Buffer,
  sampler:           sg.Sampler,
}

GFX_Renderer :: struct
{
  swapchain:    GFX_Swapchain,
  game:         GFX_Game,
  sprite_batch: Sprite_Batch,
  backend:      sg.Backend,
}

gfx_init :: proc(renderer: ^GFX_Renderer) -> bool
{
  defer free_all(context.temp_allocator)

  backend := sg.query_backend()
  renderer.backend = backend

  // game renderer
  // The game renderer renders our actual game to a low resolution
  // render target.
  // This render target is used as a texture in the swapchain renderer to do a
  // pixel perfact upscale as close as possible to the window size.

  assert(GAME_WIDTH > 0, fmt.tprintf("game_width > 0: %v", GAME_WIDTH))
  assert(GAME_HEIGHT > 0, fmt.tprintf("game_height > 0: %v", GAME_HEIGHT))
  pixel_to_ndc := gfx_get_pixel_to_ndc(GAME_WIDTH, GAME_HEIGHT)

  // `render_target` is a color attachment in the game rendering pass.
  // But also a fragement shader texture in the swapchain rendering pass.
  image_description := sg.Image_Desc {
    render_target = true,
    width         = i32(GAME_WIDTH),
    height        = i32(GAME_HEIGHT),
    pixel_format  = GAME_PIXEL_FORMAT,
    sample_count  = GAME_SAMPLE_COUNT,
    label         = "color-image-render-target",
  }
  render_target := sg.make_image(image_description)

  // Depth stencil for alpha blending
  image_description.pixel_format = .DEPTH
  image_description.label = "depth-image-render-target"
  depth_image := sg.make_image(image_description)

  game_pass_attachments := sg.make_attachments({
    colors = {0 = {image = render_target}},
    depth_stencil = {image = depth_image},
    label = "game-attachments",
  })

  game_pass := sg.Pass {
    attachments = game_pass_attachments,
    action = {
      colors = {0 = {load_action = .CLEAR, clear_value = CLEAR_COLOR}},
    },
    label = "game-pass",
  }

  // Single quad reused by all our sprites
  game_vertex_buffer_vertices := [8]f32{
    1, 1,
    1, 0,
    0, 0,
    0, 1,
  }

  game_vertex_buffer := sg.make_buffer({type = .VERTEXBUFFER, data = as_range(&game_vertex_buffer_vertices), label = "game-vertex-buffer"})

  // Index buffer to draw the quad with 4 vertices instead of 6.
  game_index_buffer_vertices := [6]u16{
    0, 1, 3,
    1, 2, 3,
  }
  game_index_buffer := sg.make_buffer({type = .INDEXBUFFER, data = as_range(&game_index_buffer_vertices), label = "game-index-buffer"})

  // Another vertex buffer, instanced for all data for each sprite.
  game_instance_buffer := sg.make_buffer({
    usage = .STREAM,
    type  = .VERTEXBUFFER,
    size  = BUDGET_GFX_SPRITES * size_of(Sprite_Shader),
    label = "game-instance-buffer",
  })

  game_shader := sg.make_shader(shaders.game_shader_desc(backend))
  game_pipeline := sg.make_pipeline(gfx_game_pipeline_desc(game_shader))

  game_sampler := sg.make_sampler({min_filter = .NEAREST, mag_filter = .NEAREST, label = "game-sampler"})

  // Load and create our sprite atlas texture.
  sprite_atlas, sprite_atlas_err := png.load_from_bytes(assets.ATLAS.bytes, allocator = context.temp_allocator)
  if sprite_atlas_err != nil
  {
    fmt.eprintfln("failed to load_from_bytes from assets.ATLAS: %v", sprite_atlas_err)
  }
  sprite_atlas_width := i32(sprite_atlas.width)
  sprite_atlas_height := i32(sprite_atlas.height)

  // When HOT_RELOAD we set the image to STREAM and update it upon game_hot_reloaded
  sprite_atlas_image_data :=
    sg.Image_Data{} when HOT_RELOAD else sg.Image_Data {
      subimage = {
        0 = {
          0 = {
            ptr = raw_data(sprite_atlas.pixels.buf),
            size = c.size_t(slice.size(sprite_atlas.pixels.buf[:])),
          },
        },
      },
    }
  sprite_atlas_image_usage := sg.Usage.STREAM when HOT_RELOAD else sg.Usage.DEFAULT
  sprite_atlas_image := sg.make_image({
    width = sprite_atlas_width,
    height = sprite_atlas_height,
    data = sprite_atlas_image_data,
    pixel_format = GAME_PIXEL_FORMAT,
    usage = sprite_atlas_image_usage,
    label = "sprite-atlas",
  })

  game_bindings := sg.Bindings {
    vertex_buffers = {0 = game_vertex_buffer, 1 = game_instance_buffer},
    index_buffer = game_index_buffer,
    samplers = {shaders.SMP_smp = game_sampler},
    images = {shaders.IMG_tex = sprite_atlas_image},
  }

  // Swapchain renderer resources

  swapchain_pass_action: sg.Pass_Action
  swapchain_pass_action.colors[0] = { load_action = .CLEAR, clear_value = CLEAR_COLOR }

  quad_vertices := [16]f32{
    +1, +1,   1, 1,
    +1, -1,   1, 0,
    -1, -1,   0, 0,
    -1, +1,   0, 1,
  }
  swapchain_vertex_buffer := sg.make_buffer({type = .VERTEXBUFFER, data = as_range(&quad_vertices), label = "swapchain-vertex-buffer"})

  swapchain_index_buffer_vertex := [QUAD_INDEX_SIZE]u16{0, 1, 3, 1, 2, 3}
  swapchain_index_buffer := sg.make_buffer({type = .INDEXBUFFER, data = as_range(&swapchain_index_buffer_vertex), label = "swapchain-index-buffer"})

  swapchain_shader := sg.make_shader(shaders.swapchain_shader_desc(backend))
  swapchain_pipeline := sg.make_pipeline(gfx_swapchain_pipeline_desc(swapchain_shader))

  swapchain_sampler := sg.make_sampler({min_filter = .NEAREST, mag_filter = .NEAREST, label = "swapchain-sampler"})

  swapchain_bindings := sg.Bindings {
    vertex_buffers = {0 = swapchain_vertex_buffer},
    index_buffer = swapchain_index_buffer,
    samplers = {shaders.IMG_tex = swapchain_sampler},
    images = {shaders.SMP_smp = render_target},
  }

  renderer.game = GFX_Game {
    pixel_to_ndc      = pixel_to_ndc,
    sprite_atlas_size = {sprite_atlas_width, sprite_atlas_height},
    pass              = game_pass,
    attachments       = game_pass_attachments,
    bindings          = game_bindings,
    pipeline          = game_pipeline,
    shader            = game_shader,
    render_target     = render_target,
    vertex_buffer     = game_vertex_buffer,
    index_buffer      = game_index_buffer,
    instance_buffer   = game_instance_buffer,
    sampler           = game_sampler,
  }

  renderer.swapchain = GFX_Swapchain {
    pass_action   = swapchain_pass_action,
    bindings      = swapchain_bindings,
    pipeline      = swapchain_pipeline,
    shader        = swapchain_shader,
    vertex_buffer = swapchain_vertex_buffer,
    index_buffer  = swapchain_index_buffer,
  }

  return true
}

// Draw a sprite by adding it to the sprite batch for the upcoming frame
//
// position: X and Y coordinates with {0, 0} being top-left
// scale:    Scale of the sprite being rendered
// color:    Color multiplier of the sprite, {255, 255, 255, 1} format
// location: Location in the sprite sheet with {0, 0} being top-left
// size:     Size of the area of the sprite sheet to render
gfx_add_to_sprite_batch :: proc(
  sprite_batch: ^Sprite_Batch,
  position:     [2]int,
  scale:        [2]int = {1, 1},
  color:        [4]f32 = {255, 255, 255, 1},
  location:     [2]int,
  size:         [2]int,
)
{
  if sprite_batch.len > BUDGET_GFX_SPRITES do return

  vertex: Sprite_Shader = {
    location = {f32(location.x * assets.ATLAS_TILE_SIZE), f32(location.y * assets.ATLAS_TILE_SIZE)},
    size     = {f32(size.x), f32(size.y)},
    position = {f32(position.x), f32(position.y)},
    scale    = {f32(scale.x), f32(scale.y)},
    color    = color,
  }
  sprite_batch.instances[sprite_batch.len] = vertex
  sprite_batch.len += 1
}

// Multiplier to convert from from pixel to normalized device coordinates
gfx_get_pixel_to_ndc :: proc(pixel_width, pixel_height: f32) -> [2]f32
{
  return {2 / pixel_width, 2 / pixel_height}
}

// Get viewport size to the largest pixel perfect resolution given game size
gfx_get_pixel_perfect_viewport :: proc(
  swapchain_width, swapchain_height, dpi_scale: f32,
  resolution_scale: int,
) -> [4]f32
{
  width := swapchain_width / dpi_scale
  height := swapchain_height / dpi_scale

  game_width := GAME_WIDTH * f32(resolution_scale)
  game_height := GAME_HEIGHT * f32(resolution_scale)

  vp_x := dpi_scale * (width - game_width) / 2
  vp_y := dpi_scale * (height - game_height) / 2
  vp_w := dpi_scale * game_width
  vp_h := dpi_scale * game_height

  return {vp_x, vp_y, vp_w, vp_h}
}

// Get the largest possible resolution scaling based on window and GAME size
gfx_get_resolution_scaling :: proc(window_width, window_height, dpi_scale: f32) -> int
{
  width := window_width / dpi_scale
  height := window_height / dpi_scale

  window_aspect := width / height
  game_aspect := f32(GAME_WIDTH / GAME_HEIGHT)

  res := int(height / GAME_HEIGHT) if game_aspect < window_aspect else int(width / GAME_WIDTH)

  return res if res > 1 else 1
}

gfx_hot_reload :: proc(renderer: ^GFX_Renderer)
{
  game_shader_state := sg.query_shader_state(renderer.game.shader)
  if game_shader_state == .VALID
  {
    sg.uninit_shader(renderer.game.shader)
    sg.init_shader(renderer.game.shader, shaders.game_shader_desc(renderer.backend))
  }
  else
  {
    sg.destroy_shader(renderer.game.shader)
    renderer.game.shader = sg.make_shader(shaders.game_shader_desc(renderer.backend))
  }

  game_pipeline_state := sg.query_pipeline_state(renderer.game.pipeline)
  if game_pipeline_state == .VALID
  {
    sg.uninit_pipeline(renderer.game.pipeline)
    sg.init_pipeline(renderer.game.pipeline, gfx_game_pipeline_desc(renderer.game.shader))
  }
  else
  {
    sg.destroy_pipeline(renderer.game.pipeline)
    renderer.game.pipeline = sg.make_pipeline(gfx_game_pipeline_desc(renderer.game.shader))
  }

  swapchain_shader_state := sg.query_shader_state(renderer.swapchain.shader)
  if swapchain_shader_state == .VALID
  {
    sg.uninit_shader(renderer.swapchain.shader)
    sg.init_shader(renderer.swapchain.shader, shaders.swapchain_shader_desc(renderer.backend))
  }
  else
  {
    sg.destroy_shader(renderer.swapchain.shader)
    renderer.swapchain.shader = sg.make_shader(shaders.swapchain_shader_desc(renderer.backend))
  }

  swapchain_pipeline_state := sg.query_pipeline_state(renderer.swapchain.pipeline)
  if swapchain_pipeline_state == .VALID
  {
    sg.uninit_pipeline(renderer.swapchain.pipeline)
    sg.init_pipeline(renderer.swapchain.pipeline, gfx_swapchain_pipeline_desc(renderer.swapchain.shader))
  }
  else
  {
    sg.destroy_pipeline(renderer.swapchain.pipeline)
    renderer.swapchain.pipeline = sg.make_pipeline(gfx_swapchain_pipeline_desc(renderer.swapchain.shader))
  }

  sprite_atlas, sprite_atlas_err := png.load_from_bytes(assets.ATLAS.bytes, allocator = context.temp_allocator)
  if sprite_atlas_err != nil
  {
    fmt.eprintfln("failed to load_from_bytes from assets.ATLAS: %v", sprite_atlas_err)
    return
  }
  sprite_atlas_width  := i32(sprite_atlas.width)
  sprite_atlas_height := i32(sprite_atlas.height)

  sprite_atlas_image_data := sg.Image_Data {
    subimage = {
      0 = {
        0 = {ptr = raw_data(sprite_atlas.pixels.buf), size = c.size_t(slice.size(sprite_atlas.pixels.buf[:]))},
      },
    },
  }

  sg.update_image(renderer.game.bindings.images[shaders.IMG_tex], sprite_atlas_image_data)
  renderer.game.sprite_atlas_size = {sprite_atlas_width, sprite_atlas_height}
}

gfx_game_pipeline_desc :: proc(shader: sg.Shader) -> sg.Pipeline_Desc
{
  return {
    layout = {
      buffers = {1 = {step_func = .PER_INSTANCE}},
      attrs = {
        shaders.ATTR_game_vertex_position = {format = .FLOAT2, buffer_index = 0},
        shaders.ATTR_game_location = {format = .FLOAT2, buffer_index = 1},
        shaders.ATTR_game_size = {format = .FLOAT2, buffer_index = 1},
        shaders.ATTR_game_position = {format = .FLOAT2, buffer_index = 1},
        shaders.ATTR_game_scale = {format = .FLOAT2, buffer_index = 1},
        shaders.ATTR_game_color = {format = .FLOAT4, buffer_index = 1},
      },
    },
    index_type = .UINT16,
    shader = shader,
    depth = {pixel_format = .DEPTH, compare = .LESS_EQUAL, write_enabled = true},
    colors = {
      0 = {
        blend = {
          enabled = true,
          src_factor_rgb = .SRC_ALPHA,
          dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
          op_rgb = .ADD,
          src_factor_alpha = .SRC_ALPHA,
          dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
          op_alpha = .ADD,
        },
        pixel_format = GAME_PIXEL_FORMAT,
      },
    },
    color_count = 1,
    sample_count = GAME_SAMPLE_COUNT,
    label = "game-pipeline",
  }
}

gfx_swapchain_pipeline_desc :: proc(shader: sg.Shader) -> sg.Pipeline_Desc
{
  return {
    layout = {
      attrs = {
        shaders.ATTR_swapchain_vertex_position = {format = .FLOAT2},
        shaders.ATTR_swapchain_vertex_uv = {format = .FLOAT2},
      },
    },
    index_type = .UINT16,
    shader = shader,
    depth = {compare = .LESS_EQUAL, write_enabled = true},
    label = "swapchain-pipeline",
  }
}

// Convert common types to sokol_gfx `Range`
as_range :: proc
{
  slice_as_range,
  dynamic_array_as_range,
  array_ptr_as_range,
}

slice_as_range :: proc "contextless" (val: $T/[]$E) -> (range: sg.Range)
{
  range.ptr = raw_data(val)
  range.size = c.size_t(len(val)) * size_of(E)
  return
}

dynamic_array_as_range :: proc "contextless" (val: $T/[dynamic]$E) -> (range: sg.Range)
{
  range.ptr = raw_data(val)
  range.size = u64(len(val)) * size_of(E)
  return
}

array_ptr_as_range :: proc "contextless" (val: ^$T/[$N]$E) -> (range: sg.Range)
{
  range.ptr = raw_data(val)
  range.size = c.size_t(len(val)) * size_of(E)
  return
}
