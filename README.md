# ember

loop disintegration instrument for norns

inspired by William Basinski's *The Disintegration Loops*

load samples, set loop regions, and witness them gradually decay through multiple degradation processes. a visual representation degrades in parallel with the audio.

## requirements

- norns (220802 or later)
- audio samples

## install

```
;install https://github.com/thomcummings/ember
```

## overview

- 4 sample slots, 1 active playhead
- 7 degradation engines: fidelity, temporal, dropout, spectral, saturation, noise, room
- degradation applied as step changes at loop boundaries
- deterministic, stochastic, or mystery decay modes
- procedural cityscape image degrades with the audio
- "tape type" presets define degradation character

## controls

| control | function |
|---------|----------|
| E1 | page selection |
| E2 | parameter selection |
| E3 | adjust value |
| K2 | next page |
| K3 | play/pause or context action |
| K1+K3 | reset head to start |

## pages

1. **SAMPLE** - load and select samples
2. **LOOP** - set loop start, length, quantize
3. **PLAYBACK** - speed, level, pan, width
4. **FIDELITY** - bit/sample rate reduction
5. **TEMPORAL** - wow, flutter, drift
6. **DROPOUT** - silence injection, erosion
7. **SPECTRAL** - lowpass rolloff, mid-scoop
8. **SATURATION** - distortion, warmth
9. **NOISE** - hiss, crackle
10. **ROOM** - reverb (the witness, not the dying thing)
11. **HEALTH** - death threshold and mode
12. **MASTER** - speed multiplier, decay mode
13. **PRESETS** - tape type recall

## factory presets

- **Archival** - very slow, gentle fade
- **Oxide** - medium, tape-damage character
- **Thermal** - warm then harsh
- **Glacial** - extremely slow (20+ min)
- **Cascade** - medium-fast, chaotic
- **Dust** - noise-dominant

## philosophy

*the dying is the point. the ending matters. leave room for the accident.*

## license

MIT
