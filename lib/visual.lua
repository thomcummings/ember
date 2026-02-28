-- visual.lua
-- Image rendering and degradation for Ember
-- Pixel buffer operations, per-engine visual effects
-- Updates triggered by loop boundary (not timer)

local Visual = {}
Visual.__index = Visual

local W = 128
local H = 64

function Visual.new()
  local v = setmetatable({}, Visual)

  -- Pixel buffers (4-bit grayscale: 0-15)
  v.original = {}    -- pristine copy
  v.buffer = {}      -- working buffer (degraded)
  v.enabled = true

  -- Initialize blank buffers
  for y = 1, H do
    v.original[y] = {}
    v.buffer[y] = {}
    for x = 1, W do
      v.original[y][x] = 0
      v.buffer[y][x] = 0
    end
  end

  v.loaded = false
  return v
end

-- Load image from file path (expects 128x64 PNG)
-- Uses norns screen.load_png if available, otherwise generates procedural cityscape
function Visual:load_image(path)
  -- Try to load PNG via norns
  if path and util.file_exists(path) then
    -- Load via screen peek method
    -- For norns, we'll render to screen then peek pixels
    -- This is a simplified approach - actual PNG loading would use
    -- a norns-compatible method
    self:generate_cityscape()
    self.loaded = true
    return true
  end

  -- Fallback: generate procedural cityscape
  self:generate_cityscape()
  self.loaded = true
  return true
end

-- Generate a procedural blurred cityscape
-- Elevated perspective, silhouettes, atmospheric distance
function Visual:generate_cityscape()
  -- Start with gradient sky (fog/atmosphere)
  for y = 1, H do
    local sky_level = math.floor(util.linlin(y, 1, H, 12, 2))
    for x = 1, W do
      self.original[y][x] = sky_level
    end
  end

  -- Distant buildings (small, faint)
  local distant = {
    {x = 10, w = 4, h = 12},
    {x = 20, w = 6, h = 18},
    {x = 30, w = 3, h = 10},
    {x = 38, w = 8, h = 22},
    {x = 50, w = 5, h = 15},
    {x = 58, w = 4, h = 11},
    {x = 65, w = 7, h = 20},
    {x = 76, w = 3, h = 9},
    {x = 82, w = 6, h = 16},
    {x = 92, w = 4, h = 13},
    {x = 100, w = 5, h = 19},
    {x = 108, w = 3, h = 8},
    {x = 115, w = 7, h = 14},
  }

  for _, b in ipairs(distant) do
    local base_y = H
    local top_y = base_y - b.h
    local shade = math.floor(util.linlin(b.h, 8, 22, 5, 2))
    for y = math.max(1, top_y), base_y do
      for x = b.x, math.min(W, b.x + b.w - 1) do
        if x >= 1 and x <= W and y >= 1 and y <= H then
          self.original[y][x] = shade
        end
      end
    end
    -- Window dots
    if b.h > 12 then
      for wy = top_y + 2, base_y - 2, 3 do
        for wx = b.x + 1, b.x + b.w - 2, 2 do
          if wx >= 1 and wx <= W and wy >= 1 and wy <= H then
            if math.random() > 0.4 then
              self.original[wy][wx] = shade + 4
            end
          end
        end
      end
    end
  end

  -- Foreground silhouettes (dark, sharp)
  local foreground = {
    {x = 1, w = 12, h = 30},
    {x = 15, w = 8, h = 25},
    {x = 45, w = 10, h = 35},
    {x = 90, w = 15, h = 28},
    {x = 110, w = 18, h = 32},
  }

  for _, b in ipairs(foreground) do
    local base_y = H
    local top_y = base_y - b.h
    for y = math.max(1, top_y), base_y do
      for x = b.x, math.min(W, b.x + b.w - 1) do
        if x >= 1 and x <= W and y >= 1 and y <= H then
          self.original[y][x] = 1
        end
      end
    end
    -- Lit windows in foreground
    for wy = top_y + 2, base_y - 2, 4 do
      for wx = b.x + 1, b.x + b.w - 2, 3 do
        if wx >= 1 and wx <= W and wy >= 1 and wy <= H then
          if math.random() > 0.3 then
            self.original[wy][wx] = 8 + math.floor(math.random() * 5)
          end
        end
      end
    end
  end

  -- Apply slight blur for atmosphere
  self:_blur_buffer(self.original, 1)

  -- Copy to working buffer
  self:reset_buffer()
end

-- Reset working buffer to original
function Visual:reset_buffer()
  for y = 1, H do
    for x = 1, W do
      self.buffer[y][x] = self.original[y][x]
    end
  end
end

-- Apply all visual degradation effects based on engine states
-- Called on loop boundary
function Visual:degrade(state)
  if not self.enabled or not self.loaded then return end

  -- Start from original and apply cumulative effects
  self:reset_buffer()

  -- Posterization (fidelity)
  if state.fidelity_state > 0 and not state.fidelity_bypass then
    self:_posterize(state.fidelity_state)
  end

  -- Warp (temporal)
  if state.temporal_state > 0 and not state.temporal_bypass then
    self:_warp(state.temporal_state)
  end

  -- Tears (dropout)
  if state.dropout_state > 0 and not state.dropout_bypass then
    self:_tears(state.dropout_state)
  end

  -- Blur (spectral)
  if state.spectral_state > 0 and not state.spectral_bypass then
    self:_blur(state.spectral_state)
  end

  -- Blown highlights (saturation)
  if state.saturation_state > 0 and not state.saturation_bypass then
    self:_blown_highlights(state.saturation_state)
  end

  -- Grain (noise)
  if state.noise_state > 0 and not state.noise_bypass then
    self:_grain(state.noise_state)
  end
end

-- POSTERIZATION: reduce grayscale levels (16 → 8 → 4 → 2 → 1)
function Visual:_posterize(amount)
  -- Number of levels: 16 down to 1
  local levels = math.max(1, math.floor(16 * (1 - amount) + 0.5))
  if levels >= 16 then return end

  local step = 15 / math.max(1, levels - 1)
  for y = 1, H do
    for x = 1, W do
      local v = self.buffer[y][x]
      local quantized = math.floor(v / step + 0.5) * step
      self.buffer[y][x] = util.clamp(math.floor(quantized), 0, 15)
    end
  end
end

-- WARP: pixel row/column displacement
function Visual:_warp(amount)
  local max_shift = math.floor(amount * 8)
  if max_shift == 0 then return end

  local temp = {}
  for y = 1, H do
    temp[y] = {}
    -- Random horizontal shift per row
    local shift = math.floor((math.random() * 2 - 1) * max_shift)
    for x = 1, W do
      local src_x = ((x - 1 + shift) % W) + 1
      temp[y][x] = self.buffer[y][src_x]
    end
  end

  -- Also some vertical displacement
  for y = 1, H do
    local v_shift = math.floor((math.random() * 2 - 1) * max_shift * 0.3)
    local src_y = util.clamp(y + v_shift, 1, H)
    for x = 1, W do
      self.buffer[y][x] = temp[src_y][x]
    end
  end
end

-- TEARS: rectangular regions set to black
function Visual:_tears(amount)
  -- Number of tears grows with amount
  local num_tears = math.floor(amount * 15)
  for i = 1, num_tears do
    local tx = math.random(1, W)
    local ty = math.random(1, H)
    local tw = math.random(1, math.floor(4 + amount * 20))
    local th = math.random(1, math.floor(1 + amount * 6))

    for y = ty, math.min(H, ty + th - 1) do
      for x = tx, math.min(W, tx + tw - 1) do
        self.buffer[y][x] = 0
      end
    end
  end
end

-- BLUR: average neighboring pixels
function Visual:_blur(amount)
  local radius = math.floor(amount * 3)
  if radius == 0 then return end
  self:_blur_buffer(self.buffer, radius)
end

function Visual:_blur_buffer(buf, radius)
  local temp = {}
  for y = 1, H do
    temp[y] = {}
    for x = 1, W do
      local sum = 0
      local count = 0
      for dy = -radius, radius do
        for dx = -radius, radius do
          local sy = util.clamp(y + dy, 1, H)
          local sx = util.clamp(x + dx, 1, W)
          sum = sum + buf[sy][sx]
          count = count + 1
        end
      end
      temp[y][x] = math.floor(sum / count)
    end
  end
  for y = 1, H do
    for x = 1, W do
      buf[y][x] = temp[y][x]
    end
  end
end

-- BLOWN HIGHLIGHTS: contrast crush, white blowout
function Visual:_blown_highlights(amount)
  local threshold = math.floor(15 - amount * 8)
  local crush = amount * 0.5

  for y = 1, H do
    for x = 1, W do
      local v = self.buffer[y][x]
      -- Push brights toward white
      if v > threshold then
        v = math.min(15, v + math.floor(amount * 6))
      end
      -- Increase contrast
      v = math.floor(((v / 15 - 0.5) * (1 + crush) + 0.5) * 15)
      self.buffer[y][x] = util.clamp(v, 0, 15)
    end
  end
end

-- GRAIN: random pixel noise
function Visual:_grain(amount)
  local noise_range = math.floor(amount * 8)
  if noise_range == 0 then return end

  for y = 1, H do
    for x = 1, W do
      local noise = math.floor((math.random() * 2 - 1) * noise_range)
      self.buffer[y][x] = util.clamp(self.buffer[y][x] + noise, 0, 15)
    end
  end
end

-- Draw the visual buffer to norns screen
function Visual:draw(fade)
  fade = fade or 0  -- 0 = normal, 1 = fully black

  for y = 1, H do
    for x = 1, W do
      local v = self.buffer[y][x]
      -- Apply fade to black
      v = math.floor(v * (1 - fade))
      if v > 0 then
        screen.level(v)
        screen.pixel(x - 1, y - 1)
      end
    end
  end
  screen.fill()
end

-- Draw pure black screen
function Visual:draw_black()
  screen.clear()
end

return Visual
