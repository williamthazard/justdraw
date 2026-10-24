// just draw's voice: one Just Friends-style morphing oscillator (the approved sound, spec Appendix A).
// Evaluates to the unadded SynthDef; the engine (and tests/nrt_voice.scd) add or send it.
// One Just Friends-style slope cycling at audio rate (after the Whimsical Raps technical map):
// RAMP splits each cycle into rise and fall (0.5 = triangle, near 0 = saw), CURVE bends both
// slopes (-1 square < log < 0 linear < exp < 1 sine), and FLOOM-style linear through-zero FM from
// a sine at `ratio` x the pitch turns it to broadband noise at the right edge.
// x walks a path through them: 0 sine, 0.2 exp curves, 0.4 linear near-saw, 0.7 log, 1 near-square + deep FM.
// No folding or saturation: the noise comes from modulation, not clipping.
SynthDef(\jd_voice, { |out = 0, note = 48, intensity = 0, pressure = 0, gate = 1, release = 0.5, ratio = 0.7, noise = 2|
	var p = Lag.kr(pressure, 0.02);
	// pressing hard pushes the morph a little further right
	var x = (Lag.kr(intensity, 0.03) + (p * 0.08)).clip(0, 1);
	var freq = Lag.kr(note, 0.015).midicps;
	var ramp = IEnvGen.kr(Env([0.5, 0.5, 0.15, 0.04, 0.01], [0.1, 0.3, 0.3, 0.3]), x);
	var curve = IEnvGen.kr(Env([1, 0.5, 0, -0.5, -0.85], [0.2, 0.2, 0.3, 0.3]), x);
	var depth = IEnvGen.kr(Env([0, 0, 1.5, noise], [0.45, 0.3, 0.25]), x);
	var modRatio = IEnvGen.kr(Env([1, 1, ratio], [0.6, 0.4]), x) * (1 + (LFNoise1.kr(0.7) * 0.02 * depth.min(1)));
	// evens out the loudness along x (x = 0, 0.1 .. 1): half the measured RMS drop, capped, because the
	// narrow pulses at the right are spiky (high peaks for their RMS) and brighter sounds seem louder anyway
	var gain = IEnvGen.kr(Env([1, 0.95, 0.96, 1.04, 1.03, 1.04, 1.09, 1.15, 1.26, 1.3, 1.3], 0.1 ! 10), x);
	var kLog = 2 ** (curve.neg.max(0) * 5.6);
	var kExp = 2 ** (curve.clip(0, 0.5) * 4);
	var toSine = ((curve - 0.5) * 2).clip(0, 1);
	// one slope segment: u runs 0 to 1 across the rise (or the fall)
	var bend = { |u|
		var shaped = (1 - ((1 - u) ** kLog)) ** kExp;
		(shaped * (1 - toSine)) + ((0.5 - (0.5 * (u * pi).cos)) * toSine)
	};
	var phase = Phasor.ar(0, freq * (1 + (depth * SinOsc.ar(freq * modRatio))) * SampleDur.ir, 0, 1);
	var rising = phase < ramp;
	var up = bend.((phase / ramp).clip(0, 1));
	var down = 1 - bend.(((phase - ramp) / (1 - ramp)).clip(0, 1));
	var env = EnvGen.kr(Env.asr(0.005, 1, release, -3), gate, doneAction: 2);
	var sig = (((rising * up) + ((1 - rising) * down)) * 2) - 1;
	// full pressure on the left peaks near -12 dBFS, like tabletseq's own voices; softclip is only a
	// safety for the spikes at the right edge (it leaves anything below -6 dBFS untouched)
	sig = LeakDC.ar(LPF.ar(sig, 14000)) * gain * (p ** 1.5) * env * 0.25;
	Out.ar(out, (sig ! 2).softclip);
});
