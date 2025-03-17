#+build !js
#+private
package downstream

import "core:fmt"

import ma "vendor:miniaudio"

import "assets"

// Use native channel count and sample rate of the device
SFX_CHANNELS :: 0
SFX_SAMPLE_RATE :: 0

SFX_Resource :: struct
{
  sound:   ma.sound,
  decoder: ma.decoder,
}

SFX_Audio :: struct
{
  engine:  ma.engine,
  resources: [BUDGET_SFX_RESOURCES]SFX_Resource,
  next_slot: int,
  len:     int,
}

_sfx_init :: proc()
{
  audio := &G.AUDIO

  engine_config := ma.engine_config_init()
  engine_config.channels = SFX_CHANNELS
  engine_config.sampleRate = SFX_SAMPLE_RATE
  engine_config.listenerCount = 1
  engine_init_result := ma.engine_init(&engine_config, &audio.engine)
  if engine_init_result != .SUCCESS
  {
    fmt.eprintfln("failed to init miniaudio `ma.engine`: %v", engine_init_result)
  }

  engine_start_result := ma.engine_start(&audio.engine)
  if engine_start_result != .SUCCESS
  {
    fmt.eprintfln("failed to start miniaudio `ma.engine`: %v", engine_start_result)
  }
}

_sfx_play_sound :: proc(sound_name: assets.Sound_Name)
{
  audio := &G.AUDIO
  format := ma.encoding_format.vorbis
  volume := f32(0.1)

  resource_slot := &audio.resources[audio.next_slot]

  // `next_slot` wraps around - make sure we uninit everything before overwriting it
  if ma.sound_is_playing(&resource_slot.sound)
  {
    ma.sound_stop(&resource_slot.sound)
    ma.sound_uninit(&resource_slot.sound)
    ma.decoder_uninit(&resource_slot.decoder)
    resource_slot^ = {}
  }

  sound_bytes := assets.SOUND[sound_name].bytes

  decoder_config := ma.decoder_config_init(
    outputFormat = .f32,
    outputChannels = ma.engine_get_channels(&audio.engine),
    outputSampleRate = audio.engine.sampleRate,
  )
  decoder_config.encodingFormat = format
  decoder_result := ma.decoder_init_memory(
    pData = raw_data(sound_bytes),
    dataSize = len(sound_bytes),
    pConfig = &decoder_config,
    pDecoder = &resource_slot.decoder,
  )
  if decoder_result != .SUCCESS
  {
    fmt.eprintfln("failed to init `ma.decoder` for sound: %v - %v", sound_name, decoder_result)
    resource_slot = {}
    return
  }

  sound_result := ma.sound_init_from_data_source(
    pEngine = &audio.engine,
    pDataSource = resource_slot.decoder.ds.pCurrent,
    flags = {},
    pGroup = {},
    pSound = &resource_slot.sound,
  )
  if sound_result != .SUCCESS
  {
    fmt.eprintfln("failed to init `ma.sound` for sound: %v - %v", sound_name, sound_result)
    ma.decoder_uninit(&resource_slot.decoder)
    resource_slot = {}
    return
  }

  ma.sound_set_volume(&resource_slot.sound, volume)
  ma.sound_start(&resource_slot.sound)

  // wrap around `next_slot`
  audio.next_slot = (audio.next_slot + 1) % BUDGET_SFX_RESOURCES
  audio.len = min(audio.len + 1, BUDGET_SFX_RESOURCES)
}
