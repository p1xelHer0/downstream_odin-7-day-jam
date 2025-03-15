package game

import "core:fmt"
// import "core:slice"
import "core:image/png"

import sdtx "third_party/sokol-odin/sokol/debugtext"

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
  DEAD,
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
  tiles: [BUDGET_GAMEPLAY_TILES]Tile,
  len:   int,
  text:  []string,
  steps: int,
}

Entity_Id :: distinct u32

Tile_Kind :: enum
{
  STREAM,
  CROSSING,
  START,
  BOOST,
  SLOW,
  DEATH,
  TELEPORT,
  GOAL,
}

Tile :: struct
{
  id:          Entity_Id,
  kind:        bit_set[Tile_Kind],
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

gameplay_restart_game :: proc(game: ^Game)
{
  game.level_cur = 0
  for &level in game.levels[:game.level_len]
  {
    level.steps = 0
  }

  gameplay_start_level(&G.GAME, game.level_cur)
}

gameplay_start_level :: proc(game: ^Game, level_idx: int)
{
  game.level_cur = level_idx
  level := &game.levels[game.level_cur]
  start, start_ok := find_tile_start(level.tiles[:level.len])

  assert(start_ok, fmt.tprintf("start not found for assets.LEVEL[%v]", level_idx))

  level.steps = 0
  game.player.pos = start.pos
  game.player.prev_pos = {-1, -1}
  game.player.dir = .DOWN
  game.state = .PLAY
}

gameplay_render :: proc(renderer: ^GFX_Renderer, game: ^Game, tick: u64)
{
  text_default_color()

  switch game.state
  {
  case .MENU:
    level := game.levels[game.level_cur]
    level_cur_text := game.level_cur + 1
    sdtx.printf("You completed level %v in %v steps!\n\n", level_cur_text, level.steps)
    sdtx.printf("- <RETURN> to start the next level\n")
    sdtx.printf("- <R> try it again\n\n\n")
    if game.level_cur < 3
    {
      sdtx.printf("Hint: You can press <R> at any time\nduring the level to restart\n\n")
      sdtx.printf("Hint: You can press <ESC> at any time\nto restart the whole game")
    }

  case .WIN:
    steps_total := 0
    for level in game.levels {
      steps_total += level.steps
    }
    sdtx.printf("You made it down the stream in\n%v steps!\n", steps_total)

    sdtx.printf("\n- <R> to play again")

    sdtx.printf("\n\n\n\n\n\n\n\n\n")
    sdtx.printf("Made with Odin and Sokol\nfor the Odin 7 Day Jam\n\n")
    sdtx.printf("- odin-lang.org\n")
    sdtx.printf("- github.com/floooh/sokol\n")

    sdtx.printf("\n\n")
    sdtx.printf("- p1xelHer0.itch.io/downstream")

  case .DEAD:
    text_dead_color()
    level_cur_text := game.level_cur + 1
    sdtx.printf("You died on level %v!\n\n\n", level_cur_text)
    text_default_color()
    sdtx.printf("- <R> try it again")

  case .PLAY:
    level := game.levels[game.level_cur]

    for &tile in level.tiles[:level.len]
    {
      render_sprite(renderer, tile.pos, tile.sprite)
    }
    if game.player.dir == .LEFT
    {
      render_sprite(renderer, game.player.pos - Pos{1, 0}, .PLAYER_LEFT_FLAG)
    }
    else if game.player.dir == .RIGHT
    {
      render_sprite(renderer, game.player.pos + Pos{1, 0}, .PLAYER_RIGHT_FLAG)
    }
    render_sprite(renderer, game.player.pos, .PLAYER)

    sdtx.printf("Level: %v\nSteps: %v\n\n", game.level_cur + 1, level.steps)

    for &text in level.text
    {
      sdtx.printf("%v\n", text)
    }
  }
}

gameplay_loop :: proc(game: ^Game, input: ^Input)
{
  switch game.state
  {
  case .MENU:

  case .WIN:

  case .DEAD:

  case .PLAY:
    level := &game.levels[game.level_cur]

    tiles := level.tiles[:level.len]
    cur_tile, cur_tile_ok := find_tile_pos(tiles, game.player.pos)
    assert(cur_tile_ok, fmt.tprintf("player out of bounds at: %v", game.player.pos))

    ////////////////////////////////////////

    // win-con!
    if .GOAL in cur_tile.kind
    {
      next_level := game.level_cur + 1
      if next_level == len(assets.LEVELS)
      {
        gameplay_win(game)
        break
      }
      else
      {
        game.state = .MENU
        break
      }
    }

    // death-con!
    if .DEATH in cur_tile.kind
    {
      game.state = .DEAD
      break
    }

    ////////////////////////////////////////

    // the player can only "steer" in a crossing - otherwise the try to go .DOWN
    direction := .CROSSING in cur_tile.kind ? game.player.dir : .DOWN
    move := Dir_Vecs[direction]

    // stepping on a .SLOW tile takes and extra step
    /**/ if .SLOW in game.player.effects
    {
      game.player.effects -= {.SLOW}
    }
    else if .SLOW in cur_tile.kind
    {
      // the next move has no effect if we are on a .SLOW tile
      move = {0, 0}
      game.player.effects += {.SLOW}
    }

    next_pos := game.player.pos + move

    // without this the player will just bounce back and forth between .TELEPORT tiles
    if .TELEPORT in cur_tile.kind && .TELEPORT_COOLDOWN not_in game.player.effects
    {
      teleport_tile, teleport_tile_ok := find_tile_id(tiles, cur_tile.teleport_to)
      if teleport_tile_ok
      {
        next_pos = teleport_tile.pos
        game.player.effects += {.TELEPORT_COOLDOWN}
      }
    }

    next_tile, next_tile_ok := find_tile_pos(tiles, next_pos)
    next_tile_ok = next_tile_ok && next_tile.pos != game.player.prev_pos

    // the player moved to a valid tile
    if next_tile_ok
    {
      commit_move(next_tile, &game.player)
    }
    else // we need to find the next tile
    {
      next_tile, next_tile_ok = drift(tiles, game)
    }

    // a boost means we move one extra tile without incrementing `steps`
    if .BOOST in cur_tile.kind
    {
      if next_tile_ok
      {
        // we only move an extra step on .BOOST tiles
        // this is a bit wonky but it will have to do
        // NOTE: This means that .BOOST tiles are useless if they are not two connected
        if .BOOST in next_tile.kind
        {
          drift(tiles, game)
        }
      }
    }

    level.steps += 1
  }

  // drifting means we disregard the players direction and find the first available tile
  drift :: proc(tiles: []Tile, game: ^Game) -> (^Tile, bool)
  {
    dirs: Dirs = {.DOWN, .LEFT, .RIGHT, .UP}
    for dir in dirs
    {
      next_pos := game.player.pos + Dir_Vecs[dir]

      // we can't go backwards
      if next_pos == game.player.prev_pos
      {
        if .SLOW not_in game.player.effects
        {
          continue
        }
      }

      next_tile, next_tile_valid := find_tile_pos(tiles, next_pos)
      if next_tile_valid
      {
        commit_move(next_tile, &game.player)
        return next_tile, true
      }
    }

    assert(false, fmt.tprintf("player failed to drift in assets.LEVELS[%v] @ %v:", game.level_cur, game.player.pos))

    return {}, false
  }

  commit_move :: proc(to: ^Tile, player: ^Player)
  {
    if .SLOW not_in player.effects
    {
      player.prev_pos = player.pos
    }
    player.pos = to.pos

    // drifting to a non-.TELEPORT tile resets the cooldown
    if .TELEPORT not_in to.kind
    {
      player.effects -= {.TELEPORT_COOLDOWN}
    }
  }
}

gameplay_handle_input :: proc(game: ^Game, input: Input, timer: ^Timer)
{
  if .ESC in input.keys
  {
    gameplay_restart_game(game)
  }

  switch game.state
  {
  case .MENU:
    handle_menu_input(game, input)

  case .DEAD:
    handle_dead_input(game, input)

  case .WIN:
    handle_win_input(game, input)

  case .PLAY:
    handle_play_input(game, input, timer)

  }
}

@(private)
handle_play_input :: proc(game: ^Game, input: Input, timer: ^Timer)
{
  if .LEFT in input.keys
  {
    game.player.dir = .LEFT
  }
  if .RIGHT in input.keys
  {
    game.player.dir = .RIGHT
  }
  if .DOWN in input.keys
  {
    game.player.dir = .DOWN
  }

  if .R in input.keys
  {
    gameplay_start_level(&G.GAME, game.level_cur)
  }

  if .SPACE in input.keys
  {
    timer.speed = 3
  }
  else
  {
    timer.speed = 1
  }
}

@(private)
handle_menu_input :: proc(game: ^Game, input: Input)
{
  if .RETURN in input.keys
  {
    gameplay_start_level(game, game.level_cur + 1)
  }

  if .R in input.keys
  {
    gameplay_start_level(&G.GAME, game.level_cur)
  }
}

@(private)
handle_dead_input :: proc(game: ^Game, input: Input)
{
  if .R in input.keys
  {
    gameplay_start_level(&G.GAME, game.level_cur)
  }
}

@(private)
handle_win_input :: proc(game: ^Game, input: Input)
{
  if .R in input.keys
  {
    gameplay_restart_game(game)
  }
}

gameplay_win :: proc(game: ^Game)
{
  game.state = .WIN
}

gameplay_hot_reloaded :: proc(game: ^Game)
{
  gameplay_init(game)
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
text_default_color :: proc()
{
  sdtx.color3b(155, 255, 255)
}

@(private)
text_dead_color :: proc()
{
  sdtx.color3b(255, 0, 0)
}

@(private)
parse_level :: proc(game: ^Game, level_idx: int)
{
  level: Level
  tile_id: Entity_Id

  level_asset := assets.LEVELS[level_idx]
  level.text = level_asset.text
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

  // map one tile to another - a teleport
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

      tile: Tile
      tile.id = tile_id
      tile.pos = pos

      /**/ if pixel == {255, 255, 0, 255}
      {
        assert(!start_set, fmt.tprintf("multiple starts found in assets.LEVELS[%v]", level_idx))
        start_set = true

        tile.kind += {.START}
        tile.sprite = .START
      }
      else if pixel == {0, 115, 255, 255}
      {
        tile.kind += {.STREAM}
        tile.sprite = .STREAM
      }
      else if pixel == {0, 115, 115, 255}
      {
        tile.kind += {.BOOST}
        tile.sprite = .BOOST
      }
      else if pixel == {0, 60, 255, 255}
      {
        tile.kind += {.SLOW}
        tile.sprite = .SLOW
      }
      else if pixel == {0, 175, 255, 255}
      {
        tile.kind += {.CROSSING}
        tile.sprite = .CROSSING
      }
      else if pixel == {255, 0, 0, 255}
      {
        tile.kind += {.DEATH}
        tile.sprite = .DEATH
      }
      else if pixel == {0, 255, 0, 255}
      {
        assert(!goal_set, fmt.tprintf("multiple goals found in assets.LEVELS[%v]", level_idx))
        goal_set = true

        tile.kind += {.GOAL}
        tile.sprite = .GOAL
      }
      else if pixel[3] == 254 // encode teleporters as two matching pixels with 254 transparency
      {
        tile.kind += {.TELEPORT}
        tile.sprite = .TELEPORT
        teleport := teleports[pixel]
        teleport.connection[teleport.len] = tile.id
        teleport.len += 1

        teleports[pixel] = teleport

        assert(teleport.len < 3, fmt.tprintf("incorrect number of teleports found in assets.LEVELS[%v] @ %v: %v", level_idx, pos, pixel))

        // connect the teleports
        if teleport.len == 2
        {
          fmt.printfln("%v", teleport)
          prev_teleport, prev_teleport_ok := find_tile_id(level.tiles[:level.len], teleport.connection[0])

          assert(prev_teleport_ok, fmt.tprintf("could not connect teleports in assets.LEVELS[%v]", level_idx))

          prev_teleport.teleport_to = tile.id
          tile.teleport_to = prev_teleport.id
        }
      }
      else
      {
        assert(false, fmt.tprintf("incorrect pixel color found in assets.LEVELS[%v] @ %v: %v", level_idx, pos, pixel))
      }

      level.tiles[level.len] = tile
      level.len += 1
      tile_id += 1
    }
  }

  assert(start_set, fmt.tprintf("start not found for assets.LEVEL[%v]", level_idx))
  assert(goal_set, fmt.tprintf("goal not found for assets.LEVEL[%v]", level_idx))

  game.levels[level_idx] = level
}

@(private, require_results)
find_tile_id :: proc(tiles: []Tile, id: Entity_Id) -> (^Tile, bool)
{
  for &tile in tiles
  {
    if tile.id == id do return &tile, true
  }
  return {}, false
}

@(private, require_results)
find_tile_start :: proc(tiles: []Tile) -> (^Tile, bool)
{
  for &tile in tiles
  {
    if .START in tile.kind do return &tile, true
  }
  return {}, false
}

@(private, require_results)
find_tile_goal :: proc(tiles: []Tile) -> (^Tile, bool)
{
  for &tile in tiles
  {
    if .GOAL in tile.kind do return &tile, true
  }
  return {}, false
}

@(private, require_results)
find_tile_pos :: proc(tiles: []Tile, pos: Pos) -> (^Tile, bool)
{
  for &tile in tiles
  {
    if tile.pos == pos do return &tile, true
  }
  return {}, false
}

@(private, require_results)
has_tile :: proc(tiles: []Tile, pos: Pos) -> bool
{
  for &tile in tiles
  {
    if tile.pos == pos do return true
  }
  return false
}
