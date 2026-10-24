// just draw's effects. Evaluates to an Array of unadded SynthDefs.
// \jd_dry reads the stereo voice bus and writes it out unchanged.
[
	SynthDef(\jd_dry, { |in = 0, out = 0|
		Out.ar(out, In.ar(in, 2));
	})
]
