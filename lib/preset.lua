-- preset.lua
-- Preset save/load for Ember
-- Factory presets define "tape type" degradation characters

local Preset = {}
Preset.__index = Preset

-- Paths
local FACTORY_PATH = _path.code .. "ember/presets/factory/"
local USER_PATH = _path.code .. "ember/presets/user/"

function Preset.new()
  local p = setmetatable({}, Preset)
  p.factory = {}
  p.user = {}
  p.all = {}  -- combined list for UI
  return p
end

-- Initialize: load factory presets, scan user presets
function Preset:init()
  self.factory = Preset.get_factory_presets()
  self:scan_user_presets()
  self:rebuild_list()
end

-- Rebuild combined preset list
function Preset:rebuild_list()
  self.all = {}
  for _, p in ipairs(self.factory) do
    table.insert(self.all, {name = p.name, data = p.data, factory = true})
  end
  for _, p in ipairs(self.user) do
    table.insert(self.all, {name = p.name, data = p.data, factory = false})
  end
end

-- Get preset by index
function Preset:get(index)
  return self.all[index]
end

-- Count
function Preset:count()
  return #self.all
end

-- Scan user preset directory
function Preset:scan_user_presets()
  self.user = {}
  -- Ensure directory exists
  os.execute("mkdir -p " .. USER_PATH)

  local files = util.scandir(USER_PATH)
  if files then
    for _, f in ipairs(files) do
      if f:match("%.lua$") then
        local name = f:gsub("%.lua$", "")
        local ok, data = pcall(dofile, USER_PATH .. f)
        if ok and data then
          table.insert(self.user, {name = name, data = data})
        end
      end
    end
  end
end

-- Save user preset
function Preset:save(name, degradation)
  local data = degradation:get_preset_data()
  local filepath = USER_PATH .. name .. ".lua"

  local file = io.open(filepath, "w")
  if file then
    file:write("-- ember preset: " .. name .. "\n")
    file:write("return {\n")
    for k, v in pairs(data) do
      if type(v) == "string" then
        file:write("  " .. k .. ' = "' .. v .. '",\n')
      elseif type(v) == "boolean" then
        file:write("  " .. k .. " = " .. tostring(v) .. ",\n")
      else
        file:write("  " .. k .. " = " .. tostring(v) .. ",\n")
      end
    end
    file:write("}\n")
    file:close()

    -- Rescan
    self:scan_user_presets()
    self:rebuild_list()
    return true
  end
  return false
end

-- Delete user preset
function Preset:delete(index)
  local preset = self.all[index]
  if not preset or preset.factory then return false end

  local filepath = USER_PATH .. preset.name .. ".lua"
  os.remove(filepath)

  self:scan_user_presets()
  self:rebuild_list()
  return true
end

-- Load preset into degradation state
function Preset:load(index, degradation)
  local preset = self.all[index]
  if not preset then return false end
  degradation:apply_preset(preset.data)
  return true
end

-- Factory preset definitions
function Preset.get_factory_presets()
  return {
    -- Archival: Very slow, gentle fade
    {
      name = "Archival",
      data = {
        fidelity_rate = 0.15, temporal_rate = 0.1, dropout_rate = 0.05,
        spectral_rate = 0.25, saturation_rate = 0.08, noise_rate = 0.1,
        room_rate = 0.15, width_rate = 0.1, mid_scoop_rate = 0.1,
        fidelity_correlation = 0.6, fidelity_curve = 0.4,
        fidelity_bypass = false,
        wow_depth_max = 30, flutter_depth_max = 15,
        drift_enabled = true, drift_reset = false, temporal_bypass = false,
        dropout_pattern = "random", dropout_max_length = 50,
        dropout_max_frequency = 3, dropout_bypass = false,
        spectral_target = 800, spectral_resonance = 0.05,
        mid_scoop_enabled = false, spectral_bypass = false,
        saturation_max = 6, saturation_asymmetry = 0.1,
        saturation_warmth = 0.3, saturation_bypass = false,
        hiss_max = -40, crackle_max_rate = 5,
        crackle_correlation = 0.5, noise_bypass = false,
        room_size_target = 0.6, room_wet_target = 0.5,
        room_damping_target = 0.6, room_bypass = false,
        width_target = 0.4, width_bypass = false,
        death_threshold = 10, death_mode = "silence",
        decay_mode = "deterministic",
        mystery_mode = false, mystery_range_min = 5, mystery_range_max = 45,
        master_speed = 0.5,
      }
    },
    -- Oxide: Medium, tape-damage character
    {
      name = "Oxide",
      data = {
        fidelity_rate = 0.2, temporal_rate = 0.25, dropout_rate = 0.4,
        spectral_rate = 0.2, saturation_rate = 0.15, noise_rate = 0.35,
        room_rate = 0.1, width_rate = 0.15, mid_scoop_rate = 0.2,
        fidelity_correlation = 0.8, fidelity_curve = 0.5,
        fidelity_bypass = false,
        wow_depth_max = 80, flutter_depth_max = 40,
        drift_enabled = true, drift_reset = false, temporal_bypass = false,
        dropout_pattern = "clustered", dropout_max_length = 200,
        dropout_max_frequency = 12, dropout_bypass = false,
        spectral_target = 600, spectral_resonance = 0.1,
        mid_scoop_enabled = true, spectral_bypass = false,
        saturation_max = 12, saturation_asymmetry = 0.4,
        saturation_warmth = 0.6, saturation_bypass = false,
        hiss_max = -28, crackle_max_rate = 25,
        crackle_correlation = 0.8, noise_bypass = false,
        room_size_target = 0.3, room_wet_target = 0.25,
        room_damping_target = 0.4, room_bypass = false,
        width_target = 0.3, width_bypass = false,
        death_threshold = 10, death_mode = "silence",
        decay_mode = "deterministic",
        mystery_mode = false, mystery_range_min = 5, mystery_range_max = 45,
        master_speed = 1.0,
      }
    },
    -- Thermal: Warm then harsh, saturation-forward
    {
      name = "Thermal",
      data = {
        fidelity_rate = 0.15, temporal_rate = 0.15, dropout_rate = 0.2,
        spectral_rate = 0.15, saturation_rate = 0.45, noise_rate = 0.2,
        room_rate = 0.25, width_rate = 0.2, mid_scoop_rate = 0.15,
        fidelity_correlation = 0.5, fidelity_curve = 0.6,
        fidelity_bypass = false,
        wow_depth_max = 60, flutter_depth_max = 30,
        drift_enabled = true, drift_reset = false, temporal_bypass = false,
        dropout_pattern = "even", dropout_max_length = 100,
        dropout_max_frequency = 6, dropout_bypass = false,
        spectral_target = 700, spectral_resonance = 0.15,
        mid_scoop_enabled = false, spectral_bypass = false,
        saturation_max = 22, saturation_asymmetry = 0.5,
        saturation_warmth = 0.8, saturation_bypass = false,
        hiss_max = -35, crackle_max_rate = 10,
        crackle_correlation = 0.6, noise_bypass = false,
        room_size_target = 0.5, room_wet_target = 0.45,
        room_damping_target = 0.5, room_bypass = false,
        width_target = 0.25, width_bypass = false,
        death_threshold = 10, death_mode = "collapse",
        decay_mode = "deterministic",
        mystery_mode = false, mystery_range_min = 5, mystery_range_max = 45,
        master_speed = 1.0,
      }
    },
    -- Glacial: Extremely slow (20+ min), all engines minimal
    {
      name = "Glacial",
      data = {
        fidelity_rate = 0.08, temporal_rate = 0.06, dropout_rate = 0.05,
        spectral_rate = 0.07, saturation_rate = 0.05, noise_rate = 0.06,
        room_rate = 0.1, width_rate = 0.05, mid_scoop_rate = 0.05,
        fidelity_correlation = 0.5, fidelity_curve = 0.3,
        fidelity_bypass = false,
        wow_depth_max = 40, flutter_depth_max = 20,
        drift_enabled = true, drift_reset = false, temporal_bypass = false,
        dropout_pattern = "random", dropout_max_length = 80,
        dropout_max_frequency = 3, dropout_bypass = false,
        spectral_target = 400, spectral_resonance = 0.05,
        mid_scoop_enabled = false, spectral_bypass = false,
        saturation_max = 8, saturation_asymmetry = 0.2,
        saturation_warmth = 0.4, saturation_bypass = false,
        hiss_max = -45, crackle_max_rate = 5,
        crackle_correlation = 0.4, noise_bypass = false,
        room_size_target = 0.95, room_wet_target = 0.85,
        room_damping_target = 0.9, room_bypass = false,
        width_target = 0.15, width_bypass = false,
        death_threshold = 5, death_mode = "silence",
        decay_mode = "deterministic",
        mystery_mode = false, mystery_range_min = 5, mystery_range_max = 45,
        master_speed = 0.25,
      }
    },
    -- Cascade: Medium-fast, chaotic, dropout-heavy
    {
      name = "Cascade",
      data = {
        fidelity_rate = 0.3, temporal_rate = 0.35, dropout_rate = 0.5,
        spectral_rate = 0.3, saturation_rate = 0.25, noise_rate = 0.4,
        room_rate = 0.45, width_rate = 0.3, mid_scoop_rate = 0.25,
        fidelity_correlation = 0.9, fidelity_curve = 0.7,
        fidelity_bypass = false,
        wow_depth_max = 150, flutter_depth_max = 70,
        drift_enabled = true, drift_reset = false, temporal_bypass = false,
        dropout_pattern = "clustered", dropout_max_length = 350,
        dropout_max_frequency = 18, dropout_bypass = false,
        spectral_target = 300, spectral_resonance = 0.2,
        mid_scoop_enabled = true, spectral_bypass = false,
        saturation_max = 18, saturation_asymmetry = 0.4,
        saturation_warmth = 0.5, saturation_bypass = false,
        hiss_max = -25, crackle_max_rate = 35,
        crackle_correlation = 0.9, noise_bypass = false,
        room_size_target = 0.9, room_wet_target = 0.9,
        room_damping_target = 0.7, room_bypass = false,
        width_target = 0.1, width_bypass = false,
        death_threshold = 15, death_mode = "collapse",
        decay_mode = "stochastic",
        mystery_mode = false, mystery_range_min = 5, mystery_range_max = 45,
        master_speed = 1.5,
      }
    },
    -- Dust: Noise-dominant
    {
      name = "Dust",
      data = {
        fidelity_rate = 0.1, temporal_rate = 0.1, dropout_rate = 0.15,
        spectral_rate = 0.2, saturation_rate = 0.1, noise_rate = 0.5,
        room_rate = 0.2, width_rate = 0.15, mid_scoop_rate = 0.1,
        fidelity_correlation = 0.5, fidelity_curve = 0.5,
        fidelity_bypass = false,
        wow_depth_max = 50, flutter_depth_max = 25,
        drift_enabled = true, drift_reset = false, temporal_bypass = false,
        dropout_pattern = "random", dropout_max_length = 120,
        dropout_max_frequency = 8, dropout_bypass = false,
        spectral_target = 600, spectral_resonance = 0.08,
        mid_scoop_enabled = false, spectral_bypass = false,
        saturation_max = 10, saturation_asymmetry = 0.2,
        saturation_warmth = 0.3, saturation_bypass = false,
        hiss_max = -22, crackle_max_rate = 40,
        crackle_correlation = 0.7, noise_bypass = false,
        room_size_target = 0.5, room_wet_target = 0.4,
        room_damping_target = 0.7, room_bypass = false,
        width_target = 0.3, width_bypass = false,
        death_threshold = 10, death_mode = "silence",
        decay_mode = "stochastic",
        mystery_mode = false, mystery_range_min = 5, mystery_range_max = 45,
        master_speed = 1.0,
      }
    },
  }
end

return Preset
