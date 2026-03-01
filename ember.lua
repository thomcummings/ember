-- EMBER
-- loop disintegration instrument
--
-- the dying is the point
-- the ending matters
-- leave room for the accident
--
-- E1: page
-- E2: select parameter
-- E3: adjust value
-- K2: play/pause
-- K3: context action (load, bypass, etc)
-- K1+K3: reset head to start

engine.name = "Ember"

-- add script's own directory to package.path so require finds lib/*
local script_dir = norns.state.path
package.path = script_dir .. "lib/?.lua;" .. package.path

local fileselect = require("fileselect")
local EmberEngine = require("ember_engine")
local Degradation = require("degradation")
local Visual = require("visual")
local UI_module = require("ui")
local Preset = require("preset")

-- State
local deg = nil          -- degradation state
local vis = nil          -- visual system
local ui = nil           -- UI state
local presets = nil       -- preset manager

-- Sample management
local sample_slots = {"none", "none", "none", "none"}
local sample_durations = {0, 0, 0, 0}
local current_slot = 1

-- Playback
local playing = false
local loop_start = 0.0
local loop_length = 4.0
local speed = 1.0
local level = 0.8
local pan = 0.0
local quantize_mode = "free"

-- Redraw
local screen_dirty = true
local redraw_metro = nil
local death_metro = nil

-- Settings
local visual_enabled = true

----------------------------------------------
-- INIT
----------------------------------------------
function init()
  -- Initialize modules
  deg = Degradation.new()
  vis = Visual.new()
  ui = UI_module.new()
  presets = Preset.new()
  presets:init()

  -- Generate default cityscape
  vis:generate_cityscape()

  -- Death callback
  deg.on_death = function(mode)
    on_death(mode)
  end

  -- Health change callback
  deg.on_health_change = function(health)
    screen_dirty = true
  end

  -- OSC listener for loop wrap
  osc.event = function(path, args, from)
    if path == "/ember/loop_wrap" then
      on_loop_wrap(args)
    elseif path == "/ember/buffer_info" then
      on_buffer_info(args)
    end
  end

  -- Redraw metro (15 fps)
  redraw_metro = metro.init()
  redraw_metro.time = 1/15
  redraw_metro.event = function()
    -- Update overlay fade
    ui:update_overlay(1/15)

    -- Update death screen
    if ui.death_screen then
      ui:update_death(1/15)
      screen_dirty = true
    end

    -- Collapse animation
    if deg.is_dying and playing then
      local done = deg:collapse_step(1/15)
      EmberEngine.apply_degradation(deg:get_state())
      vis:degrade(deg:get_state())
      if done then
        playing = false
        EmberEngine.begin_death_tail()
        -- Start death tail timer
        death_tail_start()
      end
      screen_dirty = true
    end

    if screen_dirty then
      redraw()
      screen_dirty = false
    end
  end
  redraw_metro:start()

  -- Build params
  build_params()

  print("ember: initialized")
  print("ember: load a sample to begin")
end

function cleanup()
  if redraw_metro then redraw_metro:stop() end
  if death_metro then death_metro:stop() end
end

----------------------------------------------
-- PARAMS
----------------------------------------------
function build_params()
  params:add_separator("ember")

  -- Sample
  params:add_group("sample", "SAMPLE", 1)
  params:add_file("sample_file", "sample", _path.audio)
  params:set_action("sample_file", function(path)
    if path ~= "none" and path ~= "" then
      load_sample(current_slot, path)
    end
  end)

  -- Playback
  params:add_group("playback", "PLAYBACK", 4)
  params:add_control("loop_start", "loop start", controlspec.new(0, 180, 'lin', 0.01, 0, 's'))
  params:set_action("loop_start", function(v) loop_start = v; engine.loopStart(v) end)
  params:add_control("loop_length", "loop length", controlspec.new(0.1, 180, 'exp', 0.01, 4, 's'))
  params:set_action("loop_length", function(v) loop_length = v; engine.loopLength(v) end)
  params:add_control("speed", "speed", controlspec.new(0.25, 2.0, 'lin', 0.01, 1.0, 'x'))
  params:set_action("speed", function(v) speed = v; engine.speed(v) end)
  params:add_control("level", "level", controlspec.new(0, 1, 'lin', 0.01, 0.8))
  params:set_action("level", function(v) level = v; engine.level(v) end)

  -- Fidelity
  params:add_group("fidelity", "FIDELITY", 4)
  params:add_control("fidelity_rate", "rate", controlspec.new(0, 1, 'lin', 0.01, 0.3))
  params:set_action("fidelity_rate", function(v) deg.fidelity_rate = v end)
  params:add_control("fidelity_correlation", "correlation", controlspec.new(0, 1, 'lin', 0.01, 0.7))
  params:set_action("fidelity_correlation", function(v) deg.fidelity_correlation = v end)
  params:add_control("fidelity_curve", "curve", controlspec.new(0, 1, 'lin', 0.01, 0.5))
  params:set_action("fidelity_curve", function(v) deg.fidelity_curve = v end)
  params:add_option("fidelity_bypass", "bypass", {"off", "on"}, 1)
  params:set_action("fidelity_bypass", function(v) deg.fidelity_bypass = (v == 2) end)

  -- Temporal
  params:add_group("temporal", "TEMPORAL", 5)
  params:add_control("temporal_rate", "rate", controlspec.new(0, 1, 'lin', 0.01, 0.3))
  params:set_action("temporal_rate", function(v) deg.temporal_rate = v end)
  params:add_control("wow_depth_max", "wow depth", controlspec.new(0, 200, 'lin', 1, 100, 'cents'))
  params:set_action("wow_depth_max", function(v) deg.wow_depth_max = v end)
  params:add_control("flutter_depth_max", "flutter depth", controlspec.new(0, 100, 'lin', 1, 50, 'cents'))
  params:set_action("flutter_depth_max", function(v) deg.flutter_depth_max = v end)
  params:add_option("drift_enabled", "drift", {"off", "on"}, 2)
  params:set_action("drift_enabled", function(v) deg.drift_enabled = (v == 2) end)
  params:add_option("temporal_bypass", "bypass", {"off", "on"}, 1)
  params:set_action("temporal_bypass", function(v) deg.temporal_bypass = (v == 2) end)

  -- Dropout
  params:add_group("dropout", "DROPOUT", 5)
  params:add_control("dropout_rate", "rate", controlspec.new(0, 1, 'lin', 0.01, 0.3))
  params:set_action("dropout_rate", function(v) deg.dropout_rate = v end)
  params:add_option("dropout_pattern", "pattern", {"even", "clustered", "random"}, 2)
  params:set_action("dropout_pattern", function(v) deg.dropout_pattern = ({"even", "clustered", "random"})[v] end)
  params:add_control("dropout_max_length", "max length", controlspec.new(1, 500, 'exp', 1, 200, 'ms'))
  params:set_action("dropout_max_length", function(v) deg.dropout_max_length = v end)
  params:add_control("dropout_max_frequency", "max freq", controlspec.new(0.1, 20, 'lin', 0.1, 10, '/s'))
  params:set_action("dropout_max_frequency", function(v) deg.dropout_max_frequency = v end)
  params:add_option("dropout_bypass", "bypass", {"off", "on"}, 1)
  params:set_action("dropout_bypass", function(v) deg.dropout_bypass = (v == 2) end)

  -- Spectral
  params:add_group("spectral", "SPECTRAL", 6)
  params:add_control("spectral_rate", "rate", controlspec.new(0, 1, 'lin', 0.01, 0.3))
  params:set_action("spectral_rate", function(v) deg.spectral_rate = v end)
  params:add_control("spectral_target", "target freq", controlspec.new(200, 20000, 'exp', 1, 500, 'Hz'))
  params:set_action("spectral_target", function(v) deg.spectral_target = v end)
  params:add_control("spectral_resonance", "resonance", controlspec.new(0, 0.5, 'lin', 0.01, 0.1))
  params:set_action("spectral_resonance", function(v) deg.spectral_resonance = v end)
  params:add_option("mid_scoop_enabled", "mid scoop", {"off", "on"}, 1)
  params:set_action("mid_scoop_enabled", function(v) deg.mid_scoop_enabled = (v == 2) end)
  params:add_control("mid_scoop_rate", "scoop rate", controlspec.new(0, 1, 'lin', 0.01, 0.3))
  params:set_action("mid_scoop_rate", function(v) deg.mid_scoop_rate = v end)
  params:add_option("spectral_bypass", "bypass", {"off", "on"}, 1)
  params:set_action("spectral_bypass", function(v) deg.spectral_bypass = (v == 2) end)

  -- Saturation
  params:add_group("saturation", "SATURATION", 5)
  params:add_control("saturation_rate", "rate", controlspec.new(0, 1, 'lin', 0.01, 0.3))
  params:set_action("saturation_rate", function(v) deg.saturation_rate = v end)
  params:add_control("saturation_max", "max drive", controlspec.new(0, 24, 'lin', 0.5, 18, 'dB'))
  params:set_action("saturation_max", function(v) deg.saturation_max = v end)
  params:add_control("saturation_asymmetry", "asymmetry", controlspec.new(0, 1, 'lin', 0.01, 0.3))
  params:set_action("saturation_asymmetry", function(v) deg.saturation_asymmetry = v end)
  params:add_control("saturation_warmth", "warmth", controlspec.new(0, 1, 'lin', 0.01, 0.5))
  params:set_action("saturation_warmth", function(v) deg.saturation_warmth = v end)
  params:add_option("saturation_bypass", "bypass", {"off", "on"}, 1)
  params:set_action("saturation_bypass", function(v) deg.saturation_bypass = (v == 2) end)

  -- Noise
  params:add_group("noise", "NOISE", 5)
  params:add_control("noise_rate", "rate", controlspec.new(0, 1, 'lin', 0.01, 0.3))
  params:set_action("noise_rate", function(v) deg.noise_rate = v end)
  params:add_control("hiss_max", "hiss max", controlspec.new(-60, -20, 'lin', 1, -30, 'dB'))
  params:set_action("hiss_max", function(v) deg.hiss_max = v end)
  params:add_control("crackle_max_rate", "crackle rate", controlspec.new(0, 50, 'lin', 1, 20, '/s'))
  params:set_action("crackle_max_rate", function(v) deg.crackle_max_rate = v end)
  params:add_control("crackle_correlation", "correlation", controlspec.new(0, 1, 'lin', 0.01, 0.8))
  params:set_action("crackle_correlation", function(v) deg.crackle_correlation = v end)
  params:add_option("noise_bypass", "bypass", {"off", "on"}, 1)
  params:set_action("noise_bypass", function(v) deg.noise_bypass = (v == 2) end)

  -- Room
  params:add_group("room", "ROOM", 5)
  params:add_control("room_rate", "rate", controlspec.new(0, 1, 'lin', 0.01, 0.3))
  params:set_action("room_rate", function(v) deg.room_rate = v end)
  params:add_control("room_size_target", "size target", controlspec.new(0, 1, 'lin', 0.01, 0.9))
  params:set_action("room_size_target", function(v) deg.room_size_target = v end)
  params:add_control("room_wet_target", "wet target", controlspec.new(0, 1, 'lin', 0.01, 0.8))
  params:set_action("room_wet_target", function(v) deg.room_wet_target = v end)
  params:add_control("room_damping_target", "damping target", controlspec.new(0, 1, 'lin', 0.01, 0.8))
  params:set_action("room_damping_target", function(v) deg.room_damping_target = v end)
  params:add_option("room_bypass", "bypass", {"off", "on"}, 1)
  params:set_action("room_bypass", function(v) deg.room_bypass = (v == 2) end)

  -- Width
  params:add_group("width", "WIDTH", 3)
  params:add_control("width_rate", "rate", controlspec.new(0, 1, 'lin', 0.01, 0.2))
  params:set_action("width_rate", function(v) deg.width_rate = v end)
  params:add_control("width_target", "target", controlspec.new(0, 1, 'lin', 0.01, 0.2))
  params:set_action("width_target", function(v) deg.width_target = v end)
  params:add_option("width_bypass", "bypass", {"off", "on"}, 1)
  params:set_action("width_bypass", function(v) deg.width_bypass = (v == 2) end)

  -- Death
  params:add_group("death", "DEATH", 2)
  params:add_control("death_threshold", "threshold", controlspec.new(0, 100, 'lin', 1, 10, '%'))
  params:set_action("death_threshold", function(v) deg.death_threshold = v end)
  params:add_option("death_mode", "mode", {"silence", "freeze", "collapse"}, 1)
  params:set_action("death_mode", function(v) deg.death_mode = ({"silence", "freeze", "collapse"})[v] end)

  -- Master
  params:add_group("master", "MASTER", 5)
  params:add_control("master_speed", "speed mult", controlspec.new(0.1, 4.0, 'exp', 0.01, 1.0, 'x'))
  params:set_action("master_speed", function(v) deg.master_speed = v end)
  params:add_option("decay_mode", "decay mode", {"deterministic", "stochastic", "mystery"}, 1)
  params:set_action("decay_mode", function(v)
    deg.decay_mode = ({"deterministic", "stochastic", "mystery"})[v]
    deg.mystery_mode = (v == 3)
  end)
  params:add_control("total_degradation_time", "duration", controlspec.new(60, 7200, 'exp', 30, 600, 's'))
  params:set_action("total_degradation_time", function(v) deg.total_degradation_time = v end)
  params:add_control("mystery_range_min", "mystery min", controlspec.new(1, 60, 'lin', 1, 5, 'min'))
  params:set_action("mystery_range_min", function(v) deg.mystery_range_min = v end)
  params:add_control("mystery_range_max", "mystery max", controlspec.new(1, 60, 'lin', 1, 45, 'min'))
  params:set_action("mystery_range_max", function(v) deg.mystery_range_max = v end)
end

----------------------------------------------
-- SAMPLE MANAGEMENT
----------------------------------------------
function load_sample(slot, path)
  EmberEngine.load_sample(slot - 1, path) -- 0-indexed in SC
  sample_slots[slot] = path:match("^.+/(.+)$") or path
  -- Assign immediately so synth always points to a valid buffer
  -- (SC callback will re-assign after read completes and send duration info)
  EmberEngine.assign_slot(slot - 1)
  screen_dirty = true
  print("ember: loading " .. sample_slots[slot] .. " to slot " .. slot)
end

function on_buffer_info(args)
  local slot = args[1] + 1 -- back to 1-indexed
  local duration = args[2]
  sample_durations[slot] = duration
  -- Auto-set loop length to full sample if current is default
  if loop_length == 4.0 and duration > 0 then
    loop_length = math.min(duration, 180)
    engine.loopLength(loop_length)
    params:set("loop_length", loop_length, true)
  end
  print("ember: slot " .. slot .. " duration: " .. string.format("%.1f", duration) .. "s")
end

----------------------------------------------
-- TRANSPORT
----------------------------------------------
function toggle_playback()
  if sample_slots[current_slot] == "none" then
    print("ember: no sample loaded")
    return
  end

  playing = not playing

  if playing then
    -- Initialize mystery mode if needed
    deg:init_mystery()
    -- Calculate step size
    deg:calculate_step(loop_length / speed)
    -- Sync all playback params to engine before starting
    engine.loopStart(loop_start)
    engine.loopLength(loop_length)
    engine.speed(speed)
    engine.level(level)
    engine.pan(pan)
    -- Send pristine degradation state
    EmberEngine.apply_degradation(deg:get_state())
    EmberEngine.start()
  else
    EmberEngine.stop()
  end

  screen_dirty = true
end

function reset_head()
  playing = false
  EmberEngine.stop()
  engine.loopStart(loop_start)
  screen_dirty = true
end

----------------------------------------------
-- LOOP WRAP (OSC from SC engine)
----------------------------------------------
function on_loop_wrap(args)
  if not playing then return end
  if deg.is_dead then return end

  -- Apply degradation step
  deg:step(loop_length / speed)

  -- Send updated state to engine
  EmberEngine.apply_degradation(deg:get_state())

  -- Update visual
  vis:degrade(deg:get_state())

  screen_dirty = true
end

----------------------------------------------
-- DEATH SYSTEM
----------------------------------------------
function on_death(mode)
  print("ember: death (" .. mode .. ")")

  if mode == "silence" then
    playing = false
    EmberEngine.begin_death_tail()
    death_tail_start()
  elseif mode == "freeze" then
    -- Keep playing at current state, no further degradation
    -- (is_dead flag prevents further steps)
  elseif mode == "collapse" then
    -- Collapse handled in redraw metro (is_dying flag)
  end
end

-- Start reverb tail timer (3-5 seconds, then begin death screen)
function death_tail_start()
  if death_metro then death_metro:stop() end
  death_metro = metro.init()
  death_metro.time = 4 -- seconds for reverb tail
  death_metro.count = 1
  death_metro.event = function()
    -- Kill reverb and noise
    EmberEngine.kill_room()
    -- Begin death screen sequence
    ui:begin_death()
    screen_dirty = true
  end
  death_metro:start()
end

-- Resurrect: reset everything
function resurrect()
  print("ember: resurrect")
  deg:reset()
  vis:reset_buffer()
  ui:end_death()
  EmberEngine.resurrect()
  EmberEngine.apply_degradation(deg:get_state())
  playing = false
  screen_dirty = true
end

----------------------------------------------
-- ENCODERS
----------------------------------------------
function enc(n, d)
  if ui.death_screen then return end -- no interaction during death (except keys)

  if n == 1 then
    -- E1: Page selection
    local new_page = util.clamp(ui.current_page + d, 1, #ui.pages)
    ui:set_page(new_page)
    screen_dirty = true

  elseif n == 2 then
    -- E2: Parameter selection
    local new_param = util.clamp(ui.current_param + d, 1, #ui:page().params)
    ui:set_param(new_param)
    screen_dirty = true

  elseif n == 3 then
    -- E3: Parameter value adjustment
    adjust_param(d)
    screen_dirty = true
  end
end

function adjust_param(d)
  local page_name = ui:page_name()
  local param_name = ui:param_name()

  if page_name == "SAMPLE" then
    if param_name == "slot" then
      current_slot = util.clamp(current_slot + d, 1, 4)
      EmberEngine.assign_slot(current_slot - 1)
      show_overlay("slot", current_slot)
    end

  elseif page_name == "LOOP" then
    if not playing then -- loop adjustment only when stopped
      if param_name == "start" then
        loop_start = util.clamp(loop_start + d * 0.1, 0, 180)
        engine.loopStart(loop_start)
        params:set("loop_start", loop_start, true)
        show_overlay("start", string.format("%.1fs", loop_start))
      elseif param_name == "length" then
        loop_length = util.clamp(loop_length + d * 0.1, 0.1, 180)
        engine.loopLength(loop_length)
        params:set("loop_length", loop_length, true)
        show_overlay("length", string.format("%.1fs", loop_length))
      end
    end

  elseif page_name == "PLAYBACK" then
    if param_name == "speed" then
      speed = util.clamp(speed + d * 0.01, 0.25, 2.0)
      engine.speed(speed)
      params:set("speed", speed, true)
      show_overlay("speed", string.format("%.2fx", speed))
    elseif param_name == "level" then
      level = util.clamp(level + d * 0.01, 0, 1)
      engine.level(level)
      params:set("level", level, true)
      show_overlay("level", string.format("%d%%", math.floor(level * 100)))
    elseif param_name == "pan" then
      pan = util.clamp(pan + d * 0.01, -1, 1)
      engine.pan(pan)
      show_overlay("pan", ui:format_value("pan", pan))
    elseif param_name == "width" then
      deg.width_target = util.clamp(deg.width_target + d * 0.01, 0, 1)
      show_overlay("width", string.format("%d%%", math.floor(deg.width_target * 100)))
    end

  elseif page_name == "FIDELITY" then
    adjust_engine_param("fidelity", param_name, d)
  elseif page_name == "TEMPORAL" then
    adjust_engine_param("temporal", param_name, d)
  elseif page_name == "DROPOUT" then
    adjust_engine_param("dropout", param_name, d)
  elseif page_name == "SPECTRAL" then
    adjust_engine_param("spectral", param_name, d)
  elseif page_name == "SATURATION" then
    adjust_engine_param("saturation", param_name, d)
  elseif page_name == "NOISE" then
    adjust_engine_param("noise", param_name, d)
  elseif page_name == "ROOM" then
    adjust_engine_param("room", param_name, d)

  elseif page_name == "HEALTH" then
    if param_name == "threshold" then
      deg.death_threshold = util.clamp(deg.death_threshold + d, 0, 100)
      params:set("death_threshold", deg.death_threshold, true)
      show_overlay("threshold", string.format("%d%%", math.floor(deg.death_threshold)))
    elseif param_name == "death_mode" then
      local modes = {"silence", "freeze", "collapse"}
      local idx = 1
      for i, m in ipairs(modes) do
        if m == deg.death_mode then idx = i; break end
      end
      idx = util.clamp(idx + d, 1, 3)
      deg.death_mode = modes[idx]
      params:set("death_mode", idx, true)
      show_overlay("mode", deg.death_mode)
    end

  elseif page_name == "MASTER" then
    if param_name == "speed" then
      deg.master_speed = util.clamp(deg.master_speed + d * 0.01, 0.1, 4.0)
      params:set("master_speed", deg.master_speed, true)
      show_overlay("speed", string.format("%.2fx", deg.master_speed))
    elseif param_name == "mode" then
      local modes = {"deterministic", "stochastic", "mystery"}
      local idx = 1
      for i, m in ipairs(modes) do
        if m == deg.decay_mode then idx = i; break end
      end
      idx = util.clamp(idx + d, 1, 3)
      deg.decay_mode = modes[idx]
      deg.mystery_mode = (idx == 3)
      params:set("decay_mode", idx, true)
      show_overlay("mode", deg.decay_mode)
    elseif param_name == "duration" then
      if deg.mystery_mode then
        -- In mystery mode: adjust mystery range max
        deg.mystery_range_max = util.clamp(deg.mystery_range_max + d, deg.mystery_range_min + 1, 60)
        show_overlay("mystery", deg.mystery_range_min .. "-" .. deg.mystery_range_max .. "m")
      else
        -- In deterministic/stochastic: adjust total degradation time (minutes)
        local dur_min = deg.total_degradation_time / 60
        dur_min = util.clamp(dur_min + d * 0.5, 1, 120)
        deg.total_degradation_time = dur_min * 60
        show_overlay("duration", string.format("%.0fm", dur_min))
      end
    end

  elseif page_name == "PRESETS" then
    if param_name == "selection" then
      ui.preset_index = util.clamp(ui.preset_index + d, 1, math.max(1, presets:count()))
    end
  end
end

-- Adjust engine-specific parameters
function adjust_engine_param(eng, param_name, d)
  if param_name == "rate" then
    local key = eng .. "_rate"
    deg[key] = util.clamp(deg[key] + d * 0.01, 0, 1)
    params:set(key, deg[key], true)
    show_overlay("rate", string.format("%.2f", deg[key]))

  elseif param_name == "bypass" then
    -- Handled by K3 toggle
    return

  -- Fidelity specifics
  elseif param_name == "correlation" and eng == "fidelity" then
    deg.fidelity_correlation = util.clamp(deg.fidelity_correlation + d * 0.01, 0, 1)
    show_overlay("correlation", string.format("%.2f", deg.fidelity_correlation))
  elseif param_name == "curve" and eng == "fidelity" then
    deg.fidelity_curve = util.clamp(deg.fidelity_curve + d * 0.01, 0, 1)
    show_overlay("curve", string.format("%.2f", deg.fidelity_curve))

  -- Temporal specifics
  elseif param_name == "wow" then
    deg.wow_depth_max = util.clamp(deg.wow_depth_max + d, 0, 200)
    show_overlay("wow", deg.wow_depth_max .. "¢")
  elseif param_name == "flutter" then
    deg.flutter_depth_max = util.clamp(deg.flutter_depth_max + d, 0, 100)
    show_overlay("flutter", deg.flutter_depth_max .. "¢")
  elseif param_name == "drift" then
    deg.drift_enabled = not deg.drift_enabled
    show_overlay("drift", deg.drift_enabled and "on" or "off")

  -- Dropout specifics
  elseif param_name == "pattern" then
    local patterns = {"even", "clustered", "random"}
    local idx = 1
    for i, p in ipairs(patterns) do
      if p == deg.dropout_pattern then idx = i; break end
    end
    idx = util.clamp(idx + d, 1, 3)
    deg.dropout_pattern = patterns[idx]
    show_overlay("pattern", deg.dropout_pattern)
  elseif param_name == "length" and eng == "dropout" then
    deg.dropout_max_length = util.clamp(deg.dropout_max_length + d * 5, 1, 500)
    show_overlay("length", deg.dropout_max_length .. "ms")
  elseif param_name == "frequency" then
    deg.dropout_max_frequency = util.clamp(deg.dropout_max_frequency + d * 0.5, 0.1, 20)
    show_overlay("freq", string.format("%.1f/s", deg.dropout_max_frequency))

  -- Spectral specifics
  elseif param_name == "target" then
    deg.spectral_target = util.clamp(deg.spectral_target + d * 10, 200, 20000)
    show_overlay("target", ui:format_value("target", deg.spectral_target))
  elseif param_name == "resonance" then
    deg.spectral_resonance = util.clamp(deg.spectral_resonance + d * 0.01, 0, 0.5)
    show_overlay("res", string.format("%.2f", deg.spectral_resonance))
  elseif param_name == "scoop" then
    deg.mid_scoop_enabled = not deg.mid_scoop_enabled
    show_overlay("scoop", deg.mid_scoop_enabled and "on" or "off")

  -- Saturation specifics
  elseif param_name == "max" then
    deg.saturation_max = util.clamp(deg.saturation_max + d * 0.5, 0, 24)
    show_overlay("max", string.format("%.1fdB", deg.saturation_max))
  elseif param_name == "asymmetry" then
    deg.saturation_asymmetry = util.clamp(deg.saturation_asymmetry + d * 0.01, 0, 1)
    show_overlay("asym", string.format("%.2f", deg.saturation_asymmetry))
  elseif param_name == "warmth" then
    deg.saturation_warmth = util.clamp(deg.saturation_warmth + d * 0.01, 0, 1)
    show_overlay("warmth", string.format("%.2f", deg.saturation_warmth))

  -- Noise specifics
  elseif param_name == "hiss" then
    deg.hiss_max = util.clamp(deg.hiss_max + d, -60, -20)
    show_overlay("hiss", deg.hiss_max .. "dB")
  elseif param_name == "crackle" then
    deg.crackle_max_rate = util.clamp(deg.crackle_max_rate + d, 0, 50)
    show_overlay("crackle", deg.crackle_max_rate .. "/s")
  elseif param_name == "correlation" and eng == "noise" then
    deg.crackle_correlation = util.clamp(deg.crackle_correlation + d * 0.01, 0, 1)
    show_overlay("corr", string.format("%.2f", deg.crackle_correlation))

  -- Room specifics
  elseif param_name == "size" then
    deg.room_size_target = util.clamp(deg.room_size_target + d * 0.01, 0, 1)
    show_overlay("size", string.format("%.2f", deg.room_size_target))
  elseif param_name == "wet" then
    deg.room_wet_target = util.clamp(deg.room_wet_target + d * 0.01, 0, 1)
    show_overlay("wet", string.format("%d%%", math.floor(deg.room_wet_target * 100)))
  elseif param_name == "damping" then
    deg.room_damping_target = util.clamp(deg.room_damping_target + d * 0.01, 0, 1)
    show_overlay("damp", string.format("%.2f", deg.room_damping_target))
  end
end

function show_overlay(param, value)
  ui:show_overlay(ui:page_name(), param, value)
end

----------------------------------------------
-- KEYS
----------------------------------------------
function key(n, z)
  -- During death: any key resurrects
  if ui.black_screen and z == 1 then
    resurrect()
    return
  end

  if n == 1 then
    ui.key_shift = (z == 1)
    return
  end

  if n == 2 then
    if z == 1 then
      ui.key2_held = true
      if ui.key_shift then
        -- K1+K2: Settings menu (future)
        print("ember: settings (not yet implemented)")
      else
        -- K2: universal play/pause
        toggle_playback()
        screen_dirty = true
      end
    else
      ui.key2_held = false
    end
    return
  end

  if n == 3 and z == 1 then
    local page_name = ui:page_name()

    if ui.key_shift then
      -- K1+K3: Reset head to start
      reset_head()

    elseif page_name == "SAMPLE" then
      -- K3 on sample page: file browser
      fileselect.enter(_path.audio, function(path)
        if path ~= "cancel" then
          load_sample(current_slot, path)
        end
      end)

    elseif page_name == "LOOP" then
      -- K3 on loop page: toggle quantize mode
      quantize_mode = quantize_mode == "free" and "quantized" or "free"
      show_overlay("quantize", quantize_mode)

    elseif page_name == "FIDELITY" or page_name == "TEMPORAL" or
           page_name == "DROPOUT" or page_name == "SPECTRAL" or
           page_name == "SATURATION" or page_name == "NOISE" or
           page_name == "ROOM" then
      -- K3 on engine pages: bypass toggle
      local eng = page_name:lower()
      local key = eng .. "_bypass"
      deg[key] = not deg[key]
      show_overlay("bypass", deg[key] and "on" or "off")

    elseif page_name == "HEALTH" then
      -- K3 on health: resurrect
      resurrect()

    elseif page_name == "PRESETS" then
      -- K3 on presets: load selected preset
      if presets:count() > 0 then
        if presets:load(ui.preset_index, deg) then
          -- Stop playback during preset change
          if playing then
            playing = false
            EmberEngine.stop()
          end
          -- Reset engine to pristine baseline before applying preset state
          -- Explicitly set noise/room to safe values first
          engine.hissLevel(-90)
          engine.crackleRate(0)
          engine.noiseBypass(0)
          engine.roomSize(0.1)
          engine.roomWet(0.1)
          engine.roomDamping(0.1)
          engine.roomBypass(0)
          -- Now apply the full pristine degradation state
          EmberEngine.apply_degradation(deg:get_state())
          vis:reset_buffer()
          show_overlay("preset", presets:get(ui.preset_index).name)
        end
      end
    end

    screen_dirty = true
  end
end

----------------------------------------------
-- REDRAW
----------------------------------------------
function redraw()
  screen.clear()

  -- Death screen
  if ui.death_screen then
    if ui.black_screen then
      -- Pure black, nothing
      screen.update()
      return
    end
    -- Show degraded image with fade
    vis:draw(ui.fade_to_black)
    screen.update()
    return
  end

  -- IMAGE page: full-screen visual, minimal overlay
  if ui:page_name() == "IMAGE" then
    vis:draw()
    -- Subtle health in corner
    screen.level(4)
    screen.move(127, 7)
    screen.text_right(string.format("%d", math.floor(deg.health)))
    if playing then
      screen.level(4)
      screen.move(1, 7)
      screen.text("~")
    end
    screen.update()
    return
  end

  -- Parameter pages: standard norns black bg
  -- Page header
  screen.level(6)
  screen.move(1, 7)
  screen.text(ui:page().poetic or ui:page_name():lower())

  -- Health indicator (top right)
  local health_str = string.format("%d", math.floor(deg.health))
  screen.level(deg.is_dead and 2 or 8)
  screen.move(127, 7)
  screen.text_right(health_str)

  -- Playing indicator
  if playing then
    screen.level(6)
    screen.move(64, 7)
    screen.text_center(deg.is_dead and "---" or "~")
  end

  -- Draw page-specific content
  draw_page_content()

  -- Parameter overlay (on-change, bottom edge)
  if ui.overlay_text and ui.overlay_timer > 0 then
    local alpha = math.min(1, ui.overlay_timer / 0.5)
    screen.level(math.floor(alpha * 15))
    screen.move(64, 62)
    screen.text_center(ui.overlay_text)
  end

  screen.update()
end

function draw_page_content()
  local page_name = ui:page_name()
  local params_list = ui:page().params
  local y_start = 20

  if page_name == "SAMPLE" then
    -- Sample slot and filename
    draw_param_row("slot", current_slot, ui.current_param == 1, y_start)
    draw_param_row("file", sample_slots[current_slot], ui.current_param == 2, y_start + 10)
    -- Duration info
    if sample_durations[current_slot] > 0 then
      screen.level(3)
      screen.move(1, y_start + 24)
      screen.text(string.format("%.1fs", sample_durations[current_slot]))
    end

  elseif page_name == "LOOP" then
    draw_param_row("start", string.format("%.1fs", loop_start), ui.current_param == 1, y_start)
    draw_param_row("length", string.format("%.1fs", loop_length), ui.current_param == 2, y_start + 10)
    draw_param_row("quantize", quantize_mode, ui.current_param == 3, y_start + 20)
    -- Loop region indicator
    if sample_durations[current_slot] > 0 then
      local dur = sample_durations[current_slot]
      local bar_y = 56
      screen.level(2)
      screen.rect(0, bar_y, 128, 4)
      screen.stroke()
      local sx = math.floor(loop_start / dur * 128)
      local sw = math.max(1, math.floor(loop_length / dur * 128))
      screen.level(8)
      screen.rect(sx, bar_y, sw, 4)
      screen.fill()
    end

  elseif page_name == "PLAYBACK" then
    draw_param_row("speed", string.format("%.2fx", speed), ui.current_param == 1, y_start)
    draw_param_row("level", string.format("%d%%", math.floor(level * 100)), ui.current_param == 2, y_start + 10)
    draw_param_row("pan", ui:format_value("pan", pan), ui.current_param == 3, y_start + 20)
    draw_param_row("width", string.format("%d%%", math.floor(deg.width_target * 100)), ui.current_param == 4, y_start + 30)

  elseif page_name == "FIDELITY" then
    draw_param_row("rate", string.format("%.2f", deg.fidelity_rate), ui.current_param == 1, y_start)
    draw_param_row("correlation", string.format("%.2f", deg.fidelity_correlation), ui.current_param == 2, y_start + 10)
    draw_param_row("curve", string.format("%.2f", deg.fidelity_curve), ui.current_param == 3, y_start + 20)
    draw_param_row("bypass", deg.fidelity_bypass and "on" or "off", ui.current_param == 4, y_start + 30)
    -- State bar
    draw_state_bar(deg.fidelity_state)

  elseif page_name == "TEMPORAL" then
    draw_param_row("rate", string.format("%.2f", deg.temporal_rate), ui.current_param == 1, y_start)
    draw_param_row("wow", deg.wow_depth_max .. "¢", ui.current_param == 2, y_start + 10)
    draw_param_row("flutter", deg.flutter_depth_max .. "¢", ui.current_param == 3, y_start + 20)
    draw_param_row("drift", deg.drift_enabled and "on" or "off", ui.current_param == 4, y_start + 30)
    draw_state_bar(deg.temporal_state)

  elseif page_name == "DROPOUT" then
    draw_param_row("rate", string.format("%.2f", deg.dropout_rate), ui.current_param == 1, y_start)
    draw_param_row("pattern", deg.dropout_pattern, ui.current_param == 2, y_start + 10)
    draw_param_row("length", deg.dropout_max_length .. "ms", ui.current_param == 3, y_start + 20)
    draw_param_row("freq", string.format("%.1f/s", deg.dropout_max_frequency), ui.current_param == 4, y_start + 30)
    draw_state_bar(deg.dropout_state)

  elseif page_name == "SPECTRAL" then
    draw_param_row("rate", string.format("%.2f", deg.spectral_rate), ui.current_param == 1, y_start)
    draw_param_row("target", ui:format_value("target", deg.spectral_target), ui.current_param == 2, y_start + 10)
    draw_param_row("resonance", string.format("%.2f", deg.spectral_resonance), ui.current_param == 3, y_start + 20)
    draw_param_row("scoop", deg.mid_scoop_enabled and "on" or "off", ui.current_param == 4, y_start + 30)
    draw_state_bar(deg.spectral_state)

  elseif page_name == "SATURATION" then
    draw_param_row("rate", string.format("%.2f", deg.saturation_rate), ui.current_param == 1, y_start)
    draw_param_row("max", string.format("%.1fdB", deg.saturation_max), ui.current_param == 2, y_start + 10)
    draw_param_row("asymmetry", string.format("%.2f", deg.saturation_asymmetry), ui.current_param == 3, y_start + 20)
    draw_param_row("warmth", string.format("%.2f", deg.saturation_warmth), ui.current_param == 4, y_start + 30)
    draw_state_bar(deg.saturation_state)

  elseif page_name == "NOISE" then
    draw_param_row("rate", string.format("%.2f", deg.noise_rate), ui.current_param == 1, y_start)
    draw_param_row("hiss", deg.hiss_max .. "dB", ui.current_param == 2, y_start + 10)
    draw_param_row("crackle", deg.crackle_max_rate .. "/s", ui.current_param == 3, y_start + 20)
    draw_param_row("correlation", string.format("%.2f", deg.crackle_correlation), ui.current_param == 4, y_start + 30)
    draw_state_bar(deg.noise_state)

  elseif page_name == "ROOM" then
    draw_param_row("rate", string.format("%.2f", deg.room_rate), ui.current_param == 1, y_start)
    draw_param_row("size", string.format("%.2f", deg.room_size_target), ui.current_param == 2, y_start + 10)
    draw_param_row("wet", string.format("%d%%", math.floor(deg.room_wet_target * 100)), ui.current_param == 3, y_start + 20)
    draw_param_row("damping", string.format("%.2f", deg.room_damping_target), ui.current_param == 4, y_start + 30)
    draw_state_bar(deg.room_state)

  elseif page_name == "HEALTH" then
    draw_param_row("threshold", string.format("%d%%", math.floor(deg.death_threshold)), ui.current_param == 1, y_start)
    draw_param_row("mode", deg.death_mode, ui.current_param == 2, y_start + 10)
    -- Health bar
    local bar_y = 40
    screen.level(2)
    screen.rect(0, bar_y, 128, 8)
    screen.stroke()
    local hw = math.floor(deg.health * 1.28)
    screen.level(deg.health < deg.death_threshold and 3 or (deg.health < 30 and 6 or 12))
    screen.rect(0, bar_y, hw, 8)
    screen.fill()
    -- Health value
    screen.level(10)
    screen.move(64, bar_y + 18)
    screen.text_center(deg.is_dead and "dead" or string.format("memory: %d%%", math.floor(deg.health)))

  elseif page_name == "MASTER" then
    draw_param_row("speed", string.format("%.2fx", deg.master_speed), ui.current_param == 1, y_start)
    draw_param_row("mode", deg.mystery_mode and "mystery" or deg.decay_mode, ui.current_param == 2, y_start + 10)
    if deg.mystery_mode then
      draw_param_row("range", deg.mystery_range_min .. "-" .. deg.mystery_range_max .. "m", ui.current_param == 3, y_start + 20)
    else
      local dur_min = deg.total_degradation_time / 60
      draw_param_row("duration", string.format("%.0fm", dur_min), ui.current_param == 3, y_start + 20)
    end
    -- Loop count
    screen.level(3)
    screen.move(1, 56)
    screen.text("loops: " .. deg.loop_count)

  elseif page_name == "PRESETS" then
    -- List presets
    local count = presets:count()
    if count == 0 then
      screen.level(4)
      screen.move(64, 36)
      screen.text_center("no presets")
    else
      local start_i = math.max(1, ui.preset_index - 2)
      local end_i = math.min(count, start_i + 4)
      for i = start_i, end_i do
        local p = presets:get(i)
        local y = y_start + (i - start_i) * 10
        local selected = (i == ui.preset_index)
        screen.level(selected and 15 or 4)
        screen.move(4, y)
        screen.text(p.name)
        if p.factory then
          screen.level(2)
          screen.move(127, y)
          screen.text_right("*")
        end
      end
    end
  end
end

-- Draw a parameter row
function draw_param_row(name, value, selected, y)
  screen.level(selected and 15 or 4)
  screen.move(1, y)
  screen.text(name)
  screen.move(127, y)
  screen.text_right(tostring(value))
end

-- Draw engine state bar at bottom
function draw_state_bar(state)
  local bar_y = 56
  local bar_w = math.floor(state * 128)
  screen.level(3)
  screen.move(0, bar_y)
  screen.line(128, bar_y)
  screen.stroke()
  if bar_w > 0 then
    screen.level(10)
    screen.move(0, bar_y)
    screen.line(bar_w, bar_y)
    screen.stroke()
  end
end
