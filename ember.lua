-- EMBER
-- Basinski-style loop disintegration
-- Phase 1: Single head, fidelity only
--
-- E2: Select parameter
-- E3: Change value
-- K2: Next page
-- K3: Start/stop playback
-- K1+K3: Load sample

engine.name = "Ember"

local Degradation = require("lib/degradation")

-- State
local degradation
local playing = false
local current_page = 1
local current_param = 1
local ui_dirty = true
local ui_fade_timer = 0
local key_shift = false

-- Loop parameters
local loop_start = 0.0
local loop_length = 1.0
local level = 0.8

-- Sample management
local sample_loaded = false
local sample_name = "none"

-- Pages
local pages = {
  {name = "SAMPLE", params = {"load"}},
  {name = "LOOP", params = {"start", "length"}},
  {name = "FIDELITY", params = {"rate", "curve", "correlation"}},
  {name = "HEALTH", params = {"threshold", "status"}},
}

-- Metro for degradation updates
local degradation_metro

function init()
  -- Initialize degradation state
  degradation = Degradation.new()

  -- Death callback
  degradation.on_death = function(self)
    -- For Phase 1: just stop playback on death
    playing = false
    engine.stop()
  end

  -- Set up degradation metro (15 fps update)
  degradation_metro = metro.init()
  degradation_metro.time = 1/15
  degradation_metro.event = function()
    if playing then
      degradation:update(1/15)
      engine.fidelityState(degradation.fidelity_state)
      ui_dirty = true
    end
  end
  degradation_metro:start()

  -- Redraw metro (15 fps)
  local redraw_metro = metro.init()
  redraw_metro.time = 1/15
  redraw_metro.event = function()
    if ui_dirty then
      redraw()
      ui_dirty = false
    end
  end
  redraw_metro:start()

  print("EMBER initialized - Phase 1")
  print("Load a sample with K1+K3")
end

function cleanup()
  degradation_metro:stop()
end

-- Load a sample
function load_sample()
  -- For Phase 1, use fileselect to choose a sample
  fileselect.enter(_path.audio, function(path)
    if path ~= "cancel" then
      engine.loadSample(path)
      sample_loaded = true
      sample_name = path:match("^.+/(.+)$") or path
      print("Loaded: " .. sample_name)

      -- Set default loop to entire sample (will need buffer info later)
      loop_start = 0.0
      loop_length = 4.0  -- Default 4 seconds
      engine.loopStart(loop_start)
      engine.loopLength(loop_length)

      ui_dirty = true
    end
  end)
end

-- Start/stop playback
function toggle_playback()
  if not sample_loaded then
    print("No sample loaded")
    return
  end

  playing = not playing

  if playing then
    engine.start()
    degradation:start()
    print("Playing")
  else
    engine.stop()
    degradation:stop()
    print("Stopped")
  end

  ui_dirty = true
end

-- Reset degradation to pristine
function reset_degradation()
  degradation:reset()
  engine.fidelityState(0.0)
  print("Reset to pristine")
  ui_dirty = true
end

-- Encoders
function enc(n, d)
  if n == 1 then
    -- E1: Page navigation (will be head selection in Phase 4)
    current_page = util.clamp(current_page + d, 1, #pages)
    current_param = 1
    ui_dirty = true

  elseif n == 2 then
    -- E2: Parameter selection
    local page = pages[current_page]
    current_param = util.clamp(current_param + d, 1, #page.params)
    ui_dirty = true

  elseif n == 3 then
    -- E3: Parameter value
    local page = pages[current_page]
    local param = page.params[current_param]

    if current_page == 2 then -- LOOP page
      if param == "start" then
        loop_start = util.clamp(loop_start + d * 0.1, 0.0, 60.0)
        engine.loopStart(loop_start)
      elseif param == "length" then
        loop_length = util.clamp(loop_length + d * 0.1, 0.1, 60.0)
        engine.loopLength(loop_length)
      end

    elseif current_page == 3 then -- FIDELITY page
      if param == "rate" then
        local new_rate = util.clamp(degradation.fidelity_rate + d * 0.001, 0.0, 1.0)
        degradation:set_rate("fidelity", new_rate)
      elseif param == "curve" then
        degradation.fidelity_curve = util.clamp(degradation.fidelity_curve + d * 0.01, 0.0, 1.0)
      elseif param == "correlation" then
        degradation.fidelity_correlation = util.clamp(degradation.fidelity_correlation + d * 0.01, 0.0, 1.0)
      end

    elseif current_page == 4 then -- HEALTH page
      if param == "threshold" then
        degradation.death_threshold = util.clamp(degradation.death_threshold + d * 1.0, 0.0, 100.0)
      end
    end

    ui_dirty = true
  end
end

-- Keys
function key(n, z)
  if z == 1 then -- Key down
    if n == 2 then
      -- K2: Next page
      current_page = (current_page % #pages) + 1
      current_param = 1
      ui_dirty = true

    elseif n == 3 then
      if key_shift then
        -- K1+K3: Load sample
        load_sample()
      else
        -- K3: Context action
        local page = pages[current_page]

        if current_page == 1 then -- SAMPLE page
          load_sample()
        elseif current_page == 4 then -- HEALTH page
          if current_param == 2 then -- status param
            reset_degradation()
          else
            toggle_playback()
          end
        else
          toggle_playback()
        end
      end
      ui_dirty = true

    elseif n == 1 then
      key_shift = true
    end

  else -- Key up
    if n == 1 then
      key_shift = false
    end
  end
end

-- Draw UI
function redraw()
  screen.clear()

  local page = pages[current_page]

  -- Header
  screen.level(15)
  screen.move(0, 8)
  screen.text("EMBER")

  -- Page indicator
  screen.move(128, 8)
  screen.text_right(page.name)

  -- Health bar (top right corner)
  local health_width = math.floor(degradation.health * 0.3)
  screen.level(degradation.is_dead and 2 or 8)
  screen.move(98, 2)
  screen.line_rel(health_width, 0)
  screen.stroke()

  -- Status indicators
  screen.level(4)
  screen.move(0, 16)
  screen.text(playing and "▶" or "■")

  if sample_loaded then
    screen.move(10, 16)
    screen.level(8)
    screen.text(sample_name:sub(1, 18))
  end

  -- Draw page content
  local y_start = 28

  if current_page == 1 then
    -- SAMPLE page
    draw_param("load sample", current_param == 1, y_start, "K3")

  elseif current_page == 2 then
    -- LOOP page
    draw_param("start", current_param == 1, y_start, string.format("%.1fs", loop_start))
    draw_param("length", current_param == 2, y_start + 12, string.format("%.1fs", loop_length))

  elseif current_page == 3 then
    -- FIDELITY page
    draw_param("rate", current_param == 1, y_start, string.format("%.3f", degradation.fidelity_rate))
    draw_param("curve", current_param == 2, y_start + 12, string.format("%.2f", degradation.fidelity_curve))
    draw_param("correlation", current_param == 3, y_start + 24, string.format("%.2f", degradation.fidelity_correlation))

    -- Degradation visualization
    screen.level(2)
    screen.move(0, 56)
    screen.line(128, 56)
    screen.stroke()

    local deg_width = math.floor(degradation.fidelity_state * 128)
    screen.level(10)
    screen.move(0, 56)
    screen.line(deg_width, 56)
    screen.stroke()

    screen.level(6)
    screen.move(0, 64)
    screen.text(string.format("fidelity: %.1f%%", (1.0 - degradation.fidelity_state) * 100))

  elseif current_page == 4 then
    -- HEALTH page
    draw_param("death threshold", current_param == 1, y_start, string.format("%.0f%%", degradation.death_threshold))

    -- Health status
    screen.level(current_param == 2 and 15 or 8)
    screen.move(0, y_start + 12)
    screen.text("status")
    screen.move(128, y_start + 12)
    if degradation.is_dead then
      screen.level(2)
      screen.text_right("DEAD")
    else
      screen.level(10)
      screen.text_right(string.format("%.0f%%", degradation.health))
    end

    -- Health bar visualization
    screen.level(2)
    screen.rect(0, 50, 128, 8)
    screen.stroke()

    local health_bar_width = math.floor(degradation.health * 1.28)
    local bar_level = 10
    if degradation.health < degradation.death_threshold then
      bar_level = 4
    elseif degradation.health < 30 then
      bar_level = 6
    end
    screen.level(bar_level)
    screen.rect(0, 50, health_bar_width, 8)
    screen.fill()

    -- Reset hint
    screen.level(4)
    screen.move(64, 64)
    screen.text_center("K3: reset")
  end

  screen.update()
end

-- Helper: draw a parameter row
function draw_param(name, selected, y, value)
  screen.level(selected and 15 or 8)
  screen.move(0, y)
  screen.text(name)

  screen.move(128, y)
  screen.text_right(value)
end
