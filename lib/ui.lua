-- ui.lua
-- Interface and navigation for Ember
-- 13 pages, control mapping, parameter overlay

local UI = {}
UI.__index = UI

-- Page definitions
UI.pages = {
  {name = "IMAGE",      poetic = "ember",      params = {}},
  {name = "SAMPLE",     poetic = "source",     params = {"slot", "file"}},
  {name = "LOOP",       poetic = "loop",       params = {"start", "length", "quantize"}},
  {name = "PLAYBACK",   poetic = "voice",      params = {"speed", "level", "pan", "width"}},
  {name = "FIDELITY",   poetic = "clarity",    params = {"rate", "correlation", "curve", "bypass"}},
  {name = "TEMPORAL",   poetic = "stability",  params = {"rate", "wow", "flutter", "drift"}},
  {name = "DROPOUT",    poetic = "erosion",    params = {"rate", "pattern", "length", "frequency"}},
  {name = "SPECTRAL",   poetic = "presence",   params = {"rate", "target", "resonance", "scoop"}},
  {name = "SATURATION", poetic = "heat",       params = {"rate", "max", "asymmetry", "warmth"}},
  {name = "NOISE",      poetic = "dust",       params = {"rate", "hiss", "crackle", "correlation"}},
  {name = "ROOM",       poetic = "space",      params = {"rate", "size", "wet", "damping"}},
  {name = "HEALTH",     poetic = "memory",     params = {"threshold", "death_mode"}},
  {name = "MASTER",     poetic = "master",     params = {"speed", "mode", "duration"}},
  {name = "PRESETS",    poetic = "presets",     params = {"selection"}},
}

function UI.new()
  local u = setmetatable({}, UI)
  u.current_page = 1
  u.current_param = 1
  u.key_shift = false      -- K1 held
  u.key2_held = false      -- K2 held

  -- Parameter overlay
  u.overlay_text = nil
  u.overlay_page = nil
  u.overlay_timer = 0
  u.overlay_duration = 2.0  -- seconds

  -- Settings menu
  u.settings_open = false

  -- Death screen state
  u.death_screen = false
  u.death_timer = 0
  u.black_screen = false
  u.fade_to_black = 0       -- 0-1

  -- Preset selection
  u.preset_index = 1

  return u
end

-- Get current page definition
function UI:page()
  return self.pages[self.current_page]
end

-- Get current page name
function UI:page_name()
  return self.pages[self.current_page].name
end

-- Get current param name
function UI:param_name()
  local p = self:page()
  return p.params[self.current_param]
end

-- Navigate pages
function UI:next_page()
  self.current_page = (self.current_page % #self.pages) + 1
  self.current_param = 1
end

function UI:prev_page()
  self.current_page = ((self.current_page - 2) % #self.pages) + 1
  self.current_param = 1
end

function UI:set_page(n)
  self.current_page = util.clamp(n, 1, #self.pages)
  self.current_param = 1
end

-- Navigate params within page
function UI:next_param()
  local p = self:page()
  self.current_param = util.clamp(self.current_param + 1, 1, #p.params)
end

function UI:prev_param()
  self.current_param = util.clamp(self.current_param - 1, 1, 1)
end

function UI:set_param(n)
  local p = self:page()
  self.current_param = util.clamp(n, 1, #p.params)
end

-- Show parameter overlay
function UI:show_overlay(page_name, param_name, value)
  self.overlay_page = page_name
  self.overlay_text = param_name .. ": " .. tostring(value)
  self.overlay_timer = self.overlay_duration
end

-- Update overlay timer
function UI:update_overlay(dt)
  if self.overlay_timer > 0 then
    self.overlay_timer = self.overlay_timer - dt
    if self.overlay_timer <= 0 then
      self.overlay_text = nil
      self.overlay_page = nil
    end
  end
end

-- Death screen sequence
function UI:update_death(dt)
  if not self.death_screen then return false end

  self.death_timer = self.death_timer + dt

  -- Phase 1: Hold degraded image (0-10s after reverb tail ends)
  -- Phase 2: Fade to black (10-15s)
  -- Phase 3: Pure black (15s+)
  if self.death_timer > 10 and self.death_timer <= 15 then
    self.fade_to_black = (self.death_timer - 10) / 5.0
  elseif self.death_timer > 15 then
    self.fade_to_black = 1.0
    self.black_screen = true
  end

  return true
end

-- Start death screen
function UI:begin_death()
  self.death_screen = true
  self.death_timer = 0
  self.fade_to_black = 0
  self.black_screen = false
end

-- Reset death screen (resurrect)
function UI:end_death()
  self.death_screen = false
  self.death_timer = 0
  self.fade_to_black = 0
  self.black_screen = false
end

-- Format value for display
function UI:format_value(param, value)
  if type(value) == "boolean" then
    return value and "on" or "off"
  elseif type(value) == "number" then
    if param == "rate" or param == "correlation" or param == "curve"
      or param == "asymmetry" or param == "warmth" or param == "resonance"
      or param == "wet" or param == "damping" or param == "size" then
      return string.format("%.2f", value)
    elseif param == "target" then
      if value >= 1000 then
        return string.format("%.1fk", value / 1000)
      else
        return string.format("%dHz", math.floor(value))
      end
    elseif param == "hiss" then
      return string.format("%ddB", math.floor(value))
    elseif param == "level" then
      return string.format("%d%%", math.floor(value * 100))
    elseif param == "pan" then
      if value == 0 then return "C"
      elseif value < 0 then return string.format("L%d", math.floor(math.abs(value) * 100))
      else return string.format("R%d", math.floor(value * 100))
      end
    elseif param == "speed" then
      return string.format("%.2fx", value)
    elseif param == "start" or param == "length" then
      return string.format("%.1fs", value)
    elseif param == "threshold" then
      return string.format("%d%%", math.floor(value))
    elseif param == "wow" or param == "flutter" then
      return string.format("%d¢", math.floor(value))
    elseif param == "length" and value < 1 then
      return string.format("%dms", math.floor(value * 1000))
    elseif param == "crackle" or param == "frequency" then
      return string.format("%.1f/s", value)
    else
      return string.format("%.2f", value)
    end
  elseif type(value) == "string" then
    return value
  end
  return tostring(value)
end

return UI
