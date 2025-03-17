package downstream

import "assets"

sfx_init :: proc()
{
  _sfx_init()
}

sfx_play_sound :: proc(sound: assets.Sound_Name)
{
  _sfx_play_sound(sound)
}
