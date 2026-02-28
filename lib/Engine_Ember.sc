// Engine_Ember
// Loop disintegration engine for norns
// Full degradation chain: Fidelity → Temporal → Dropout → Spectral → Saturation → Noise → Room → Width → Out

Engine_Ember : CroneEngine {
    var <buffers;       // 4 sample slot buffers
    var <synth;         // playback voice
    var <reverbSynth;   // room/space (separate for tail after death)
    var <noiseSynth;    // hiss + crackle generator
    var <busVerb;       // bus to reverb
    var <busDry;        // bus for dry signal routing
    var <loopCount;     // track loop completions
    var <oscAddr;       // OSC address for loop_wrap

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    alloc {
        var server = context.server;

        // Allocate 4 sample buffers (mono, 3 minutes max at 48kHz)
        buffers = Array.fill(4, {
            Buffer.alloc(server, server.sampleRate * 180, 1);
        });

        loopCount = 0;

        // Audio buses
        busVerb = Bus.audio(server, 2);
        busDry = Bus.audio(server, 2);

        // OSC address for sending loop wrap notifications back to Lua
        oscAddr = NetAddr("localhost", 10111);

        // =============================================
        // MAIN VOICE SYNTHDEF
        // Full chain: playback → fidelity → temporal → dropout → spectral → saturation → width → out
        // Noise and Room are separate synths for independence
        // =============================================
        SynthDef(\emberVoice, {
            arg out, verbOut, buf = 0,
            gate = 0, level = 0.8, pan = 0,
            loopStart = 0, loopLength = 1, speed = 1.0,
            // Fidelity
            fidelityState = 0.0,
            fidelityCorrelation = 0.7,
            fidelityCurve = 0.5,
            fidelityBypass = 0,
            // Temporal
            temporalState = 0.0,
            wowDepthMax = 100, flutterDepthMax = 50,
            driftEnabled = 1, driftVal = 0,
            temporalBypass = 0,
            // Dropout
            dropoutState = 0.0,
            dropoutMaxLength = 0.2, dropoutMaxFreq = 10,
            dropoutBypass = 0,
            // Spectral
            spectralState = 0.0,
            spectralTarget = 500, spectralResonance = 0.1,
            midScoopEnabled = 0, midScoopState = 0.0,
            spectralBypass = 0,
            // Saturation
            saturationState = 0.0,
            saturationMax = 18, saturationAsymmetry = 0.3,
            saturationWarmth = 0.5,
            saturationBypass = 0,
            // Width
            widthState = 0.0, widthTarget = 0.2,
            widthBypass = 0;

            var snd, playhead, loopEnd, trig, phase;
            var bits, srDiv, degraded;
            var wowLfo, flutterLfo, pitchMod;
            var dropEnv, dropTrig, dropFreq, dropLen;
            var cutoff, res, filtered, midFreq, midNotch;
            var drive, driven, warmth;
            var mid, side, width;
            var env;
            var loopSamples, loopEndSamples, startSamples;

            // Calculate loop endpoints in samples
            startSamples = loopStart * BufSampleRate.kr(buf);
            loopEndSamples = (loopStart + loopLength) * BufSampleRate.kr(buf);
            loopSamples = loopLength * BufSampleRate.kr(buf);

            // Playhead with loop detection
            playhead = Phasor.ar(0,
                BufRateScale.kr(buf) * speed,
                startSamples,
                loopEndSamples,
                startSamples
            );

            // Detect loop wrap: when playhead resets to start
            trig = Trig1.ar(
                (playhead - startSamples) < (BufRateScale.kr(buf) * speed * 2),
                0.01
            );

            // Send OSC on loop wrap (delayed slightly to avoid init trigger)
            SendReply.ar(trig, '/ember/loop_wrap', [0], 0);

            // Read from buffer (mono)
            snd = BufRd.ar(1, buf, playhead, 1, 4);

            // Make stereo for processing chain
            snd = snd ! 2;

            // ---- ENGINE 1: FIDELITY ----
            degraded = if(fidelityBypass > 0, snd, {
                var bitReduced, srReduced;
                // Bit depth: 16 → 1 bit (exponential)
                bits = LinExp.kr(1 - fidelityState, 0.001, 1.0, 1, 16).clip(1, 16);
                // Sample rate divisor: 1 → 24 (logarithmic, influenced by correlation)
                srDiv = LinExp.kr(fidelityState * (fidelityCorrelation.linlin(0, 1, 0.5, 1.0)),
                    0.001, 1.0, 1, 24).clip(1, 24);

                bitReduced = snd.round(2.pow(1 - bits));
                srReduced = Latch.ar(bitReduced, Impulse.ar(SampleRate.ir / srDiv));
                srReduced;
            });

            // ---- ENGINE 2: TEMPORAL ----
            degraded = if(temporalBypass > 0, degraded, {
                var wowed;
                // Wow: slow pitch, depth grows with state
                wowLfo = SinOsc.kr(LFNoise1.kr(0.1).range(0.5, 3.0));
                wowLfo = wowLfo * (temporalState * wowDepthMax / 1200); // cents to ratio

                // Flutter: fast noise, depth grows with state
                flutterLfo = LFNoise2.kr(LFNoise1.kr(0.2).range(5, 15));
                flutterLfo = flutterLfo * (temporalState * flutterDepthMax / 1200);

                // Drift: applied from Lua as a fixed offset (accumulates over time)
                pitchMod = 1.0 + wowLfo + flutterLfo + (driftVal / 1200 * driftEnabled);

                // Apply pitch modulation via delay modulation
                wowed = DelayC.ar(degraded,
                    0.05,
                    SinOsc.ar(0).range(0, 0).max(0.001) +
                    ((1.0 - pitchMod).abs.clip(0, 0.04) * 0.05).max(0.0001)
                );
                // Simpler approach: PitchShift for wow/flutter
                PitchShift.ar(degraded, 0.1, pitchMod.clip(0.5, 2.0), 0.01, 0.01);
            });

            // ---- ENGINE 3: DROPOUT ----
            degraded = if(dropoutBypass > 0, degraded, {
                // Dropout frequency grows from 0 to max
                dropFreq = dropoutState * dropoutMaxFreq;
                // Dropout length grows from minimal to max
                dropLen = dropoutState.linlin(0, 1, 0.001, dropoutMaxLength);
                // Dust-based trigger scaled by frequency
                dropTrig = Dust.kr(dropFreq);
                // Envelope: 1 = playing, 0 = dropout
                dropEnv = 1 - EnvGen.kr(Env.perc(0.001, dropLen, 1, -4), dropTrig);
                degraded * dropEnv;
            });

            // ---- ENGINE 4: SPECTRAL ----
            degraded = if(spectralBypass > 0, degraded, {
                // Cutoff drops exponentially from 20kHz to target
                cutoff = LinExp.kr(1 - spectralState, 0.001, 1.0,
                    spectralTarget.max(200), 20000).clip(200, 20000);
                // Resonance develops over time
                res = spectralState * spectralResonance;
                filtered = RLPF.ar(degraded, cutoff, (1 - res).max(0.1));

                // Optional mid-scoop (print-through)
                filtered = if(midScoopEnabled > 0, {
                    midFreq = 1000;
                    midNotch = BPF.ar(filtered, midFreq, 0.5);
                    filtered - (midNotch * midScoopState * 0.75); // up to -12dB
                }, filtered);

                filtered;
            });

            // ---- ENGINE 5: SATURATION ----
            degraded = if(saturationBypass > 0, degraded, {
                // Drive grows from 0dB to max
                drive = (saturationState * saturationMax).dbamp;
                // Pre-emphasis: 100Hz warmth boost
                warmth = BLowShelf.ar(degraded, 100, 1, saturationWarmth * saturationState * 6);
                // Asymmetric soft clipping (tanh)
                driven = (warmth * drive).tanh;
                // Asymmetry: compress positive peaks more
                driven = Select.ar(driven > 0, [
                    driven,
                    driven * (1 - (saturationAsymmetry * saturationState * 0.3))
                ]);
                // Compensate gain
                driven = driven * drive.reciprocal.sqrt;
                driven;
            });

            // ---- STEREO WIDTH ----
            degraded = if(widthBypass > 0, degraded, {
                // Mid-side processing
                mid = (degraded[0] + degraded[1]) * 0.5;
                side = (degraded[0] - degraded[1]) * 0.5;
                // Width collapses toward target
                width = 1.0 - (widthState * (1.0 - widthTarget));
                [(mid + (side * width)), (mid - (side * width))];
            });

            // Envelope
            env = EnvGen.kr(Env.asr(0.01, 1, 0.05), gate, doneAction: 0);

            // Output: dry to main out + send to reverb bus
            Out.ar(out, Pan2.ar(degraded.sum * 0.5, pan) * level * env);
            Out.ar(verbOut, degraded * level * env);
        }).add;

        // =============================================
        // ROOM/SPACE SYNTHDEF (separate for reverb tail after death)
        // =============================================
        SynthDef(\emberRoom, {
            arg in, out,
            roomSize = 0.3, wet = 0.1, damping = 0.3,
            roomBypass = 0, gate = 1;

            var snd, verb, env;

            snd = In.ar(in, 2);

            verb = FreeVerb2.ar(snd[0], snd[1],
                mix: wet,
                room: roomSize,
                damp: damping
            );

            env = EnvGen.kr(Env.asr(0.01, 1, 5.0), gate, doneAction: 0);

            Out.ar(out, Select.ar(roomBypass, [verb, snd]) * env);
        }).add;

        // =============================================
        // NOISE SYNTHDEF (hiss + crackle, separate for flexibility)
        // =============================================
        SynthDef(\emberNoise, {
            arg out,
            hissLevel = -90, crackleRate = 0,
            noiseBypass = 0, gate = 1;

            var hiss, crackle, env;

            // Pink noise (hiss)
            hiss = PinkNoise.ar(hissLevel.dbamp) ! 2;

            // Crackle: short impulses
            crackle = Dust2.ar(crackleRate) * 0.3 ! 2;

            env = EnvGen.kr(Env.asr(0.01, 1, 0.1), gate, doneAction: 0);

            Out.ar(out, Select.ar(noiseBypass, [(hiss + crackle) * env, DC.ar(0) ! 2]));
        }).add;

        // Wait for SynthDefs
        server.sync;

        // Create synths in correct order (room reads from bus, must be after voice writes)
        reverbSynth = Synth.new(\emberRoom, [
            \in, busVerb,
            \out, context.out_b,
            \roomSize, 0.3,
            \wet, 0.1,
            \damping, 0.3,
            \gate, 1
        ], target: context.xg, addAction: \addToTail);

        synth = Synth.new(\emberVoice, [
            \out, context.out_b,
            \verbOut, busVerb,
            \buf, buffers[0],
            \gate, 0,
            \level, 0.8,
            \pan, 0,
            \loopStart, 0,
            \loopLength, 1,
            \speed, 1.0,
            \fidelityState, 0.0,
            \temporalState, 0.0,
            \dropoutState, 0.0,
            \spectralState, 0.0,
            \saturationState, 0.0,
            \widthState, 0.0
        ], target: context.xg, addAction: \addToHead);

        noiseSynth = Synth.new(\emberNoise, [
            \out, context.out_b,
            \hissLevel, -90,
            \crackleRate, 0,
            \gate, 1
        ], target: context.xg, addAction: \addToTail);

        // =============================================
        // COMMANDS
        // =============================================

        // Sample loading (slot 0-3, path)
        this.addCommand(\loadSample, "is", { arg msg;
            var slot = msg[1].asInteger.clip(0, 3);
            var path = msg[2].asString;
            buffers[slot].free;
            buffers[slot] = Buffer.readChannel(server, path, channels: [0], action: { arg buf;
                ("ember: loaded sample to slot " ++ slot ++ " (" ++ buf.numFrames ++ " frames)").postln;
            });
        });

        // Assign buffer to voice
        this.addCommand(\assignSlot, "i", { arg msg;
            var slot = msg[1].asInteger.clip(0, 3);
            synth.set(\buf, buffers[slot]);
        });

        // Transport
        this.addCommand(\start, "", { arg msg; synth.set(\gate, 1); });
        this.addCommand(\stop, "", { arg msg; synth.set(\gate, 0); });

        // Playback params
        this.addCommand(\loopStart, "f", { arg msg; synth.set(\loopStart, msg[1]); });
        this.addCommand(\loopLength, "f", { arg msg; synth.set(\loopLength, msg[1].max(0.01)); });
        this.addCommand(\speed, "f", { arg msg; synth.set(\speed, msg[1].clip(0.25, 2.0)); });
        this.addCommand(\level, "f", { arg msg; synth.set(\level, msg[1].clip(0.0, 1.0)); });
        this.addCommand(\pan, "f", { arg msg; synth.set(\pan, msg[1].clip(-1.0, 1.0)); });

        // Fidelity
        this.addCommand(\fidelityState, "f", { arg msg; synth.set(\fidelityState, msg[1].clip(0, 1)); });
        this.addCommand(\fidelityCorrelation, "f", { arg msg; synth.set(\fidelityCorrelation, msg[1].clip(0, 1)); });
        this.addCommand(\fidelityCurve, "f", { arg msg; synth.set(\fidelityCurve, msg[1].clip(0, 1)); });
        this.addCommand(\fidelityBypass, "i", { arg msg; synth.set(\fidelityBypass, msg[1]); });

        // Temporal
        this.addCommand(\temporalState, "f", { arg msg; synth.set(\temporalState, msg[1].clip(0, 1)); });
        this.addCommand(\wowDepthMax, "f", { arg msg; synth.set(\wowDepthMax, msg[1].clip(0, 200)); });
        this.addCommand(\flutterDepthMax, "f", { arg msg; synth.set(\flutterDepthMax, msg[1].clip(0, 100)); });
        this.addCommand(\driftEnabled, "i", { arg msg; synth.set(\driftEnabled, msg[1]); });
        this.addCommand(\driftVal, "f", { arg msg; synth.set(\driftVal, msg[1]); });
        this.addCommand(\temporalBypass, "i", { arg msg; synth.set(\temporalBypass, msg[1]); });

        // Dropout
        this.addCommand(\dropoutState, "f", { arg msg; synth.set(\dropoutState, msg[1].clip(0, 1)); });
        this.addCommand(\dropoutMaxLength, "f", { arg msg; synth.set(\dropoutMaxLength, msg[1].clip(0.001, 0.5)); });
        this.addCommand(\dropoutMaxFreq, "f", { arg msg; synth.set(\dropoutMaxFreq, msg[1].clip(0.1, 20)); });
        this.addCommand(\dropoutBypass, "i", { arg msg; synth.set(\dropoutBypass, msg[1]); });

        // Spectral
        this.addCommand(\spectralState, "f", { arg msg; synth.set(\spectralState, msg[1].clip(0, 1)); });
        this.addCommand(\spectralTarget, "f", { arg msg; synth.set(\spectralTarget, msg[1].clip(200, 20000)); });
        this.addCommand(\spectralResonance, "f", { arg msg; synth.set(\spectralResonance, msg[1].clip(0, 0.5)); });
        this.addCommand(\midScoopEnabled, "i", { arg msg; synth.set(\midScoopEnabled, msg[1]); });
        this.addCommand(\midScoopState, "f", { arg msg; synth.set(\midScoopState, msg[1].clip(0, 1)); });
        this.addCommand(\spectralBypass, "i", { arg msg; synth.set(\spectralBypass, msg[1]); });

        // Saturation
        this.addCommand(\saturationState, "f", { arg msg; synth.set(\saturationState, msg[1].clip(0, 1)); });
        this.addCommand(\saturationMax, "f", { arg msg; synth.set(\saturationMax, msg[1].clip(0, 24)); });
        this.addCommand(\saturationAsymmetry, "f", { arg msg; synth.set(\saturationAsymmetry, msg[1].clip(0, 1)); });
        this.addCommand(\saturationWarmth, "f", { arg msg; synth.set(\saturationWarmth, msg[1].clip(0, 1)); });
        this.addCommand(\saturationBypass, "i", { arg msg; synth.set(\saturationBypass, msg[1]); });

        // Width
        this.addCommand(\widthState, "f", { arg msg; synth.set(\widthState, msg[1].clip(0, 1)); });
        this.addCommand(\widthTarget, "f", { arg msg; synth.set(\widthTarget, msg[1].clip(0, 1)); });
        this.addCommand(\widthBypass, "i", { arg msg; synth.set(\widthBypass, msg[1]); });

        // Room
        this.addCommand(\roomSize, "f", { arg msg; reverbSynth.set(\roomSize, msg[1].clip(0, 1)); });
        this.addCommand(\roomWet, "f", { arg msg; reverbSynth.set(\wet, msg[1].clip(0, 1)); });
        this.addCommand(\roomDamping, "f", { arg msg; reverbSynth.set(\damping, msg[1].clip(0, 1)); });
        this.addCommand(\roomBypass, "i", { arg msg; reverbSynth.set(\roomBypass, msg[1]); });

        // Room gate (for reverb tail continuation after death)
        this.addCommand(\roomGate, "i", { arg msg; reverbSynth.set(\gate, msg[1]); });

        // Noise
        this.addCommand(\hissLevel, "f", { arg msg; noiseSynth.set(\hissLevel, msg[1].clip(-90, -20)); });
        this.addCommand(\crackleRate, "f", { arg msg; noiseSynth.set(\crackleRate, msg[1].clip(0, 50)); });
        this.addCommand(\noiseBypass, "i", { arg msg; noiseSynth.set(\noiseBypass, msg[1]); });
        this.addCommand(\noiseGate, "i", { arg msg; noiseSynth.set(\gate, msg[1]); });

        // Get buffer info (returns duration)
        this.addCommand(\getBufferDuration, "i", { arg msg;
            var slot = msg[1].asInteger.clip(0, 3);
            var dur = buffers[slot].duration;
            // Send back via OSC
            NetAddr("localhost", 10111).sendMsg('/ember/buffer_info', slot, dur);
        });
    }

    free {
        synth.free;
        reverbSynth.free;
        noiseSynth.free;
        buffers.do({ arg buf; buf.free; });
        busVerb.free;
        busDry.free;
    }
}
