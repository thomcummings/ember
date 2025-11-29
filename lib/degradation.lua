-- degradation.lua
-- Manages degradation state and health for Ember
-- Phase 1: Single head, fidelity only

local Degradation = {}
Degradation.__index = Degradation

-- Create a new degradation state manager
function Degradation.new()
  local d = {
    -- Fidelity degradation (Phase 1)
    fidelity_state = 0.0,        -- Current degradation level (0.0 = pristine, 1.0 = destroyed)
    fidelity_rate = 0.01,        -- Speed of degradation
    fidelity_correlation = 0.7,  -- Bit/sample coupling (0.0-1.0)
    fidelity_curve = 0.5,        -- Exponential steepness (0.0-1.0)

    -- Temporal (Phase 2)
    temporal_state = 0.0,
    temporal_rate = 0.01,

    -- Dropout (Phase 2)
    dropout_state = 0.0,
    dropout_rate = 0.01,

    -- Spectral (Phase 2)
    spectral_state = 0.0,
    spectral_rate = 0.01,

    -- Saturation (Phase 2)
    saturation_state = 0.0,
    saturation_rate = 0.01,

    -- Noise (Phase 2)
    noise_state = 0.0,
    noise_rate = 0.01,

    -- Health tracking
    health = 100.0,
    is_dead = false,
    death_threshold = 10.0,

    -- Active degradation flag
    active = false,
  }

  setmetatable(d, Degradation)
  return d
end

-- Update degradation state (called each frame)
-- dt: delta time in seconds
function Degradation:update(dt)
  if not self.active then
    return
  end

  -- Phase 1: Only fidelity degradation
  if self.fidelity_state < 1.0 then
    -- Increment based on rate and delta time
    -- Rate is scaled so 1.0 = complete degradation in ~60 seconds
    local increment = self.fidelity_rate * dt / 60.0

    -- Apply curve to make degradation exponential or linear
    -- curve = 0.5 is linear, > 0.5 is slower start/fast end, < 0.5 is fast start/slow end
    if self.fidelity_curve ~= 0.5 then
      -- Apply exponential shaping
      local progress = self.fidelity_state
      local curve_factor = 1.0 + (self.fidelity_curve - 0.5) * 4.0
      increment = increment * (1.0 + progress * curve_factor)
    end

    self.fidelity_state = math.min(1.0, self.fidelity_state + increment)
  end

  -- Calculate health (weighted combination of all degradation states)
  self:calculate_health()

  -- Check for death
  if self.health <= self.death_threshold and not self.is_dead then
    self.is_dead = true
    self:on_death()
  end
end

-- Calculate overall health from degradation states
function Degradation:calculate_health()
  -- Health formula from spec:
  -- health = (fidelity * 0.25 + temporal * 0.15 + dropout * 0.20 +
  --           spectral * 0.20 + saturation * 0.10 + noise * 0.10)
  -- Result: 100% (pristine) → 0% (dead)

  local degradation_total = (
    self.fidelity_state * 0.25 +
    self.temporal_state * 0.15 +
    self.dropout_state * 0.20 +
    self.spectral_state * 0.20 +
    self.saturation_state * 0.10 +
    self.noise_state * 0.10
  )

  self.health = (1.0 - degradation_total) * 100.0
end

-- Death callback (override in main script)
function Degradation:on_death()
  -- Will be overridden in main script to handle death behavior
end

-- Reset all degradation to pristine state
function Degradation:reset()
  self.fidelity_state = 0.0
  self.temporal_state = 0.0
  self.dropout_state = 0.0
  self.spectral_state = 0.0
  self.saturation_state = 0.0
  self.noise_state = 0.0

  self.health = 100.0
  self.is_dead = false
end

-- Start degradation
function Degradation:start()
  self.active = true
end

-- Stop degradation
function Degradation:stop()
  self.active = false
end

-- Get state for a specific engine
function Degradation:get_state(engine)
  if engine == "fidelity" then
    return self.fidelity_state
  elseif engine == "temporal" then
    return self.temporal_state
  elseif engine == "dropout" then
    return self.dropout_state
  elseif engine == "spectral" then
    return self.spectral_state
  elseif engine == "saturation" then
    return self.saturation_state
  elseif engine == "noise" then
    return self.noise_state
  end
  return 0.0
end

-- Set rate for a specific engine
function Degradation:set_rate(engine, rate)
  rate = util.clamp(rate, 0.0, 1.0)

  if engine == "fidelity" then
    self.fidelity_rate = rate
  elseif engine == "temporal" then
    self.temporal_rate = rate
  elseif engine == "dropout" then
    self.dropout_rate = rate
  elseif engine == "spectral" then
    self.spectral_rate = rate
  elseif engine == "saturation" then
    self.saturation_rate = rate
  elseif engine == "noise" then
    self.noise_rate = rate
  end
end

-- Get rate for a specific engine
function Degradation:get_rate(engine)
  if engine == "fidelity" then
    return self.fidelity_rate
  elseif engine == "temporal" then
    return self.temporal_rate
  elseif engine == "dropout" then
    return self.dropout_rate
  elseif engine == "spectral" then
    return self.spectral_rate
  elseif engine == "saturation" then
    return self.saturation_rate
  elseif engine == "noise" then
    return self.noise_rate
  end
  return 0.0
end

return Degradation
