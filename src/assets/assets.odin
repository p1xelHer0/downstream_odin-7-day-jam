package asset

ATLAS_TILE_SIZE :: 8
ATLAS_TILE :: [2]int {ATLAS_TILE_SIZE, ATLAS_TILE_SIZE}

LEVEL_PNG_WIDTH  :: 40
LEVEL_PNG_HEIGHT :: 23

Asset :: struct
{
  bytes: []u8,
}

Sound_Name :: enum
{
  BEEP
}

Music_Name :: enum {}

@(rodata)
SOUND := #partial[Sound_Name]Asset {
  // .BEEP = {
  //   bytes = #load("BEEP.ogg"),
  // }
}

@(rodata)
ATLAS := Asset {
  bytes = #load("ATLAS.png"),
}

Sprite :: struct
{
  location: [2]int,
  size:     [2]int,
}

Sprite_Name :: enum
{
  PLAYER,
  START,
  STREAM,
  CROSSING,
  BOOST,
  SLOW,
  TELEPORT,
  GOAL,
  WIN,
}

SPRITE := #partial [Sprite_Name]Sprite {
  .PLAYER = {
    location = [2]int{0, 0},
    size     = ATLAS_TILE,
  },
  .START = {
    location = [2]int{0, 3},
    size     = ATLAS_TILE,
  },
  .STREAM = {
    location = [2]int{0, 2},
    size     = ATLAS_TILE,
  },
  .CROSSING = {
    location = [2]int{1, 3},
    size     = ATLAS_TILE,
  },
  .BOOST = {
    location = [2]int{0, 4},
    size     = ATLAS_TILE,
  },
  .SLOW = {
    location = [2]int{1, 4},
    size     = ATLAS_TILE,
  },
  .TELEPORT = {
    location = [2]int{3, 2},
    size     = ATLAS_TILE,
  },
  .GOAL = {
    location = [2]int{1, 2},
    size     = ATLAS_TILE,
  },
  .WIN = {
    location = [2]int{2, 0},
    size     = ATLAS_TILE,
  },
}

Level :: struct
{
  bytes: []u8,
}

@(rodata)
LEVELS := [?]Level {
  // {bytes = #load("level_1.png")},
  // {bytes = #load("level_2.png")},
  // {bytes = #load("level_3.png")},
  // {bytes = #load("level_4.png")},
  {bytes = #load("level_5.png")},
}
