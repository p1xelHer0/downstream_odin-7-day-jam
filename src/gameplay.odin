package game

import "core:fmt"
import "core:slice"
import "core:image/png"

import "assets"

Pos :: [2]int

Dir :: enum
{
  DOWN,
  UP,
  RIGHT,
  LEFT,
}

Game_State :: enum
{
  MENU,
  PLAY,
  WIN,
}

Game :: struct
{
  state:     Game_State,

  player:    Player,
  steps:     int,

  levels:    [BUDGET_GAMEPLAY_LEVELS]Level,
  level_cur: int,
  level_len: int,
}

Player :: struct
{
  pos:      Pos,
  dir:      Dir,
  prev_pos: Pos,
}

Level :: struct
{
  start:    Pos,
  goal:     Pos,
  pathways: [BUDGET_GAMEPLAY_PATHWAYS]Pos,
  len:      int,
}

Dir_Vecs := [Dir][2]int {
  .UP    = { 0, -1},
  .DOWN  = { 0,  1},
  .LEFT  = {-1,  0},
  .RIGHT = { 1,  0},
}
Dirs :: bit_set[Dir;u8]

gameplay_init :: proc(game: ^Game)
{
  game.level_len = 0

  for _, idx in assets.LEVELS
  {
    parse_level(game, idx)
    game.level_len += 1
  }
}

gameplay_start_level :: proc(game: ^Game, level_idx: int)
{
  game.level_cur = level_idx
  level := game.levels[game.level_cur]
  game.player.pos = level.start
  game.player.dir = .DOWN
  game.state = .PLAY
}

gameplay_render :: proc(renderer: ^GFX_Renderer, game: ^Game, tick: u64)
{
  switch game.state
  {
  case .MENU:

  case .WIN:
    render_sprite(renderer, {18, 11}, .WIN, scale = {4, 4})

  case .PLAY:
    level := game.levels[game.level_cur]

    render_sprite(renderer, level.start, .START)
    for &pathway in level.pathways[:level.len]
    {
      render_sprite(renderer, pathway, .STREAM)
    }
    render_sprite(renderer, level.goal, .GOAL)
    render_sprite(renderer, game.player.pos, .PLAYER)
  }
}

@(private)
render_sprite :: proc(renderer: ^GFX_Renderer, pos: Pos, sprite: assets.Sprite_Name, scale := [2]int{1, 1})
{
  sprite_data := assets.SPRITE[sprite]

  gfx_add_to_sprite_batch(
    &renderer.sprite_batch,
    position = pos * assets.ATLAS_TILE_SIZE,
    size = sprite_data.size,
    location = sprite_data.location,
    scale = scale,
  )
}

gameplay_loop :: proc(game: ^Game)
{
  switch game.state
  {
  case .MENU:
    game.state = .PLAY

  case .WIN:

  case .PLAY:
    game.steps += 1

    level := game.levels[game.level_cur]
    pathways := level.pathways[:level.len]
    next_pos := game.player.pos + Dir_Vecs[game.player.dir]

    /**/ if game.player.pos == level.goal
    {
      next_level := game.level_cur + 1
      if next_level == len(assets.LEVELS)
      {
        gameplay_win(game)
      }
      else
      {
        gameplay_start_level(game, next_level)
      }
    }
    else if next_pos == level.goal
    {
      game.player.prev_pos = game.player.pos
      game.player.pos = next_pos
    }
    else if slice.contains(pathways, next_pos)
    {
      game.player.prev_pos = game.player.pos
      game.player.pos = next_pos
    }
    else
    {
      dirs: Dirs = {.DOWN, .LEFT, .RIGHT, .UP}
      for dir in dirs
      {
        next_pos = game.player.pos + Dir_Vecs[dir]
        if next_pos == game.player.prev_pos do continue
        if slice.contains(pathways, next_pos)
        {
          game.player.prev_pos = game.player.pos
          game.player.pos = next_pos
          break
        }
      }
    }
  }
}

gameplay_win :: proc(game: ^Game)
{
  fmt.printfln("you is a winner!")
  game.state = .WIN
}

@(private)
parse_level :: proc(game: ^Game, level_idx: int)
{
  level: Level

  level_asset := assets.LEVELS[level_idx]
  level_png, level_png_err := png.load_from_bytes(data = level_asset.bytes, allocator = context.temp_allocator)
  if level_png_err != nil
  {
    fmt.eprintfln("failed to load_from_bytes from assets.LEVELS[%v]: %v", level_idx, level_png_err)
  }
  pixels := level_png.pixels.buf[:]

  assert(level_png.width == assets.LEVEL_PNG_WIDTH, fmt.tprintf("level_png.width != %v: %v", assets.LEVEL_PNG_WIDTH, level_png.width))
  assert(level_png.height == assets.LEVEL_PNG_HEIGHT, fmt.tprintf("level_png.height != %v: %v", assets.LEVEL_PNG_HEIGHT, level_png.height))

  for idx := 0; idx < len(pixels); idx += 4
  {
    rgba := pixels[idx:idx + 4]

    // discard "empty" pixels
    if rgba[3] < 255
    {
      continue
    }
    else
    {
      pixel := [3]u8{rgba[0], rgba[1], rgba[2]}
      pixel_idx := idx / 4
      x := pixel_idx % assets.LEVEL_PNG_WIDTH
      y := pixel_idx / assets.LEVEL_PNG_WIDTH
      pos := Pos{x, y}

      start_set: bool
      goal_set: bool

      /**/ if pixel == {0, 255, 0}   // Start
      {
        assert(!start_set, fmt.tprintf("multiple starts found in assets.LEVELS[%v]", level_idx))
        level.start = pos
        start_set = true
      }
      else if pixel == {0, 115, 255} // Stream
      {
        level.pathways[level.len] = pos
        level.len += 1
      }
      else if pixel == {255, 0, 0}   // Goal
      {
        assert(!goal_set, fmt.tprintf("multiple goals found in assets.LEVELS[%v]", level_idx))
        level.goal = pos
        goal_set = true
      }
      else
      {
        assert(false, fmt.tprintf("incorrect pixel color found in assets.LEVELS[%v] @ %v: %v", level_idx, pos, pixel))
      }
    }
  }

  game.levels[level_idx] = level
}

gameplay_hot_reloaded :: proc(game: ^Game)
{
  gameplay_init(game)
  gameplay_start_level(game, game.level_cur)
}
