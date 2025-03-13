package game

import "core:fmt"
// import "core:slice"
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
  effects:  bit_set[Player_Effect],
}

Player_Effect :: enum
{
  SLOW,
  TELEPORT_COOLDOWN,
}

Level :: struct
{
  pathways: [BUDGET_GAMEPLAY_PATHWAYS]Pathway,
  len:      int,
}

Entity_Id :: distinct u32

Pathway_Kind :: enum
{
  STREAM,
  CROSSING,
  START,
  BOOST,
  SLOW,
  TELEPORT,
  GOAL,
}

Pathway :: struct
{
  id:          Entity_Id,
  kind:        bit_set[Pathway_Kind],
  pos:         Pos,
  sprite:      assets.Sprite_Name,
  teleport_to: Entity_Id
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
  start, start_ok := find_pathway_start(level.pathways[:level.len])
  assert(start_ok, fmt.tprintf("start not found for assets.LEVEL[%v]", level_idx))
  game.player.pos = start.pos
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

    for &pathway in level.pathways[:level.len]
    {
      render_sprite(renderer, pathway.pos, pathway.sprite)
    }
    render_sprite(renderer, game.player.pos, .PLAYER)
  }
}

gameplay_loop :: proc(game: ^Game)
{
  switch game.state
  {
  case .MENU:
    game.state = .PLAY

  case .WIN:

  case .PLAY:
    level := game.levels[game.level_cur]

    pathways := level.pathways[:level.len]
    cur_pathway, cur_pathway_ok := find_pathway_pos(pathways, game.player.pos)
    assert(cur_pathway_ok, fmt.tprintf("player out of bounds at: %v", game.player.pos))

    ////////////////////////////////////////

    // win-con!
    if .GOAL in cur_pathway.kind
    {
      next_level := game.level_cur + 1
      if next_level == len(assets.LEVELS)
      { // we made it through all levels
        gameplay_start_level(game, next_level % len(assets.LEVELS))
        // gameplay_win(game)
        break
      }
      else
      { // start the next level
        gameplay_start_level(game, next_level)
        break
      }
    }

    // the player can only "steer" in a crossing - otherwise the try to go .DOWN
    direction := .CROSSING in cur_pathway.kind ? game.player.dir : .DOWN
    move := Dir_Vecs[direction]

    ////////////////////////////////////////
    // stepping on a .SLOW tile takes and extra step

    /**/ if .SLOW in game.player.effects
    {
      game.player.effects -= {.SLOW}
    }
    else if .SLOW in cur_pathway.kind
    {
      // the next move has no effect if we are on a .SLOW pathway
      move = {0, 0}
      game.player.effects += {.SLOW}
    }

    ////////////////////////////////////////

    next_pos := game.player.pos + move

    if .TELEPORT in cur_pathway.kind && .TELEPORT_COOLDOWN not_in game.player.effects
    {
      teleport_pathway, teleport_pathway_ok := find_pathway_id(pathways, cur_pathway.teleport_to)
      if teleport_pathway_ok
      {
        next_pos = teleport_pathway.pos
        game.player.effects += {.TELEPORT_COOLDOWN}
      }
    }

    next_pathway, next_pathway_ok := find_pathway_pos(pathways, next_pos)

    // the player moved to a valid pathway
    if next_pathway_ok
    {
      game.player.prev_pos = game.player.pos
      game.player.pos = next_pos

      if .TELEPORT not_in next_pathway.kind
      {
        game.player.effects -= {.TELEPORT_COOLDOWN}
      }
    }
    else
    {
      drift(pathways, game)
    }

    // a boost just means we move one extra pathway without incrementing `steps`
    if .BOOST in cur_pathway.kind && .BOOST in next_pathway.kind
    {
      drift(pathways, game)
    }

    game.steps += 1
  }

  drift :: proc(pathways: []Pathway, game: ^Game)
  {
    dirs: Dirs = {.DOWN, .LEFT, .RIGHT, .UP}
    for dir in dirs
    {
      next_pos := game.player.pos + Dir_Vecs[dir]

      // we can't go backwards
      if next_pos == game.player.prev_pos do continue

      next_pathway, next_pathway_valid := find_pathway_pos(pathways, next_pos)
      if next_pathway_valid
      {
        game.player.prev_pos = game.player.pos
        game.player.pos = next_pos
        game.player.effects -= {.TELEPORT_COOLDOWN}

        return
      }
    }

    assert(false, fmt.tprintf("player failed to drift in assets.LEVELS[%v] @ %v: %v", game.level_cur, game.player.pos))
  }

}

gameplay_win :: proc(game: ^Game)
{
  fmt.printfln("you is a winner!")
  game.state = .WIN
}

gameplay_hot_reloaded :: proc(game: ^Game)
{
  gameplay_init(game)
  gameplay_start_level(game, game.level_cur)
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

@(private)
parse_level :: proc(game: ^Game, level_idx: int)
{
  level: Level
  pathway_id: Entity_Id

  level_asset := assets.LEVELS[level_idx]
  level_png, level_png_err := png.load_from_bytes(data = level_asset.bytes, allocator = context.temp_allocator)
  if level_png_err != nil
  {
    fmt.eprintfln("failed to load_from_bytes from assets.LEVELS[%v]: %v", level_idx, level_png_err)
  }
  pixels := level_png.pixels.buf[:]

  assert(level_png.width == assets.LEVEL_PNG_WIDTH, fmt.tprintf("level_png.width != %v: %v", assets.LEVEL_PNG_WIDTH, level_png.width))
  assert(level_png.height == assets.LEVEL_PNG_HEIGHT, fmt.tprintf("level_png.height != %v: %v", assets.LEVEL_PNG_HEIGHT, level_png.height))

  start_set: bool
  goal_set: bool

  Teleport_Mapper :: struct
  {
    connection: [2]Entity_Id,
    len:        int,
  }
  teleports := make(map[[4]u8]Teleport_Mapper, context.temp_allocator)

  for idx := 0; idx < len(pixels); idx += 4
  {
    rgba := pixels[idx:idx + 4]

    // discard non-opaque pixels
    if rgba[3] == 0
    {
      continue
    }
    else
    {
      pixel := [4]u8{rgba[0], rgba[1], rgba[2], rgba[3]}
      pixel_idx := idx / 4
      x := pixel_idx % assets.LEVEL_PNG_WIDTH
      y := pixel_idx / assets.LEVEL_PNG_WIDTH
      pos := Pos{x, y}

      pathway: Pathway
      pathway.id = pathway_id
      pathway.pos = pos

      /**/ if pixel == {255, 255, 0, 255}
      {
        assert(!start_set, fmt.tprintf("multiple starts found in assets.LEVELS[%v]", level_idx))
        start_set = true

        pathway.kind += {.START}
        pathway.sprite = .START
      }
      else if pixel == {0, 115, 255, 255}
      {
        pathway.kind += {.STREAM}
        pathway.sprite = .STREAM
      }
      else if pixel == {0, 115, 115, 255}
      {
        pathway.kind += {.BOOST}
        pathway.sprite = .BOOST
      }
      else if pixel == {0, 60, 255, 255}
      {
        pathway.kind += {.SLOW}
        pathway.sprite = .SLOW
      }
      else if pixel == {0, 175, 255, 255}
      {
        pathway.kind += {.CROSSING}
        pathway.sprite = .CROSSING
      }
      else if pixel == {255, 0, 0, 255}
      {
        assert(!goal_set, fmt.tprintf("multiple goals found in assets.LEVELS[%v]", level_idx))
        goal_set = true

        pathway.kind += {.GOAL}
        pathway.sprite = .GOAL
      }
      else if pixel[3] == 254 // encode teleporters as two matching pixels with 254 transparency
      {
        fmt.printfln("found teleport at pos %v", pos)
        pathway.kind += {.TELEPORT}
        pathway.sprite = .TELEPORT
        teleport := teleports[pixel]
        teleport.connection[teleport.len] = pathway.id
        teleport.len += 1

        teleports[pixel] = teleport

        assert(teleport.len < 3, fmt.tprintf("incorrect number of teleports found in assets.LEVELS[%v] @ %v: %v", level_idx, pos, pixel))

        // connect the teleports
        if teleport.len == 2
        {
          fmt.printfln("%v", teleport)
          prev_teleport, prev_teleport_ok := find_pathway_id(level.pathways[:level.len], teleport.connection[0])

          assert(prev_teleport_ok, fmt.tprintf("could not connect teleports in assets.LEVELS[%v]", level_idx))

          prev_teleport.teleport_to = pathway.id
          pathway.teleport_to = prev_teleport.id
        }
      }
      else
      {
        assert(false, fmt.tprintf("incorrect pixel color found in assets.LEVELS[%v] @ %v: %v", level_idx, pos, pixel))
      }

      level.pathways[level.len] = pathway
      level.len += 1
      pathway_id += 1
    }
  }

  assert(start_set, fmt.tprintf("start not found for assets.LEVEL[%v]", level_idx))
  assert(goal_set, fmt.tprintf("goal not found for assets.LEVEL[%v]", level_idx))

  game.levels[level_idx] = level
}

@(private)
find_pathway_id :: proc(pathways: []Pathway, id: Entity_Id) -> (^Pathway, bool)
{
  for &pathway in pathways
  {
    if pathway.id == id do return &pathway, true
  }
  return {}, false
}

@(private)
find_pathway_start :: proc(pathways: []Pathway) -> (^Pathway, bool)
{
  for &pathway in pathways
  {
    if .START in pathway.kind do return &pathway, true
  }
  return {}, false
}

@(private)
find_pathway_goal :: proc(pathways: []Pathway) -> (^Pathway, bool)
{
  for &pathway in pathways
  {
    if .GOAL in pathway.kind do return &pathway, true
  }
  return {}, false
}

@(private)
find_pathway_pos :: proc(pathways: []Pathway, pos: Pos) -> (^Pathway, bool)
{
  for &pathway in pathways
  {
    if pathway.pos == pos do return &pathway, true
  }
  return {}, false
}

@(private)
has_pathway :: proc(pathways: []Pathway, pos: Pos) -> bool
{
  for &pathway in pathways
  {
    if pathway.pos == pos do return true
  }
  return false
}
