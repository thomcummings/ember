# EMBER - Complete Technical Specification

## Overview
ember is a loop disintegration instrument for Norns, inspired by William Basinski's "The Disintegration Loops." Load samples, set loop regions, and experience them gradually decaying through multiple degradation processes. A visual representation (cityscape photograph) degrades in parallel with the audio.

## Core Concept
* Single-head default experience (multi-head as later expansion)
* 4 sample slots available, 1 active playhead initially
* 7 degradation engines per head (including room/space)
* Degradation is time-based but applied as step changes at loop boundaries
* Deterministic, stochastic, or mystery decay modes
* "Tape type" presets define degradation characteristics
* Visual degradation synced to loop boundaries (not timer-based)

## Aesthetic Philosophy
* Interface uses poetic/abstract language where possible
* Visual representation: Dorian Gray metaphor (image ages as sound decays)
* Parameter display is minimal, on-change only, subtle
* The dying is the point
* The ending matters
* Leave room for the accident

## Technical Architecture

### File Structure
```
dust/code/ember/
├── ember.lua                 (main script)
├── lib/
│   ├── Engine_Ember.sc      (SuperCollider engine)
│   ├── ember_engine.lua     (engine communication layer)
│   ├── degradation.lua      (degradation state management)
│   ├── visual.lua           (image rendering & degradation)
│   ├── preset.lua           (preset save/load)
│   └── ui.lua               (interface & navigation)
├── images/
│   ├── default.png          (blurred cityscape, 128x64, 4-bit grayscale)
│   └── user/                (user-uploaded images)
└── presets/
    ├── factory/             (shipped presets as .json or .lua)
    └── user/                (user-saved presets)
```

### SuperCollider Engine

**Voice Architecture (Phase 1):**
* 1 playback voice (expandable to 4 in later phase)
* Voice: sample playback → degradation chain → stereo output

**Loop Boundary Communication:**
* Engine sends OSC message /ember/loop_wrap on each loop completion
* Message includes: voice index, loop count, current playhead position
* Lua receives and triggers degradation step + visual update
* This ensures audio and visual degradation are perfectly synchronized

**Degradation Signal Chain (per voice):**
```
Sample Playback
    ↓
Bit/Sample Rate Reduction (Fidelity)
    ↓
Wow/Flutter/Drift (Temporal)
    ↓
Dropout Injection (Erosion)
    ↓
Lowpass + Mid-Scoop (Spectral)
    ↓
Saturation/Distortion
    ↓
Noise Addition (Hiss + Crackle)
    ↓
Room/Space (Reverb)
    ↓
Stereo Width Processing
    ↓
Level + Pan
    ↓
Stereo Output
```

## Lua Script Structure

### Main Components:
* ember.lua: Init, params, redraw loop, key/encoder handlers, OSC listener
* ember_engine.lua: Engine commands, parameter mapping
* degradation.lua: Health tracking, degradation state per head, loop cycle counting
* visual.lua: Image buffer, degradation rendering, overlay
* preset.lua: Save/load, factory preset definitions
* ui.lua: Page navigation, parameter display, waveform overlay

## Sample & Playback System

### Sample Slots (4 total)
* Load samples from anywhere on device (file browser)
* Maximum sample length: 3 minutes
* Mono or stereo (stereo summed to mono for processing)
* Stored in SuperCollider buffers

### Playhead (Single Head - Phase 1)
Each playhead has:
* Sample slot assignment (1-4): which sample to read from
* Loop start: position in sample (seconds or beats if quantized)
* Loop length: duration (seconds or beats if quantized)
* Quantize mode: free (time-based) or quantized (beat-based)
* Playback speed: 0.25x - 2.0x (independent of degradation)
* Level: 0-100% (default 80%)
* Pan: -100 (left) to +100 (right) (default 0/center)
* Stereo width: 0-100% (default 100%, collapses toward mono as it degrades)
* Play state: stopped / playing / paused

### Playback Controls
* K3: Play/pause toggle for selected head
* K1+K3: Reset to loop start (stop and return to beginning)

### Loop Point Behavior
* Adjustable only when head is stopped
* Displayed as temporary waveform overlay on LOOP page
* Full sample waveform shown with loop region highlighted

## Degradation Engine Specifications

### Global Degradation Behavior
* Time-based: User sets total time to full degradation
* Applied per-cycle: Degradation step occurs at each loop boundary
* Triggered by OSC: Engine sends /ember/loop_wrap, Lua applies degradation
* Step calculation: Total degradation ÷ estimated cycles = increment per loop
* First loop: Always pristine (no degradation applied until first loop completes)

### Health System
Each head maintains a health value:
* Range: 100% (pristine) → 0% (dead)
* Calculation (weighted average):
```
health = (
  fidelity_state * 0.25 +
  temporal_state * 0.15 +
  dropout_state * 0.20 +
  spectral_state * 0.20 +
  saturation_state * 0.10 +
  noise_state * 0.10
)
```
* Note: Room/Space engine does NOT affect health. It exists outside the death system - the room is the witness, not the dying thing.
* Note: This weighting should be tested during development. Alternative approaches to consider if weighted average feels wrong:
  * Minimum of all engine states (most degraded engine determines health)
  * Worst single engine state dominates
  * User-adjustable weighting
* State values: Each engine tracks 0.0 (no degradation) → 1.0 (full degradation)

### Engine 1: Fidelity Decay

**Parameters:**

| Parameter | Range | Default | Description |
|---|---|---|---|
| fidelity_rate | 0.0-1.0 | 0.3 | Speed of degradation |
| fidelity_correlation | 0.0-1.0 | 0.7 | Bit/sample rate coupling |
| fidelity_curve | 0.0-1.0 | 0.5 | Exponential steepness |
| fidelity_bypass | bool | false | Engine bypass |

**Behavior:**
* Bit depth: 16-bit → 1-bit, exponential curve
* Sample rate: 48kHz → 2kHz, logarithmic curve
* Correlation: How much bit reduction influences sample rate reduction
* Implementation: Quantization with triangular dithering, decimation with anti-aliasing

**Visual Effect:** Posterization (reduce grayscale levels)

### Engine 2: Temporal Instability

**Parameters:**

| Parameter | Range | Default | Description |
|---|---|---|---|
| temporal_rate | 0.0-1.0 | 0.3 | Speed of instability growth |
| wow_depth_max | 0-200 cents | 100 | Maximum wow depth |
| flutter_depth_max | 0-100 cents | 50 | Maximum flutter depth |
| drift_enabled | bool | true | Enable pitch drift |
| drift_reset | bool | false | Reset drift at loop boundary |
| temporal_bypass | bool | false | Engine bypass |

**Behavior:**
* Wow: Slow pitch variation, sine LFO 0.5-3Hz, depth grows from 0 to max
* Flutter: Fast pitch variation, noise LFO 5-15Hz, depth grows from 0 to max
* Drift: Random walk ±0.1-5 cents/minute, accumulates (can drift semitones over time)

**Visual Effect:** Warp (pixel row/column displacement)

### Engine 3: Dropout/Erosion

**Parameters:**

| Parameter | Range | Default | Description |
|---|---|---|---|
| dropout_rate | 0.0-1.0 | 0.3 | Speed of dropout increase |
| dropout_pattern | even/clustered/random | clustered | Distribution pattern |
| dropout_max_length | 1-500ms | 200 | Maximum dropout duration |
| dropout_max_frequency | 0.1-20 events/sec | 10 | Maximum event rate |
| dropout_bypass | bool | false | Engine bypass |

**Behavior:**
* Events: Random silence injection
* Length distribution: Exponential (many short, few long)
* Frequency: Grows from 0 to max over degradation time
* Patterns:
  * Even: Regular interval with jitter
  * Clustered: Dropouts bunch together (damage spreads)
  * Random: Pure Poisson distribution

**Visual Effect:** Tears (rectangular regions set to black)

### Engine 4: Spectral Degradation

**Parameters:**

| Parameter | Range | Default | Description |
|---|---|---|---|
| spectral_rate | 0.0-1.0 | 0.3 | Speed of HF rolloff |
| spectral_target | 200Hz-20kHz | 500 | Final cutoff frequency |
| spectral_resonance | 0.0-0.5 | 0.1 | Filter peak development |
| mid_scoop_enabled | bool | false | Enable print-through effect |
| mid_scoop_rate | 0.0-1.0 | 0.3 | Mid-scoop development speed |
| spectral_bypass | bool | false | Engine bypass |

**Behavior:**
* Lowpass: 2-pole Butterworth, cutoff drops exponentially from 20kHz to target
* Resonance: Slight peak develops over time (0 → max)
* Mid-scoop: Optional notch at 500Hz-2kHz, depth grows 0 → -12dB (simulates magnetic print-through)

**Visual Effect:** Blur (gaussian smoothing / pixel averaging)

### Engine 5: Saturation/Distortion

**Parameters:**

| Parameter | Range | Default | Description |
|---|---|---|---|
| saturation_rate | 0.0-1.0 | 0.3 | Speed of saturation increase |
| saturation_max | 0-24dB | 18 | Maximum drive amount |
| saturation_asymmetry | 0.0-1.0 | 0.3 | Asymmetric clipping amount |
| saturation_warmth | 0.0-1.0 | 0.5 | Pre-emphasis (100Hz bump) |
| saturation_bypass | bool | false | Engine bypass |

**Behavior:**
* Clipping: Asymmetric soft clipping (tanh curve)
* Drive: Grows from 0dB to max over degradation time
* Asymmetry: More compression on positive peaks (tape character)
* Pre-emphasis: 100Hz boost before saturation (warmth)
* Harmonics: Emphasis on odd harmonics

**Visual Effect:** Blown highlights (contrast crush, white blowout)

### Engine 6: Noise Accumulation

**Parameters:**

| Parameter | Range | Default | Description |
|---|---|---|---|
| noise_rate | 0.0-1.0 | 0.3 | Speed of noise increase |
| hiss_max | -60 to -20dB | -30 | Maximum hiss level |
| crackle_max_rate | 0-50 events/sec | 20 | Maximum crackle frequency |
| crackle_correlation | 0.0-1.0 | 0.8 | Link to dropout events |
| noise_bypass | bool | false | Engine bypass |

**Behavior:**
* Hiss: Pink noise (1/f spectrum), level grows from -∞ to max
* Crackle: Impulse noise, 1-10 sample duration, rate grows from 0 to max
* Correlation: Crackle clusters around dropout events (damage attracts damage)
* Hiss bandwidth: Narrows as spectral degradation progresses

**Visual Effect:** Grain (random pixel noise)

### Engine 7: Room/Space

**Concept:** Inspired by Alvin Lucier's "I Am Sitting in a Room" - as the loop degrades, the room gradually consumes it. The source dissolves into the resonance of the space where it was played. By the end, you're hearing the ghost of the loop, not the loop itself.

**Parameters:**

| Parameter | Range | Default | Description |
|---|---|---|---|
| room_rate | 0.0-1.0 | 0.3 | Speed of room transformation |
| room_size_target | 0.0-1.0 | 0.9 | Final room size (small → large) |
| room_wet_target | 0-100% | 80 | Final wet mix |
| room_damping_target | 0.0-1.0 | 0.8 | Final HF damping in reverb |
| room_bypass | bool | false | Engine bypass |

**Behavior:**
* Room size: Grows from small/tight to large/diffuse
* Wet mix: Increases from ~10% to target (loop dissolves into space)
* Decay time: Lengthens as size grows
* Damping: Increases (reverb tail loses high frequencies)
* Character: The room "wins" - source becomes less intelligible, space becomes more present

**Health:** Room does NOT affect health calculation. It exists outside the death system. The room is the witness, not the dying thing.

**Visual Effect:** None directly (or subtle edge diffusion, low priority)

**Special Death Behavior:**
* When loop dies, source goes silent
* BUT reverb tail continues for 3-5 seconds
* The last echoes fade in the space
* Then true silence
* Then fade to black

**Implementation:** Simple reverb (FreeVerb or similar) - not CPU intensive.

### Stereo Width Degradation

**Parameters:**

| Parameter | Range | Default | Description |
|---|---|---|---|
| width_rate | 0.0-1.0 | 0.2 | Speed of stereo collapse |
| width_target | 0-100% | 20 | Final stereo width |
| width_bypass | bool | false | Disable width degradation |

**Behavior:**
* Stereo width: Starts at 100%, collapses toward target over degradation time
* Implementation: Mid-side processing, reduce side level
* Character: Loop becomes increasingly mono as it dies (intimacy, focus narrowing)

Note: Subtle, should not dominate. Width degradation rate slower than other engines by default.

## Death System

### Threshold
* Global setting: 0-100% (default 10%)
* When head health drops below threshold, death behavior triggers

### Death Modes
* Silence: Playhead stops, outputs silence
* Freeze: Continues playing at final degradation state (no further decay)
* Collapse: Rapid final degradation (2-10 seconds) then silence

### Death Sequence
1. Health drops below threshold
2. Death mode triggers (silence/freeze/collapse)
3. If silence or collapse: source stops
4. Reverb tail continues (3-5 seconds) - the room remembers
5. Reverb tail fades naturally
6. Complete silence
7. Hold black screen for 10 seconds
8. No text, no indication, just black
9. Any key press: option to begin again (resurrect)

## Decay Modes

### Deterministic Mode
* All degradation follows predictable curves
* Same settings = same result every time
* User is conductor

### Stochastic Mode
When enabled, degradation becomes probabilistic:

Per evaluation period (1-10 seconds, randomized):
* Plateau probability: 0-30% chance degradation pauses
* Acceleration probability: 0-20% chance of sudden jump
* Regression probability: 0-5% chance of brief "healing"

Variation applied to:
* Degradation rate (subtle random multiplier)
* Dropout timing (more irregular)
* Noise characteristics (fluctuating)

### Mystery Mode

**Concept:** User doesn't know when death will come. The system chooses. They are witness, not conductor. Leave room for the accident.

**Parameters:**

| Parameter | Range | Default | Description |
|---|---|---|---|
| mystery_mode | bool | false | Enable mystery timing |
| mystery_range_min | 1-60 min | 5 | Minimum possible duration |
| mystery_range_max | 1-60 min | 45 | Maximum possible duration |

**Behavior:**
* When mystery mode enabled, system secretly selects total degradation time within range
* Selection happens on first play (or on resurrect)
* User cannot see the chosen time
* All rate parameters are internally scaled to hit death at the chosen moment
* User only knows the range, not the specific duration
* Stochastic variations still apply

**UI indication:**
* On MASTER page, if mystery mode on, show "mystery" instead of time/rate values
* No countdown, no progress indicator
* The user simply waits and witnesses

## Interface Design

### Control Mapping

| Control | Function |
|---|---|
| E1 | Page selection (single head mode) |
| E2 | Parameter selection within current page |
| E3 | Parameter value adjustment |
| K2 | Cycle through pages |
| K3 | Play/pause or context action |
| K1+K3 | Reset head to start |
| K1+K2 | Open settings menu |

### Page Structure (Single Head Mode)

| # | Page | E2 Selects | E3 Adjusts | K3 Action |
|---|---|---|---|---|
| 1 | SAMPLE | Sample slot | Sample file | Load browser |
| 2 | LOOP | Start / Length / Quantize | Selected param | Toggle quantize |
| 3 | PLAYBACK | Speed / Level / Pan / Width | Selected param | Play/pause |
| 4 | FIDELITY | Rate / Correlation / Curve | Selected param | Bypass toggle |
| 5 | TEMPORAL | Rate / Wow / Flutter / Drift | Selected param | Bypass toggle |
| 6 | DROPOUT | Rate / Pattern / Length / Freq | Selected param | Bypass toggle |
| 7 | SPECTRAL | Rate / Target / Res / Scoop | Selected param | Bypass toggle |
| 8 | SATURATION | Rate / Max / Asym / Warmth | Selected param | Bypass toggle |
| 9 | NOISE | Rate / Hiss / Crackle / Corr | Selected param | Bypass toggle |
| 10 | ROOM | Rate / Size / Wet / Damping | Selected param | Bypass toggle |
| 11 | HEALTH | Threshold / Death mode | Selected param | Resurrect (100%) |
| 12 | MASTER | Speed mult / Mode (det/stoch/mystery) | Selected param | Start/stop |
| 13 | PRESETS | Preset selection | Scroll presets | Load preset |

**LOOP Page Special Behavior:**
* Displays temporary waveform overlay
* Shows full sample with loop region highlighted
* Loop adjustment only available when head is stopped

**PRESETS Page Special Behavior:**
* K3: Load selected preset
* K1+K3: Save current state as new preset
* K2+K3: Delete selected preset (instant, no confirmation)

### Settings Menu (K1+K2)

| Setting | Options |
|---|---|
| Image | default / user / [file browser] |
| Visual | on / off |
| Reset all health | [action] |
| Multi-head mode | on / off (future expansion) |

## Visual System

### Base Image
* Default: Blurred cityscape fading into fog/distance
* Specs: 128x64 pixels, 4-bit grayscale (16 levels), PNG format
* Aesthetic: Elevated perspective, silhouettes in foreground, atmospheric distance, already slightly nostalgic
* User upload: Optional, from dust/code/ember/images/user/

### Image Storage
* Loaded into pixel buffer on init
* Buffer manipulated for degradation
* Original preserved for reference/reset

### Degradation Rendering

**Trigger:** Visual degradation updates on loop boundary (synced to /ember/loop_wrap OSC message), not on timer. This ensures visual and audio degradation are perfectly synchronized.

| Engine | Visual Effect | Implementation |
|---|---|---|
| Fidelity | Posterization | Reduce grayscale levels (16→8→4→2→1) |
| Temporal | Warp | Pixel row/column displacement |
| Dropout | Tears | Rectangular regions set to black |
| Spectral | Blur | Average neighboring pixels |
| Saturation | Blown highlights | Contrast crush, clip whites |
| Noise | Grain | Random pixel value addition |

### Performance Optimization
* Pre-compute degradation lookup tables where possible
* Only update changed regions if feasible
* Accept lower visual frame rate (loop-synced is inherently slower for long loops)

### Parameter Overlay
* Trigger: On parameter change only
* Duration: Visible for 2 seconds, then fades
* Style: Subtle, minimal, bottom edge of screen
* Content: Page name, parameter name, value
* No persistent UI elements on main view

### Death Visual Sequence
1. Loop dies, audio fades (reverb tail continues)
2. Image holds final degraded state
3. Reverb tail ends, silence begins
4. Hold for 10 seconds
5. Fade to pure black over 5 seconds
6. No text, nothing - just black emptiness
7. Any key press to restart

## Presets System

### What Presets Save
Degradation parameters only (the "tape type"):
* All 7 engines' parameters (rate, max, bypass, etc.)
* Stereo width degradation parameters
* Death threshold and mode
* Stochastic/mystery mode settings
* Master speed multiplier

### What Presets Do NOT Save
* Sample assignments
* Loop points
* Playback speed/level/pan
* Current health state

### On Preset Load
* Head resets to 100% health
* New degradation parameters applied
* Sample/loop unchanged

### Factory Presets

| Name | Character | Dominant Engines | Room |
|---|---|---|---|
| Archival | Very slow, gentle fade | Spectral + Fidelity, minimal others | Slow room growth, ends medium-wet |
| Oxide | Medium, tape-damage | Dropout + Noise, clustered pattern | Minimal room, stays intimate |
| Thermal | Warm then harsh | Saturation-forward, high warmth | Medium room, diffuses heat |
| Glacial | Extremely slow (20+ min) | All engines at minimal rate | Very slow room, ends cathedral |
| Cascade | Medium-fast, chaotic | Dropout-heavy, high crackle correlation | Fast room growth, overwhelms |
| Dust | Noise-dominant | Noise + Crackle high, others subtle | Dusty room, grainy reverb |

### Preset Storage
* Factory: dust/code/ember/presets/factory/ (read-only)
* User: dust/code/ember/presets/user/ (read-write)
* Format: JSON or Lua table

## PARAMS Integration
All parameters exposed to Norns PARAMS system for:
* MIDI learn (handled by Norns system automatically)
* Parameter automation
* Preset recall via PSET

### Parameter Naming Convention
```
[engine]_[param]
```
Examples:
* fidelity_rate
* dropout_pattern
* room_wet_target
* master_speed
* death_threshold

## Build Phases

### Phase 1: Core Engine + Single Head
* [ ] SuperCollider engine skeleton (single voice)
* [ ] Sample loading and basic playback (3 min max)
* [ ] Loop point setting
* [ ] OSC message on loop wrap (/ember/loop_wrap)
* [ ] Fidelity engine only (bit/sample rate reduction)
* [ ] Basic Lua interface (load sample, set loop, adjust fidelity)
* [ ] PARAMS integration from start
* [ ] K3 play/pause, K1+K3 reset
* [ ] Degradation applied on loop wrap (OSC trigger)
* Goal: Hear a loop gradually lose fidelity, degradation synced to loop

### Phase 2: Complete Degradation Engines
* [ ] Add Temporal engine (wow/flutter/drift)
* [ ] Add Dropout engine
* [ ] Add Spectral engine (including mid-scoop)
* [ ] Add Saturation engine
* [ ] Add Noise engine
* [ ] Add Stereo Width degradation
* [ ] Add Room/Space engine (simple reverb)
* [ ] Engine bypass toggles
* [ ] Health calculation (test weighted average, adjust if needed)
* Goal: Full degradation palette including room

### Phase 3: Visual System
* [ ] Default cityscape image creation/sourcing
* [ ] Image loading into buffer
* [ ] Visual update triggered by loop wrap OSC (not timer)
* [ ] Fidelity visual (posterization)
* [ ] Temporal visual (warp)
* [ ] Dropout visual (tears)
* [ ] Spectral visual (blur)
* [ ] Saturation visual (blown highlights)
* [ ] Noise visual (grain)
* [ ] On-change parameter overlay
* [ ] Combined degradation from health state
* Goal: Image dies as sound dies, synced to loop boundaries

### Phase 4: Death & Completion
* [ ] Death threshold and behaviors (silence/freeze/collapse)
* [ ] Reverb tail continuation after death (3-5 sec)
* [ ] Extended silence (10 sec)
* [ ] Fade to black (5 sec), no text
* [ ] Resurrect function (reset to 100% health)
* [ ] Key press to restart after death
* Goal: Complete lifecycle with meaningful ending

### Phase 5: Modes & Presets
* [ ] Stochastic mode implementation
* [ ] Mystery mode implementation
* [ ] Preset data structure
* [ ] Save/load functions
* [ ] Factory presets (6 tape types with room)
* [ ] User preset management
* [ ] PRESETS page UI
* Goal: Multiple decay modes + recallable characters

### Phase 6: Polish
* [ ] User image upload support
* [ ] Settings menu
* [ ] Waveform overlay on LOOP page
* [ ] Tempo/quantize system
* [ ] Edge case handling
* [ ] Performance optimization
* Goal: Release-ready single-head experience

### Phase 7: Expansion (Future)
* [ ] Multiple heads (expand to 4 voices)
* [ ] Head selection UI
* [ ] Per-head parameters
* [ ] Phase relationships (free/locked, maybe attract)
* [ ] Inter-head influence (cascade/independent/sympathy)
* [ ] Global start/stop all
* [ ] MIDI clock sync
* [ ] Input recording capability (optional)

## Future Considerations (Document Only)
Not in initial build, documented for potential implementation:
* Smoothed degradation option: Distribute degradation across loop instead of step at boundary
* Phase "attract" mode: Heads slowly drift toward phase alignment
* Crossfade loop option: Smooth loop boundaries (requires dual playhead implementation)
* Multiple images: Cycle or randomize source image
* Visual themes: Different degradation aesthetics
* Grid integration: Tactile control surface (function TBD)
* Record degradation timeline: Save parameter automation over time
* Import/export presets: Share tape types between users
* Quad output: Each head to separate output
* Alternative health calculations: Min-based, worst-engine-based, user-weighted
* Visual-audio desync: Image leads or lags sound intentionally
* Input recording: Record directly into sample slot

## Technical Notes

### SuperCollider Considerations
* Engine changes require full system restart (SYSTEM > RESTART)
* Buffer allocation for 4 × 3-minute mono samples
* OSC communication for loop boundary sync (/ember/loop_wrap)
* FreeVerb or similar for room engine (CPU-friendly)

### Performance Targets
* Single head playing without dropouts
* Visual updates on loop wrap without impacting audio
* Smooth encoder response
* Room reverb not exceeding CPU budget

### Error Handling
* Graceful behavior if sample fails to load
* Preset validation (handle missing/corrupt files)
* Health bounds checking (never go below 0 or above 100)

### Poetic Parameter Names (Reference)
For interface display, consider these mappings:

| Technical | Poetic Alternative |
|---|---|
| degradation_rate | forgetting |
| fidelity | clarity |
| temporal | stability |
| dropout | erosion |
| spectral | presence |
| saturation | heat |
| noise | dust |
| room | space |
| health | memory |
| death_threshold | horizon |
| stereo_width | focus |
| mystery_mode | witness |

Final naming decisions during UI implementation.

---
*End of specification*
