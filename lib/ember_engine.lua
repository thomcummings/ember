-- ember_engine.lua
-- Engine communication layer
-- Maps degradation state to SuperCollider engine commands

local EmberEngine = {}

-- Send all degradation states to the SC engine
-- Called on each loop boundary after degradation step
function EmberEngine.apply_degradation(state)
  -- Fidelity
  if not state.fidelity_bypass then
    engine.fidelityState(state.fidelity_state)
    engine.fidelityCorrelation(state.fidelity_correlation)
    engine.fidelityCurve(state.fidelity_curve)
  end
  engine.fidelityBypass(state.fidelity_bypass and 1 or 0)

  -- Temporal
  if not state.temporal_bypass then
    engine.temporalState(state.temporal_state)
    engine.wowDepthMax(state.wow_depth_max)
    engine.flutterDepthMax(state.flutter_depth_max)
    engine.driftEnabled(state.drift_enabled and 1 or 0)
    engine.driftVal(state.drift_val)
  end
  engine.temporalBypass(state.temporal_bypass and 1 or 0)

  -- Dropout
  if not state.dropout_bypass then
    engine.dropoutState(state.dropout_state)
    engine.dropoutMaxLength(state.dropout_max_length / 1000) -- ms to seconds
    engine.dropoutMaxFreq(state.dropout_max_frequency)
  end
  engine.dropoutBypass(state.dropout_bypass and 1 or 0)

  -- Spectral
  if not state.spectral_bypass then
    engine.spectralState(state.spectral_state)
    engine.spectralTarget(state.spectral_target)
    engine.spectralResonance(state.spectral_resonance)
    engine.midScoopEnabled(state.mid_scoop_enabled and 1 or 0)
    engine.midScoopState(state.mid_scoop_state)
  end
  engine.spectralBypass(state.spectral_bypass and 1 or 0)

  -- Saturation
  if not state.saturation_bypass then
    engine.saturationState(state.saturation_state)
    engine.saturationMax(state.saturation_max)
    engine.saturationAsymmetry(state.saturation_asymmetry)
    engine.saturationWarmth(state.saturation_warmth)
  end
  engine.saturationBypass(state.saturation_bypass and 1 or 0)

  -- Noise
  if not state.noise_bypass then
    -- Hiss: map state 0-1 to dB range (-90 to max)
    local hiss_db = util.linlin(state.noise_state, 0, 1, -90, state.hiss_max)
    engine.hissLevel(hiss_db)
    -- Crackle: map state 0-1 to rate
    local crackle = state.noise_state * state.crackle_max_rate
    engine.crackleRate(crackle)
  end
  engine.noiseBypass(state.noise_bypass and 1 or 0)

  -- Room
  if not state.room_bypass then
    -- Room grows from initial to target based on room_state
    local room_size = util.linlin(state.room_state, 0, 1, 0.1, state.room_size_target)
    local room_wet = util.linlin(state.room_state, 0, 1, 0.1, state.room_wet_target)
    local room_damp = util.linlin(state.room_state, 0, 1, 0.1, state.room_damping_target)
    engine.roomSize(room_size)
    engine.roomWet(room_wet)
    engine.roomDamping(room_damp)
  end
  engine.roomBypass(state.room_bypass and 1 or 0)

  -- Stereo width
  if not state.width_bypass then
    engine.widthState(state.width_state)
    engine.widthTarget(state.width_target)
  end
  engine.widthBypass(state.width_bypass and 1 or 0)
end

-- Apply playback parameters
function EmberEngine.apply_playback(params)
  engine.level(params.level)
  engine.pan(params.pan)
  engine.speed(params.speed)
  engine.loopStart(params.loop_start)
  engine.loopLength(params.loop_length)
end

-- Load sample into slot
function EmberEngine.load_sample(slot, path)
  engine.loadSample(slot, path)
end

-- Assign slot to voice
function EmberEngine.assign_slot(slot)
  engine.assignSlot(slot)
end

-- Transport
function EmberEngine.start()
  engine.start()
end

function EmberEngine.stop()
  engine.stop()
end

-- Death tail: stop voice but keep room and noise ringing out
function EmberEngine.begin_death_tail()
  -- Stop only the voice synth; noise + room stay open for tail
  -- (stop() now closes both voice + noise, so we reopen noise)
  engine.stop()
  engine.noiseGate(1)
end

-- Kill everything including reverb tail
function EmberEngine.kill_room()
  engine.roomGate(0)
  engine.noiseGate(0)
end

-- Resurrect: reopen room and noise gates
function EmberEngine.resurrect()
  engine.roomGate(1)
  engine.noiseGate(1)
end

-- Request buffer duration info
function EmberEngine.get_buffer_duration(slot)
  engine.getBufferDuration(slot)
end

return EmberEngine
