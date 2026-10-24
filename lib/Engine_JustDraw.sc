// just draw's engine: one morphing voice, played from the tablet.
// The only SuperCollider class in the script; the SynthDefs live in jd_voice.scd and jd_fx.scd.
Engine_JustDraw : CroneEngine {
	var voiceBus, reverbBus, delayBus, voiceGroup, fxGroup, sends, delay, reverb, voice;
	var noise = 2, ratio = 0.7, release = 0.5;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		var dir = PathName(this.class.filenameSymbol.asString).pathOnly;
		var defs = [thisProcess.interpreter.executeFile(dir +/+ "jd_voice.scd")]
			++ thisProcess.interpreter.executeFile(dir +/+ "jd_fx.scd");
		defs.do { |def| def.add };
		Server.default.sync;

		voiceBus = Bus.audio(context.server, 2);
		voiceGroup = Group.new(context.xg);
		reverbBus = Bus.audio(context.server, 2);
		delayBus = Bus.audio(context.server, 2);
		fxGroup = Group.after(voiceGroup);
		// Each new synth goes to the head of fxGroup, so adding reverb, delay, then sends
		// runs them sends, delay, reverb: the delay's writes reach the reverb bus before it is read.
		reverb = Synth.new(\jd_reverb, [\in, reverbBus, \out, context.out_b], fxGroup);
		delay = Synth.new(\jd_delay, [\in, delayBus, \out, context.out_b, \reverbOut, reverbBus], fxGroup);
		sends = Synth.new(\jd_sends, [
			\in, voiceBus, \out, context.out_b, \reverbOut, reverbBus, \delayOut, delayBus
		], fxGroup);

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
			[\set_delay_time, { delay }, \delayTime], [\set_delay_decay, { delay }, \decayTime],
			[\set_delay_level, { delay }, \amp], [\set_delay_to_reverb, { delay }, \to_reverb],
			[\set_delay_to_dry, { delay }, \to_dry], [\set_reverb_room, { reverb }, \room],
			[\set_reverb_damp, { reverb }, \damp], [\set_reverb_level, { reverb }, \amp]
		].do { |row|
			this.addCommand(row[0], "f", { arg msg; row[1].value.set(row[2], msg[1]) });
		};
	}

	releaseVoice {
		if(voice.notNil) { voice.set(\gate, 0); voice = nil };
	}

	free {
		this.releaseVoice;
		sends.free;
		delay.free;
		reverb.free;
		fxGroup.free;
		voiceGroup.free;
		voiceBus.free;
		reverbBus.free;
		delayBus.free;
	}
}
