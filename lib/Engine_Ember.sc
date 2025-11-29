// Engine_Ember
// Basinski-style loop disintegration engine for norns
// Phase 1: Single head, fidelity degradation only

Engine_Ember : CroneEngine {
    var <synth;
    var <buffer;
    var <fidelityBus;

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    alloc {
        // Allocate buffer for sample (mono or stereo, up to 60 seconds at 48kHz)
        buffer = Buffer.alloc(context.server, context.server.sampleRate * 60 * 2, 2);

        // Audio bus for fidelity processing
        fidelityBus = Bus.audio(context.server, 2);

        // Main synthesis architecture
        SynthDef(\emberVoice, {
            arg out, buf,
            // Playback
            gate = 1, level = 0.8,
            loopStart = 0, loopLength = 1,
            // Fidelity degradation
            bitDepth = 16, sampleRateDiv = 1,
            fidelityState = 0.0;

            var snd, playhead, loopEnd, loopSamples;
            var degraded;
            var bits, srDiv;
            var env;

            // Calculate loop endpoints in samples
            loopEnd = loopStart + loopLength;
            loopSamples = loopLength * BufSampleRate.kr(buf);

            // Playback with looping
            playhead = Phasor.ar(0, BufRateScale.kr(buf),
                loopStart * BufSampleRate.kr(buf),
                loopEnd * BufSampleRate.kr(buf),
                loopStart * BufSampleRate.kr(buf));

            snd = BufRd.ar(2, buf, playhead, 1, 4); // 4-point interpolation

            // Fidelity degradation (0.0 = pristine, 1.0 = destroyed)
            // Bit depth: 16 → 1 bit (exponential curve)
            bits = 16 * (1 - fidelityState).pow(2);
            bits = bits.max(1);

            // Sample rate divisor: 1 → 24 (48kHz → 2kHz, logarithmic)
            srDiv = 1 + ((fidelityState.pow(0.5)) * 23);
            srDiv = srDiv.min(24);

            // Apply bit depth reduction (quantization)
            degraded = snd.round(2.pow(1 - bits));

            // Apply sample rate reduction (sample and hold)
            degraded = Latch.ar(degraded, Impulse.ar(SampleRate.ir / srDiv));

            // Envelope for clean start/stop
            env = EnvGen.kr(Env.asr(0.01, 1, 0.1), gate, doneAction: 0);

            Out.ar(out, degraded * level * env);
        }).add;

        // Wait for SynthDef to load, then create synth
        context.server.sync;

        synth = Synth.new(\emberVoice, [
            \out, context.out_b,
            \buf, buffer,
            \gate, 0, // Start stopped
            \level, 0.8,
            \loopStart, 0,
            \loopLength, 1,
            \bitDepth, 16,
            \sampleRateDiv, 1,
            \fidelityState, 0.0
        ], target: context.xg);

        // Commands for Lua communication

        // Load sample from file
        this.addCommand(\loadSample, "s", { arg msg;
            var path = msg[1].asString;
            buffer.allocRead(path, completionMessage: {
                ("Loaded sample: " ++ path).postln;
            });
        });

        // Start playback
        this.addCommand(\start, "", { arg msg;
            synth.set(\gate, 1);
        });

        // Stop playback
        this.addCommand(\stop, "", { arg msg;
            synth.set(\gate, 0);
        });

        // Set loop start (in seconds)
        this.addCommand(\loopStart, "f", { arg msg;
            synth.set(\loopStart, msg[1]);
        });

        // Set loop length (in seconds)
        this.addCommand(\loopLength, "f", { arg msg;
            synth.set(\loopLength, msg[1]);
        });

        // Set level
        this.addCommand(\level, "f", { arg msg;
            synth.set(\level, msg[1]);
        });

        // Set fidelity degradation state (0.0-1.0)
        this.addCommand(\fidelityState, "f", { arg msg;
            synth.set(\fidelityState, msg[1].clip(0.0, 1.0));
        });

        // Set fidelity rate (for auto-degradation, handled in Lua)
        // This is just for manual testing
        this.addCommand(\fidelityRate, "f", { arg msg;
            // Store for reference, actual degradation happens in Lua
        });
    }

    free {
        synth.free;
        buffer.free;
        fidelityBus.free;
    }
}
