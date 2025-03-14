package game

BUDGET_GFX_SPRITES :: 40 * 23 * 2 // two sprites on each tiles should be enough for now

BUDGET_GAMEPLAY_TILES  :: (40 * 23) / 4 // let's assume we never fill more than 1/4 of the screen with tiles for now
BUDGET_GAMEPLAY_LEVELS :: 10

// game, swapchain, sdtx
BUDGET_PIPELINE_POOL   :: 1 + 1 + 1
BUDGET_BUFFER_POOL     :: 3 + 2 + 1
BUDGET_IMAGE_POOL      :: 3 + 1
BUDGET_SAMPLER_POOL    :: 1 + 1 + 1
BUDGET_SHADER_POOL     :: 1 + 1 + 1
BUDGET_ATTACHMENT_POOL :: 1
