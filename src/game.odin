package game

// import "core:fmt"
import "core:strings"

import "assets"

Pos :: [2]int

Game :: struct
{
  player: Pos,
  level:  Level,
}

Level :: struct
{
  start:    Pos,
  goal:     Pos,
  pathways: [BUDGET_GAME_PATHWAYS]Pos,
  len:      int,
}

render_level :: proc(renderer: ^GFX_Renderer, level: ^Level)
{
  gfx_draw_sprite(
    sprite_batch = &renderer.sprite_batch,
    position = level.start * assets.ATLAS_TILE_SIZE,
    size = {16, 16},
    location = {1, 1},
  )

  for &pathway in level.pathways[:level.len]
  {
    gfx_draw_sprite(
      sprite_batch = &renderer.sprite_batch,
      position = pathway * assets.ATLAS_TILE_SIZE,
      size = {16, 16},
      location = {1, 13},
    )
  }

  gfx_draw_sprite(
    sprite_batch = &renderer.sprite_batch,
    position = level.goal * assets.ATLAS_TILE_SIZE,
    size = {16, 16},
    location = {1, 11},
  )
}

start_level :: proc(idx: int, game: ^Game)
{
  level: Level

  cur_level := assets.LEVELS[idx]
  level_lines := strings.split_lines(cur_level.data, context.temp_allocator)

  for line, y in level_lines do for rune, x in line
  {
    pos := Pos{x, y}

    switch rune
    {
    case '#':
      level.start = pos
      game.player = pos
    case '.':
      level.pathways[level.len] = pos
      level.len += 1
    case '$':
      level.goal = pos

    case:
      continue
    }
  }

  game.level = level
}
