// just draw's Carter's delay: a granular delay, ported from schicksalslied 2's chain in Lied.sc
// (\liedPtr, \liedRec, \liedFbPatchMix, \liedGran), itself ported from carters-delay-norns.
// Evaluates to an Array of unadded SynthDefs. Nothing here is allocated until the engine switches
// the chain on. There is no mic: the recorder reads only the mono bus \jd_sends writes (grains_send)
// plus the feedback patch. Each grain's pan, cutoff and resonance LFOs run inside the grain synth
// (Lied used one Ndef per LFO), so the rates are plain synth controls and the chain is SynthDefs only.
[
	// Pointer (write head): advances through the delay buffer.
	SynthDef(\jd_ptr, { |out = 0, buf = 0, rate = 1|
		Out.ar(out, Phasor.ar(0, BufRateScale.kr(buf) * rate, 0, BufFrames.kr(buf)));
	}),
	// Recorder: writes (bus + preLevel * existing buffer) to the delay buffer.
	SynthDef(\jd_rec, { |ptrIn = 0, micIn = 0, buf = 0, preLevel = 0|
		var ptr = In.ar(ptrIn, 1);
		var sig = In.ar(micIn, 1);
		// softclip bounds the recirculated part (|out| < 1), so at preLevel 1 the buffer can't
		// grow without limit pass after pass. It is linear below 0.5.
		sig = sig + (BufRd.ar(1, buf, ptr) * preLevel).softclip;
		BufWr.ar(sig, buf, ptr);
	}),
	// Feedback patch: the main output, balanced, softclipped and high-passed (plus optional noise
	// and sine), written back to the recorder's bus.
	SynthDef(\jd_fbmix, { |in = 0, out = 0, amp = 0, amp_slew = 0.05, balance = 0,
		hpFreq = 12, noiseLevel = 0, sineLevel = 0, sineHz = 55|
		var input = InFeedback.ar(in, 2);
		var sig = Balance2.ar(input[0], input[1], balance);
		sig = sig + (PinkNoise.ar * noiseLevel);
		sig = sig + (SinOsc.ar(sineHz) * sineLevel);
		sig = HPF.ar(sig, hpFreq.max(5));
		Out.ar(out, sig.softclip * amp.lag3(amp_slew));
	}),
	// Grain synth: reads the delay buffer at randomized rates and positions.
	SynthDef(\jd_gran, { |amp = 0, amp_slew = 0.05, buf = 0, out = 0, atk = 1, rel = 1, gate = 1,
		sync = 1, dens = 40, baseDur = 0.05, durRand = 1, rate = 1, rateRand = 1,
		grainEnv = (-1), ptrBus = 0, ptrSampleDelay = 20000, ptrRandSamples = 5000,
		minPtrDelay = 1000, cutoffMax = 16000, beatSec = 0.5,
		panRate = 8, cutoffRate = 8, resRate = 8|
		var sig, env, trig, dur, rt, ptr, ptrRand, totalDelay, pan, cutoff, res;
		env = EnvGen.kr(Env.asr(atk, 1, rel), gate, doneAction: 2);
		trig = CoinGate.ar(sync.clip(0, 1), Impulse.ar(dens)) + CoinGate.ar(1 - sync.clip(0, 1), Dust.ar(dens));
		dur = baseDur * LFNoise1.kr(100).exprange(1 / durRand, durRand);
		rt = rate.lag3(0.5) * LFNoise1.kr(100).exprange(1 / rateRand, rateRand);
		ptrRand = LFNoise1.kr(100).bipolar(ptrRandSamples);
		totalDelay = max(ptrSampleDelay - ptrRand, minPtrDelay);
		ptr = (In.ar(ptrBus, 1) - totalDelay) / BufFrames.kr(buf);
		dur = min(dur, (totalDelay / rt.abs) / SampleRate.ir);
		pan = LFTri.kr(1 / (panRate * beatSec)).range(-1, 1);
		cutoff = LFTri.kr(1 / (cutoffRate * beatSec)).range(500, 15000);
		res = LFTri.kr(1 / (resRate * beatSec)).range(0, 2);
		sig = GrainBuf.ar(1, trig, dur, buf, rt, ptr, 4, 0, grainEnv);
		sig = MoogFF.ar(sig * env * amp.lag3(amp_slew), min(cutoff, cutoffMax).clip(50, 18000), res.clip(0, 4));
		Out.ar(out, Pan2.ar(sig, pan));
	})
]
