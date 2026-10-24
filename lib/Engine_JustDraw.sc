// just draw's engine: one morphing voice, played from the tablet.
// The only SuperCollider class in the script; the SynthDefs live in jd_voice.scd and jd_fx.scd.
Engine_JustDraw : CroneEngine {
	var voiceBus, voiceGroup, fxGroup, dry, voice;
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
		fxGroup = Group.after(voiceGroup);
		dry = Synth.new(\jd_dry, [\in, voiceBus, \out, context.out_b], fxGroup);

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
	}

	releaseVoice {
		if(voice.notNil) { voice.set(\gate, 0); voice = nil };
	}

	free {
		this.releaseVoice;
		dry.free;
		fxGroup.free;
		voiceGroup.free;
		voiceBus.free;
	}
}
