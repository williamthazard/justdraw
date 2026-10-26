// just draw's engine: one morphing voice, played from the tablet.
// The only SuperCollider class in the script; the SynthDefs live in jd_voice.scd and jd_fx.scd.
Engine_JustDraw : CroneEngine {
	var voiceBus, reverbBus, delayBus, voiceGroup, fxGroup, reverbGroup, outGroup, outSynth, sends, delay, reverb, voice;
	var noise = 0.5, ratio = 0.7, release = 0.5;
	// Carter's delay (jd_grains.scd): nothing is allocated until grains_on 1. grainSet holds every
	// setting, so values sent while the chain is off (or still allocating) apply when it comes up.
	var grainsBus, grainsOn = false, grainsLive = false, grainsGen = 0;
	var grainSet, grainRates;
	var grainGroups, grainBuf, grainEnvBufs, grainPtrBus, grainPtr, grainRec, grainFb, grainSynths;
	var grainDurs, grainDelays;
	classvar grainCount = 4, grainBeatSec = 0.5;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		var dir = PathName(this.class.filenameSymbol.asString).pathOnly;
		var defs = [thisProcess.interpreter.executeFile(dir +/+ "jd_voice.scd")]
			++ thisProcess.interpreter.executeFile(dir +/+ "jd_fx.scd");
		defs = defs ++ thisProcess.interpreter.executeFile(dir +/+ "jd_grains.scd");
		defs.do { |def| def.add };
		Server.default.sync;

		voiceBus = Bus.audio(context.server, 2);
		voiceGroup = Group.new(context.xg);
		reverbBus = Bus.audio(context.server, 2);
		delayBus = Bus.audio(context.server, 2);
		grainsBus = Bus.audio(context.server, 1);
		this.initGrains;
		fxGroup = Group.after(voiceGroup);
		// Node order: a bus written by a node that runs after its reader is lost for that cycle.
		// The reverb reads reverbBus, which \jd_delay and Carter's delay both write, so it gets a
		// group of its own after fxGroup: voices, fxGroup (sends, delay), Carter's delay (its three
		// groups come right after fxGroup), reverbGroup, then the output stage. Each new synth goes
		// to the head of fxGroup, so adding delay, then sends runs them sends, delay.
		reverbGroup = Group.after(fxGroup);
		reverb = Synth.new(\jd_reverb, [\in, reverbBus, \out, context.out_b], reverbGroup);
		delay = Synth.new(\jd_delay, [\in, delayBus, \out, context.out_b, \reverbOut, reverbBus], fxGroup);
		sends = Synth.new(\jd_sends, [
			\in, voiceBus, \out, context.out_b, \reverbOut, reverbBus, \delayOut, delayBus,
			\grainsOut, grainsBus
		], fxGroup);

		// The tail of everything: outGroup comes right after reverbGroup, and every group made later
		// (Carter's delay allocates its three with Group.after(fxGroup)) lands before reverbGroup, so
		// \jd_out always runs last. -10 dB (0.316) until the script's param sends its value.
		outGroup = Group.after(reverbGroup);
		outSynth = Synth.new(\jd_out, [\out, context.out_b, \level, 10 ** (-10 / 20)], outGroup);

		this.addCommand(\set_out_level, "f", { arg msg; outSynth.set(\level, msg[1]) });
		this.addCommand(\voice_on, "fff", { arg msg;
			this.releaseVoice;
			voice = Synth.new(\jd_voice, [
				\out, voiceBus, \note, msg[1], \intensity, msg[2], \pressure, msg[3],
				\noise, noise, \ratio, ratio, \release, release
			], voiceGroup);
		});
		this.addCommand(\voice_move, "fff", { arg msg;
			if(voice.notNil) { voice.set(\note, msg[1], \intensity, msg[2], \pressure, msg[3]) };
		});
		this.addCommand(\voice_off, "", { arg msg;
			this.releaseVoice;
		});
		this.addCommand(\set_noise, "f", { arg msg;
			noise = msg[1];
			if(voice.notNil) { voice.set(\noise, noise) };
		});
		this.addCommand(\set_ratio, "f", { arg msg;
			ratio = msg[1];
			if(voice.notNil) { voice.set(\ratio, ratio) };
		});
		this.addCommand(\set_release, "f", { arg msg;
			release = msg[1];
			if(voice.notNil) { voice.set(\release, release) };
		});

		// Effects: each command sets one control on the synth that owns it.
		[
			[\set_reverb_send, { sends }, \reverb_send], [\set_delay_send, { sends }, \delay_send],
			[\set_grains_send, { sends }, \grains_send],
			[\set_delay_time, { delay }, \delayTime], [\set_delay_decay, { delay }, \decayTime],
			[\set_delay_level, { delay }, \amp], [\set_delay_to_reverb, { delay }, \to_reverb],
			[\set_delay_to_dry, { delay }, \to_dry], [\set_reverb_room, { reverb }, \room],
			[\set_reverb_damp, { reverb }, \damp], [\set_reverb_level, { reverb }, \amp]
		].do { |row|
			this.addCommand(row[0], "f", { arg msg; row[1].value.set(row[2], msg[1]) });
		};

		// Carter's delay.
		this.addCommand(\grains_on, "i", { arg msg;
			if(msg[1] > 0) { this.allocGrains } { this.freeGrains };
		});
		[
			[\set_grains_level, \level], [\set_grains_to_reverb, \toReverb],
			[\set_grains_freeze, \freeze], [\set_grains_rec_pre, \recPre],
			[\set_grains_window, \window], [\set_grains_sync, \sync],
			[\set_grains_cutoff_ceiling, \ceiling], [\set_grains_rate_mult, \rateMult],
			[\set_grains_octaves, \octaves], [\set_grains_fifths, \fifths],
			[\set_grains_suboctaves, \suboctaves], [\set_grains_reverse, \reverse],
			[\set_grains_delay_scale, \delayScale], [\set_grains_fb_amp, \fbAmp],
			[\set_grains_fb_balance, \fbBalance], [\set_grains_fb_hpf, \fbHpf],
			[\set_grains_fb_noise, \fbNoise], [\set_grains_fb_sine_level, \fbSineLevel],
			[\set_grains_fb_sine_hz, \fbSineHz]
		].do { |row|
			this.addCommand(row[0], "f", { arg msg; this.setGrain(row[1], msg[1]) });
		};
		[[\set_grains_pan_rate, \panRate], [\set_grains_cutoff_rate, \cutoffRate],
			[\set_grains_res_rate, \resRate]].do { |row|
			this.addCommand(row[0], "if", { arg msg; this.setGrainRate(row[1], msg[1].asInteger, msg[2]) });
		};
	}

	// ---- Carter's delay: ported from schicksalslied 2's Lied.sc (ensureGranularChain and friends) ----

	initGrains {
		grainSet = Dictionary.newFrom([
			\level, 0.3, \toReverb, 0, \freeze, 0, \recPre, 0, \window, 0, \sync, 1, \ceiling, 16000,
			\rateMult, 1, \octaves, 0, \fifths, 0, \suboctaves, 0, \reverse, 0, \delayScale, 1,
			\fbAmp, 0, \fbBalance, 0, \fbHpf, 12, \fbNoise, 0, \fbSineLevel, 0, \fbSineHz, 55
		]);
		grainRates = (panRate: Array.fill(grainCount, { rrand(1, 64) }),
			cutoffRate: Array.fill(grainCount, { rrand(1, 64) }), resRate: Array.fill(grainCount, { rrand(1, 64) }));
	}

	// Playback rates of the grains, from the octave, fifth, sub-octave and reverse switches.
	grainTapRates {
		var oct = grainSet[\octaves] > 0, fif = grainSet[\fifths] > 0, sub = grainSet[\suboctaves] > 0;
		var base = case
			{ oct and: fif and: sub } { [1/2, 1, 3/2, 2] }
			{ oct and: fif } { [1, 2, 3/2, 4/3] }
			{ oct and: sub } { [1/4, 1/2, 1, 2] }
			{ fif and: sub } { [1/2, 1, 3/2, 4/3] }
			{ oct } { [1, 2, 1, 2] }
			{ fif } { [1, 3/2, 4/3, 9/8] }
			{ sub } { [1, 1/2, 1/4, 1/2] }
			{ true } { [1/4, 1/2, 1, 3/2] };
		^grainCount.collect { |i|
			var rate = base[i % base.size];
			(if(grainSet[\reverse] > 0 and: { i.odd }) { rate.neg } { rate }) * grainSet[\rateMult].max(0.01)
		};
	}

	grainEnvNum {
		^if(grainSet[\window] == 0) { -1 } { grainEnvBufs[grainSet[\window].asInteger - 1].bufnum }
	}

	// Sends one stored setting to the live chain.
	pushGrain { arg key;
		var value = grainSet[key];
		case
			{ key == \level } { grainSynths.do { |g| g.set(\amp, value) } }
			{ key == \toReverb } { grainSynths.do { |g| g.set(\toReverb, value) } }
			{ key == \sync } { grainSynths.do { |g| g.set(\sync, value) } }
			{ key == \ceiling } { grainSynths.do { |g| g.set(\cutoffMax, value) } }
			{ key == \window } { grainSynths.do { |g| g.set(\grainEnv, this.grainEnvNum) } }
			{ key == \recPre } { grainRec.set(\preLevel, value) }
			{ key == \freeze } {
				grainPtr.set(\rate, if(value > 0) { 0 } { 1 });
				grainRec.run(value <= 0);
			}
			{ [\rateMult, \octaves, \fifths, \suboctaves, \reverse].includes(key) } {
				this.grainTapRates.do { |rate, i|
					grainSynths[i].set(\rate, rate, \dens, 1 / (grainDurs[i] * rate.abs));
				};
			}
			{ key == \fbAmp } { grainFb.set(\amp, value) }
			{ key == \fbBalance } { grainFb.set(\balance, value) }
			{ key == \fbHpf } { grainFb.set(\hpFreq, value) }
			{ key == \fbNoise } { grainFb.set(\noiseLevel, value) }
			{ key == \fbSineLevel } { grainFb.set(\sineLevel, value) }
			{ key == \fbSineHz } { grainFb.set(\sineHz, value) };
	}

	// Stores a setting and, once the chain is up, sends it.
	setGrain { arg key, value;
		grainSet[key] = value;
		if(grainsLive) { this.pushGrain(key) };
	}

	setGrainRate { arg key, index, rate;
		if(index < grainCount) {
			grainRates[key][index] = rate;
			if(grainsLive) { grainSynths[index].set(key, rate) };
		};
	}

	allocGrains {
		var gen;
		if(grainsOn) { ^this };
		grainsOn = true;
		gen = grainsGen = grainsGen + 1;
		fork {
			var server = context.server;
			var delayScale = grainSet[\delayScale];
			var rates;
			grainBuf = Buffer.alloc(server, server.sampleRate * (grainBeatSec * 512), 1);
			grainEnvBufs = [
				Buffer.sendCollection(server, Env.perc(0.01, 0.99, 1, -4).asSignal(512)),
				Buffer.sendCollection(server, Env.new([0, 1, 0], [0.7, 0.3], [3, -3]).asSignal(512)),
				Buffer.sendCollection(server, Env.new([0, 1, 0], [0.98, 0.02], [4, -4]).asSignal(512))
			];
			grainPtrBus = Bus.audio(server, 1);
			server.sync;
			// Freed while allocating: only the buffers and bus exist, so free them and stop.
			if(gen != grainsGen) {
				grainBuf.free; grainEnvBufs.do(_.free); grainPtrBus.free;
			} {
				// ptr, rec and grains run after fxGroup, so \jd_sends has written grainsBus first, and
				// before reverbGroup, so the grains' writes reach the reverb bus before it is read.
				grainGroups = Array.newClear(3);
				grainGroups[0] = Group.after(fxGroup);
				grainGroups[1] = Group.after(grainGroups[0]);
				grainGroups[2] = Group.after(grainGroups[1]);
				grainPtr = Synth(\jd_ptr, [\buf, grainBuf, \out, grainPtrBus,
					\rate, if(grainSet[\freeze] > 0) { 0 } { 1 }], grainGroups[0]);
				grainFb = Synth(\jd_fbmix, [\in, context.out_b, \out, grainsBus, \amp, grainSet[\fbAmp],
					\balance, grainSet[\fbBalance], \hpFreq, grainSet[\fbHpf], \noiseLevel, grainSet[\fbNoise],
					\sineLevel, grainSet[\fbSineLevel], \sineHz, grainSet[\fbSineHz]], grainGroups[0]);
				grainRec = Synth(\jd_rec, [\ptrIn, grainPtrBus, \micIn, grainsBus, \buf, grainBuf,
					\preLevel, grainSet[\recPre]], grainGroups[1]);
				if(grainSet[\freeze] > 0) { grainRec.run(false) };
				rates = this.grainTapRates;
				grainDurs = grainCount.collect({ |i| grainBeatSec * (i + 1) }).scramble;
				grainDelays = grainCount.collect({ |i|
					server.sampleRate * (grainBeatSec * (i + 1)) * 16 * delayScale
				}).scramble;
				grainSynths = grainCount.collect { |n|
					Synth(\jd_gran, [
						\amp, grainSet[\level], \buf, grainBuf, \out, context.out_b,
						\reverbOut, reverbBus, \toReverb, grainSet[\toReverb], \atk, 1, \rel, 1, \gate, 1,
						\sync, grainSet[\sync], \dens, 1 / (grainDurs[n] * rates[n].abs),
						\baseDur, grainDurs[n], \durRand, 1, \rate, rates[n], \rateRand, 1,
						\grainEnv, this.grainEnvNum, \ptrBus, grainPtrBus, \ptrSampleDelay, grainDelays[n],
						\ptrRandSamples, server.sampleRate * (grainBeatSec * (n + 1)) * 2,
						\minPtrDelay, grainDelays[n], \cutoffMax, grainSet[\ceiling], \beatSec, grainBeatSec,
						\panRate, grainRates[\panRate][n], \cutoffRate, grainRates[\cutoffRate][n],
						\resRate, grainRates[\resRate][n]
					], grainGroups[2]);
				};
				grainsLive = true;
			};
		};
	}

	freeGrains {
		if(grainsOn.not) { ^this };
		grainsOn = false;
		grainsGen = grainsGen + 1;
		if(grainsLive) {
			grainsLive = false;
			grainGroups.do(_.free);
			grainEnvBufs.do(_.free);
			grainBuf.free;
			grainPtrBus.free;
			grainGroups = grainSynths = grainPtr = grainRec = grainFb = nil;
			grainBuf = grainEnvBufs = grainPtrBus = nil;
		};
	}

	releaseVoice {
		if(voice.notNil) { voice.set(\gate, 0); voice = nil };
	}

	free {
		this.releaseVoice;
		this.freeGrains;
		sends.free;
		delay.free;
		reverb.free;
		outSynth.free;
		outGroup.free;
		reverbGroup.free;
		fxGroup.free;
		voiceGroup.free;
		voiceBus.free;
		reverbBus.free;
		delayBus.free;
		grainsBus.free;
	}
}
