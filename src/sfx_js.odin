#+private
package downstream

import "assets"

foreign import sfxjs "sfx"

SFX_Audio :: struct{}

foreign sfxjs
{
  @(link_name="sfx_init")
  _sfx_init :: proc "contextless" () ---

  @(link_name="sfx_play_sound")
  _sfx_play_sound :: proc "contextless" (sound: assets.Sound_Name) ---
}
