-- degradation.lua
-- Degradation state management for Ember
-- Tracks health, all 7 engine states, loop cycle counting
-- Degradation applied as step changes at loop boundaries

local Degradation = {}
Degradation.__index = Degradation

function Degradation.new()
  local d = setmetatable({}, Degradation)

  -- Engine states (0.0 = pristine, 1.0 = fully degraded)
  d.fidelity_state = 0.0
  d.temporal_state = 0.0
  d.dropout_state = 0.0
  d.spectral_state = 0.0
  d.saturation_state = 0.0
  d.noise_state = 0.0
  d.room_state = 0.0
  d.width_state = 0.0
  d.mid_scoop_state = 0.0

  -- Engine rates (0.0-1.0, speed of degradation)
  d.fidelity_rate = 0.3
  d.temporal_rate = 0.3
  d.dropout_rate = 0.3
  d.spectral_rate = 0.3
  d.saturation_rate = 0.3
  d.noise_rate = 0.3
  d.room_rate = 0.3
  d.width_rate = 0.2
  d.mid_scoop_rate = 0.3

  -- Fidelity params
  d.fidelity_correlation = 0.7
  d.fidelity_curve = 0.5
  d.fidelity_bypass = false

  -- Temporal params
  d.wow_depth_max = 100     -- cents
  d.flutter_depth_max = 50  -- cents
  d.drift_enabled = true
  d.drift_reset = false
  d.drift_val = 0            -- accumulated drift in cents
  d.temporal_bypass = false

  -- Dropout params
  d.dropout_pattern = "clustered"  -- even/clustered/random
  d.dropout_max_length = 200       -- ms
  d.dropout_max_frequency = 10     -- events/sec
  d.dropout_bypass = false

  -- Spectral params
  d.spectral_target = 500          -- Hz
  d.spectral_resonance = 0.1
  d.mid_scoop_enabled = false
  d.spectral_bypass = false

  -- Saturation params
  d.saturation_max = 18            -- dB
  d.saturation_asymmetry = 0.3
  d.saturation_warmth = 0.5
  d.saturation_bypass = false

  -- Noise params
  d.hiss_max = -30                 -- dB
  d.crackle_max_rate = 20          -- events/sec
  d.crackle_correlation = 0.8
  d.noise_bypass = false

  -- Room params
  d.room_size_target = 0.9
  d.room_wet_target = 0.8          -- 0-1 (80%)
  d.room_damping_target = 0.8
  d.room_bypass = false

  -- Width params
  d.width_target = 0.2             -- 0-1 (20%)
  d.width_bypass = false

  -- Health system
  d.health = 100.0
  d.death_threshold = 10.0
  d.death_mode = "silence"         -- silence/freeze/collapse
  d.is_dead = false
  d.is_dying = false               -- collapse in progress

  -- Loop tracking
  d.loop_count = 0
  d.total_degradation_time = 600   -- seconds (default 10 min)
  d.estimated_cycles = 0           -- calculated from loop length

  -- Decay mode
  d.decay_mode = "deterministic"   -- deterministic/stochastic/mystery
  d.mystery_mode = false
  d.mystery_range_min = 5          -- minutes
  d.mystery_range_max = 45         -- minutes
  d.mystery_chosen_time = nil      -- secretly chosen duration

  -- Stochastic params
  d.stochastic_plateau_chance = 0.15
  d.stochastic_accel_chance = 0.10
  d.stochastic_regress_chance = 0.02

  -- Master
  d.master_speed = 1.0

  -- Callbacks
  d.on_death = nil
  d.on_health_change = nil

  return d
end

-- Calculate step increment per loop cycle
-- Called when play starts or loop length changes
function Degradation:calculate_step(loop_length)
  if loop_length <= 0 then return end
  local total_time = self.total_degradation_time
  if self.mystery_mode and self.mystery_chosen_time then
    total_time = self.mystery_chosen_time
  end
  total_time = total_time / self.master_speed
  self.estimated_cycles = math.max(1, math.floor(total_time / loop_length))
end

-- Apply one degradation step (called on loop boundary)
function Degradation:step(loop_length)
  if self.is_dead then return end
  if self.loop_count == 0 then
    -- First loop is always pristine
    self.loop_count = 1
    return
  end

  self.loop_count = self.loop_count + 1

  -- Recalculate step size
  self:calculate_step(loop_length)
  if self.estimated_cycles == 0 then return end

  local base_increment = 1.0 / self.estimated_cycles

  -- Apply stochastic variation if enabled
  local multiplier = 1.0
  if self.decay_mode == "stochastic" then
    multiplier = self:_stochastic_multiplier()
  end

  -- Step each engine
  self:_step_engine("fidelity", base_increment * multiplier)
  self:_step_engine("temporal", base_increment * multiplier)
  self:_step_engine("dropout", base_increment * multiplier)
  self:_step_engine("spectral", base_increment * multiplier)
  self:_step_engine("saturation", base_increment * multiplier)
  self:_step_engine("noise", base_increment * multiplier)
  self:_step_engine("room", base_increment * multiplier)
  self:_step_engine("width", base_increment * multiplier)

  -- Mid-scoop follows its own rate
  if self.mid_scoop_enabled then
    self.mid_scoop_state = math.min(1.0, self.mid_scoop_state + base_increment * self.mid_scoop_rate * multiplier)
  end

  -- Drift accumulation (random walk per loop)
  if self.drift_enabled and not self.temporal_bypass then
    local drift_range = util.linlin(self.temporal_state, 0, 1, 0.1, 5) -- cents per loop
    self.drift_val = self.drift_val + (math.random() * 2 - 1) * drift_range
    if self.drift_reset then
      -- Partial reset toward 0
      self.drift_val = self.drift_val * 0.9
    end
  end

  -- Calculate health
  self:calculate_health()

  -- Check death
  if self.health <= self.death_threshold and not self.is_dead then
    self:trigger_death()
  end
end

-- Step a single engine
function Degradation:_step_engine(name, base_increment)
  local rate_key = name .. "_rate"
  local state_key = name .. "_state"
  local bypass_key = name .. "_bypass"

  if self[bypass_key] then return end

  local rate = self[rate_key] or 0.3
  local increment = base_increment * rate

  -- Apply curve shaping for fidelity
  if name == "fidelity" and self.fidelity_curve ~= 0.5 then
    local curve_factor = 1.0 + (self.fidelity_curve - 0.5) * 4.0
    increment = increment * (1.0 + self[state_key] * curve_factor)
  end

  self[state_key] = math.min(1.0, self[state_key] + increment)
end

-- Stochastic multiplier
function Degradation:_stochastic_multiplier()
  local r = math.random()
  if r < self.stochastic_regress_chance then
    return -0.5  -- brief healing
  elseif r < self.stochastic_regress_chance + self.stochastic_plateau_chance then
    return 0     -- pause
  elseif r < self.stochastic_regress_chance + self.stochastic_plateau_chance + self.stochastic_accel_chance then
    return 2.0 + math.random() * 2.0  -- sudden jump
  end
  return 0.8 + math.random() * 0.4  -- normal with slight variation
end

-- Calculate health (weighted average of engine states)
-- Room does NOT affect health
function Degradation:calculate_health()
  local degradation_total = (
    self.fidelity_state * 0.25 +
    self.temporal_state * 0.15 +
    self.dropout_state * 0.20 +
    self.spectral_state * 0.20 +
    self.saturation_state * 0.10 +
    self.noise_state * 0.10
  )
  self.health = math.max(0, (1.0 - degradation_total) * 100.0)

  if self.on_health_change then
    self.on_health_change(self.health)
  end
end

-- Trigger death sequence
function Degradation:trigger_death()
  self.is_dead = true
  if self.death_mode == "collapse" then
    self.is_dying = true
  end
  if self.on_death then
    self.on_death(self.death_mode)
  end
end

-- Collapse step: rapid final degradation
-- Returns true when collapse is complete
function Degradation:collapse_step(dt)
  if not self.is_dying then return true end

  local rapid = dt * 0.3  -- fast
  self.fidelity_state = math.min(1.0, self.fidelity_state + rapid)
  self.temporal_state = math.min(1.0, self.temporal_state + rapid)
  self.dropout_state = math.min(1.0, self.dropout_state + rapid)
  self.spectral_state = math.min(1.0, self.spectral_state + rapid)
  self.saturation_state = math.min(1.0, self.saturation_state + rapid)
  self.noise_state = math.min(1.0, self.noise_state + rapid)

  self:calculate_health()

  if self.health <= 0 then
    self.is_dying = false
    return true
  end
  return false
end

-- Initialize mystery mode (secretly choose duration)
function Degradation:init_mystery()
  if not self.mystery_mode then return end
  local min_s = self.mystery_range_min * 60
  local max_s = self.mystery_range_max * 60
  self.mystery_chosen_time = min_s + math.random() * (max_s - min_s)
end

-- Reset to pristine
function Degradation:reset()
  self.fidelity_state = 0.0
  self.temporal_state = 0.0
  self.dropout_state = 0.0
  self.spectral_state = 0.0
  self.saturation_state = 0.0
  self.noise_state = 0.0
  self.room_state = 0.0
  self.width_state = 0.0
  self.mid_scoop_state = 0.0
  self.drift_val = 0
  self.health = 100.0
  self.is_dead = false
  self.is_dying = false
  self.loop_count = 0
  self.mystery_chosen_time = nil
end

-- Get all state as a flat table (for engine communication)
function Degradation:get_state()
  return {
    fidelity_state = self.fidelity_state,
    fidelity_correlation = self.fidelity_correlation,
    fidelity_curve = self.fidelity_curve,
    fidelity_bypass = self.fidelity_bypass,
    temporal_state = self.temporal_state,
    wow_depth_max = self.wow_depth_max,
    flutter_depth_max = self.flutter_depth_max,
    drift_enabled = self.drift_enabled,
    drift_val = self.drift_val,
    temporal_bypass = self.temporal_bypass,
    dropout_state = self.dropout_state,
    dropout_max_length = self.dropout_max_length,
    dropout_max_frequency = self.dropout_max_frequency,
    dropout_bypass = self.dropout_bypass,
    spectral_state = self.spectral_state,
    spectral_target = self.spectral_target,
    spectral_resonance = self.spectral_resonance,
    mid_scoop_enabled = self.mid_scoop_enabled,
    mid_scoop_state = self.mid_scoop_state,
    spectral_bypass = self.spectral_bypass,
    saturation_state = self.saturation_state,
    saturation_max = self.saturation_max,
    saturation_asymmetry = self.saturation_asymmetry,
    saturation_warmth = self.saturation_warmth,
    saturation_bypass = self.saturation_bypass,
    noise_state = self.noise_state,
    hiss_max = self.hiss_max,
    crackle_max_rate = self.crackle_max_rate,
    crackle_correlation = self.crackle_correlation,
    noise_bypass = self.noise_bypass,
    room_state = self.room_state,
    room_size_target = self.room_size_target,
    room_wet_target = self.room_wet_target,
    room_damping_target = self.room_damping_target,
    room_bypass = self.room_bypass,
    width_state = self.width_state,
    width_target = self.width_target,
    width_bypass = self.width_bypass,
  }
end

-- Get degradation parameters only (for presets)
function Degradation:get_preset_data()
  return {
    -- Rates
    fidelity_rate = self.fidelity_rate,
    temporal_rate = self.temporal_rate,
    dropout_rate = self.dropout_rate,
    spectral_rate = self.spectral_rate,
    saturation_rate = self.saturation_rate,
    noise_rate = self.noise_rate,
    room_rate = self.room_rate,
    width_rate = self.width_rate,
    mid_scoop_rate = self.mid_scoop_rate,
    -- Fidelity
    fidelity_correlation = self.fidelity_correlation,
    fidelity_curve = self.fidelity_curve,
    fidelity_bypass = self.fidelity_bypass,
    -- Temporal
    wow_depth_max = self.wow_depth_max,
    flutter_depth_max = self.flutter_depth_max,
    drift_enabled = self.drift_enabled,
    drift_reset = self.drift_reset,
    temporal_bypass = self.temporal_bypass,
    -- Dropout
    dropout_pattern = self.dropout_pattern,
    dropout_max_length = self.dropout_max_length,
    dropout_max_frequency = self.dropout_max_frequency,
    dropout_bypass = self.dropout_bypass,
    -- Spectral
    spectral_target = self.spectral_target,
    spectral_resonance = self.spectral_resonance,
    mid_scoop_enabled = self.mid_scoop_enabled,
    spectral_bypass = self.spectral_bypass,
    -- Saturation
    saturation_max = self.saturation_max,
    saturation_asymmetry = self.saturation_asymmetry,
    saturation_warmth = self.saturation_warmth,
    saturation_bypass = self.saturation_bypass,
    -- Noise
    hiss_max = self.hiss_max,
    crackle_max_rate = self.crackle_max_rate,
    crackle_correlation = self.crackle_correlation,
    noise_bypass = self.noise_bypass,
    -- Room
    room_size_target = self.room_size_target,
    room_wet_target = self.room_wet_target,
    room_damping_target = self.room_damping_target,
    room_bypass = self.room_bypass,
    -- Width
    width_target = self.width_target,
    width_bypass = self.width_bypass,
    -- Death
    death_threshold = self.death_threshold,
    death_mode = self.death_mode,
    -- Mode
    decay_mode = self.decay_mode,
    mystery_mode = self.mystery_mode,
    mystery_range_min = self.mystery_range_min,
    mystery_range_max = self.mystery_range_max,
    -- Master
    master_speed = self.master_speed,
    total_degradation_time = self.total_degradation_time,
  }
end

-- Apply preset data
function Degradation:apply_preset(data)
  for k, v in pairs(data) do
    if self[k] ~= nil then
      self[k] = v
    end
  end
  self:reset()
end

return Degradation
