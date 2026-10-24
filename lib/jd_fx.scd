// just draw's effects. Evaluates to an Array of unadded SynthDefs, ported from schicksalslied 2's
// \liedDelay and \liedReverb. Node order is voices, \jd_sends, \jd_delay, \jd_reverb.
// \jd_sends reads the stereo voice bus: the dry signal goes to `out` unchanged, and scaled copies
// go to the reverb and delay buses. The delay feeds `out` and the reverb bus; the reverb feeds `out`.
[
	SynthDef(\jd_sends, { |in = 0, out = 0, reverbOut = 0, delayOut = 0, reverb_send = 0, delay_send = 0|
		var sig = In.ar(in, 2);
		Out.ar(out, sig);
		Out.ar(reverbOut, sig * reverb_send.lag(0.05));
		Out.ar(delayOut, sig * delay_send.lag(0.05));
	}),
	SynthDef(\jd_delay, { |in = 0, out = 0, reverbOut = 0, delayTime = 0.3, decayTime = 0.5,
		amp = 1, amp_slew = 0.1, to_reverb = 1, to_dry = 0|
		var sig = In.ar(in, 2);
		// CombL's maximum is 8 s: 16 s overran the real-time memory pool on norns in Lied.
		var del = CombL.ar(sig, 8.0, delayTime, decayTime) * amp.lag(amp_slew);
		Out.ar(out, del * to_dry.lag(0.05));
		Out.ar(reverbOut, del * to_reverb.lag(0.05));
	}),
	SynthDef(\jd_reverb, { |in = 0, out = 0, room = 0.5, damp = 0.5, amp = 1, amp_slew = 0.1|
		var rev = FreeVerb.ar(In.ar(in, 2), 1.0, room, damp);
		Out.ar(out, rev * amp.lag(amp_slew));
	})
]
