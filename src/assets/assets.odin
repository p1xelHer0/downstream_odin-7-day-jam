package asset

ATLAS_TILE_SIZE :: 16

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
  .BEEP = {
    bytes = #load("BEEP.ogg"),
  }
}

@(rodata)
ATLAS := Asset {
  bytes = #load("ATLAS.png"),
}

Sprite :: struct
{
  location: [2]int,
  size:   [2]int,
}

Sprite_Name :: enum
{
  ZERO,
  WIZARD,
}

SPRITE := #partial [Sprite_Name]Sprite {
  .WIZARD = {
    location = [2]int{22, 5} * ATLAS_TILE_SIZE,
    size   = [2]int{1, 1} * ATLAS_TILE_SIZE,
  }
}

Level :: struct
{
  data: string,
}

@(rodata)
LEVELS := [?]Level {
  1 = {data = #load("level_1", string)},
}
