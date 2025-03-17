(function() {
  // NOTE: Match these with the assets.Sound_Name
  const ATTACK_SWORD_1  = 0;

  class SFX {
    constructor(mem) {
      this.mem = mem;

      this.audioCtx = new AudioContext();

      this.sounds = {};
    }

    async load(idx, filepath) {
      try {
        const response = await fetch(filepath);
        const buffer   = await this.audioCtx.decodeAudioData(await response.arrayBuffer());
        this.sounds[idx] = buffer;
      } catch (err) {
        console.error("failed to decodeAudioData: " + filepath, err);
      }
    }

    getInterface() {
      return {
        sfx_init: async () => {
          this.load(ATTACK_SWORD_1, "human_atk_sword_1.ogg");
        },
        sfx_play_sound: (sound) => {
          const source = this.audioCtx.createBufferSource();
          source.buffer = this.sounds[sound];
          source.connect(this.audioCtx.destination);
          source.start();
        },
      };
    }
  }

  window.odin = window.odin || {};
  window.odin.SFX = SFX;
})();
