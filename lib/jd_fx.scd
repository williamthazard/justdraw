// just draw's effects. Evaluates to an Array of unadded SynthDefs, ported from schicksalslied 2's
// \liedDelay and \liedReverb. Node order is voices and \jd_input (same group), \jd_sends, \jd_delay,
// Carter's delay (when it is on, writing the reverb bus too), \jd_reverb (in its own group, after the
// grains), then (in a group at the very tail of the engine) \jd_out.
// \jd_sends reads the stereo voice bus: the dry signal goes to `out` unchanged, and scaled copies
// go to the reverb and delay buses and, as a mono sum, to Carter's delay (grainsOut). The delay feeds `out` and the reverb bus; the reverb feeds `out` and a bus of its own (fbOut).
[
	// norns' audio input (inL and inR, the two mono buses of context.in_b) into the effects: scaled
	// copies go to the reverb and delay buses and, as a mono average, to Carter's delay (grainsOut).
	// It never writes the main output: norns' own monitor level (LEVELS > monitor) already passes the
	// dry input, and writing it here too would double it.
	SynthDef(\jd_input, { |inL = 0, inR = 1, reverbOut = 0, delayOut = 0, grainsOut = 0,
		reverb_send = 0, delay_send = 0, grains_send = 0|
		var sig = [In.ar(inL), In.ar(inR)];
		Out.ar(reverbOut, sig * reverb_send.lag(0.05));
		Out.ar(delayOut, sig * delay_send.lag(0.05));
		Out.ar(grainsOut, (sig[0] + sig[1]) * 0.5 * grains_send.lag(0.05));
	}),
	SynthDef(\jd_sends, { |in = 0, out = 0, reverbOut = 0, delayOut = 0, grainsOut = 0,
		reverb_send = 0, delay_send = 0, grains_send = 0|
		var sig = In.ar(in, 2);
		Out.ar(out, sig);
		Out.ar(reverbOut, sig * reverb_send.lag(0.05));
		Out.ar(delayOut, sig * delay_send.lag(0.05));
		// Carter's delay records a mono sum; nothing reads grainsOut while the chain is off.
		Out.ar(grainsOut, (sig[0] + sig[1]) * 0.5 * grains_send.lag(0.05));
	}),
	SynthDef(\jd_delay, { |in = 0, out = 0, reverbOut = 0, delayTime = 0.3, decayTime = 15,
		amp = 1, amp_slew = 0.1, to_reverb = 1, to_dry = 0|
		var sig = In.ar(in, 2);
		// CombL's maximum is 8 s: 16 s overran the real-time memory pool on norns in Lied.
		var del = CombL.ar(sig, 8.0, delayTime, decayTime) * amp.lag(amp_slew);
		Out.ar(out, del * to_dry.lag(0.05));
		Out.ar(reverbOut, del * to_reverb.lag(0.05));
	}),
	// The reverb also writes a copy of its output to fbOut, for the feedback patch: it runs after
	// \jd_fbmix, which could not otherwise hear it on `out` (see jd_grains.scd).
	SynthDef(\jd_reverb, { |in = 0, out = 0, fbOut = 0, room = 0.5, damp = 0.5, amp = 1, amp_slew = 0.1|
		var rev = FreeVerb.ar(In.ar(in, 2), 1.0, room, damp) * amp.lag(amp_slew);
		Out.ar(out, rev);
		Out.ar(fbOut, rev);
	}),
	// The last node of everything the engine makes: the output level (linear amp) and a safety
	// limiter at -1 dBFS, applied in place on the stereo output bus.
	SynthDef(\jd_out, { |out = 0, level = 0.316|
		var sig = In.ar(out, 2) * level.lag(0.05);
		ReplaceOut.ar(out, Limiter.ar(sig, -1.dbamp, 0.005));
	})
]
