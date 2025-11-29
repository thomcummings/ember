# EMBER

Basinski-style loop disintegration instrument for monome Norns.

Load samples, set loop points, and watch/hear them gradually decay through multiple degradation processes.

## Status

**Phase 1 - COMPLETE**
- Single playhead
- Fidelity degradation engine (bit depth + sample rate reduction)
- Basic UI with 4 pages
- Health tracking system

## Installation

```
;install https://github.com/thomcummings/ember
```

Or manually copy to `~/dust/code/ember/`

## Usage

### Quick Start

1. Load a sample: **K1+K3** (or **K3** on SAMPLE page)
2. Adjust loop points on LOOP page
3. Set degradation rate on FIDELITY page
4. Start playback: **K3**
5. Watch and listen as the loop degrades

### Controls

- **E1:** Page navigation
- **E2:** Select parameter
- **E3:** Change value
- **K2:** Next page
- **K3:** Start/stop playback (context-dependent)
- **K1+K3:** Load sample

### Pages

#### SAMPLE
- Load audio files from `~/dust/audio/`
- Supports WAV and AIFF formats

#### LOOP
- **start:** Loop start point in seconds (0-60s)
- **length:** Loop duration in seconds (0.1-60s)

#### FIDELITY
- **rate:** Degradation speed (0.0-1.0)
  - 0.01 = slow decay (~100 min to destruction)
  - 0.1 = moderate (~10 min)
  - 1.0 = fast (~1 min)
- **curve:** Exponential curve shape (0.0-1.0)
  - <0.5 = fast start, slow end
  - 0.5 = linear
  - >0.5 = slow start, fast end
- **correlation:** Bit/sample coupling (0.0-1.0)
  - Currently unused in Phase 1

Visual bar shows current degradation state (0-100%)

#### HEALTH
- **death threshold:** Health % at which playback stops (0-100%)
- **status:** Current health percentage
- **K3:** Reset to pristine state

Health bar visualization:
- Green (>30%): healthy
- Yellow (10-30%): degrading
- Red (<10%): critical
- Gray: dead

### Degradation Behavior

The **fidelity engine** applies two processes:

1. **Bit depth reduction**
   - 16-bit → 1-bit
   - Exponential curve
   - Creates quantization/stairstepping artifacts

2. **Sample rate reduction**
   - 48kHz → 2kHz
   - Logarithmic curve
   - Creates aliasing and bandwidth loss

Both processes advance based on the **rate** parameter and contribute to overall health decay.

### Death

When health drops below the **death threshold**, playback automatically stops. Use **K3** on the HEALTH page to reset all degradation to pristine state.

## Roadmap

### Phase 2: Complete Degradation Suite
- Temporal instability (wow/flutter/drift)
- Dropout/erosion events
- Spectral degradation (lowpass filter)
- Saturation/distortion
- Noise accumulation (hiss/crackle)

### Phase 3: Visual System
- Image degradation visualization
- Cityscape photograph disintegrating in parallel with audio
- Per-engine visual effects

### Phase 4: Multi-Head
- 4 independent playheads
- Phase relationships (free/locked/attract)
- Per-head degradation settings

### Phase 5: Global Systems
- Death influence modes (cascade/independent/sympathy)
- Stochastic degradation mode
- Inter-head correlation

### Phase 6: Presets
- Factory "tape type" presets
- User preset save/load
- Parameter morphing

### Phase 7: Polish
- User image upload
- Settings menu
- Documentation

## Architecture

### SuperCollider Engine
- `lib/Engine_Ember.sc`
- Single voice sample playback with looping
- Bit depth reduction via quantization
- Sample rate reduction via sample-and-hold (Latch)

### Lua Script
- `ember.lua` - Main script, UI, control
- `lib/degradation.lua` - State management, health calculation

### Update Loop
- 15 fps metro for degradation state updates
- Real-time communication to SuperCollider engine
- Separate 15 fps redraw metro

## Credits

Concept inspired by William Basinski's "The Disintegration Loops"

## License

MIT
