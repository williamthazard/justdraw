# just draw

a one-voice instrument for norns, played on a wacom one pen tablet. the tablet plugs straight
into norns. nothing else is needed.

the voice is a just friends-style oscillator. it glides in pitch as the pen moves up and down,
gets louder with pressure, and morphs through sine, curves, saw and pulse into fm noise as the
pen moves to the right. it doesn't fold. it can also play a midi synth and a modular through crow, alone or together.

## install

copy this folder to `/home/we/dust/code/justdraw/` on the norns. once the repo is public,
`;install https://github.com/williamthazard/justdraw` in maiden does the same.

the first install needs a norns restart, so the new engine registers.

## the pen

- the pen's height on the tablet is pitch. it glides across the dots; there are no steps.
- the pen's side to side position is the sound: sine on the left, then curves, saw and pulse, then fm noise on the right.
- pressure is loudness. a light touch is quiet.
- the two buttons on the pen shift the octave up and down. a press while the pen hovers applies
  to the next note.
- lifting the pen lets the note go over the release time.
- the dots on the screen are the tablet's 15 x 10 grid.

## encoders and keys

- E1: noise
- E2: ratio
- E3: release
- K2: octave down
- K3: octave up

the encoders work on a note that is sounding, and whether or not the engine is switched on.

hold K1 for a shift layer (a quick tap still opens the norns menu; the layer starts after a
quarter second):

- E1: move a cursor along the E M C J W row. a small line under the letter shows where it is, and
  the cursor stays put when K1 is let go.
- K3: switch the output under the cursor on or off.
- K2: send the ii settings again (JF's mode and w/syn's settings) to the outputs that are on.
- E2: delay sync
- E3: delay decay

the screen's bottom strip shows each change. without K1, everything works as above.

## outputs

each output is switched on or off in params. engine is on at first; the rest are off.

- **engine** is norns' own sound.
- **midi** plays one channel. pitch bend carries the pitch between notes, channel pressure the pen
  pressure, and one cc the x position (74 at first). velocity follows the landing pressure.
  "send CC" in params sweeps the cc, for midi learn.
- **crow** puts pitch on out 1 (1 volt per octave, middle c at 0 v), the gate on out 2 (5 v),
  pressure on out 3 (0 to 5 v, falling over the release time at the lift) and x on out 4 (0 to 5 v).
- **just friends** over ii. each touch plays the next of six channels. E2 sets the fm ratio.
- **w/syn** over ii. each touch plays the next voice. x moves the wave shape.

## settings

all in params, so a pset saves and loads every one of them.

- noise, ratio, release
- engine level: the engine's output level in dB (-60 to +6, -10 at first). a safety limiter at
  -1 dBFS always sits after it, so a loud moment is held down instead of overloading norns. if the
  sound is still too loud, lower the engine level; if it is too quiet, raise it.
- tablet readings: switch on to show the tablet's raw numbers in place of the normal screen: the
  largest x, y and pressure since you switched it on, the last pen button pressed (upper or lower,
  and which code it sent) and the live x, y and pressure. it is for checking the tablet's range and
  which pen button is which. playing still works underneath. it is not saved in a pset.
- root and octave
- flip 180: turns the tablet around
- tablet: auto, or a hid port 1 to 4
- outputs: engine, midi, crow, just friends, w/syn
- midi: device, channel, bend range, x cc, send cc
- just friends mode (normal or synthesis); w/syn voices, lpg time, lpg symmetry, fm envelope (0 is off), hold or pluck
- effects (engine only), all off by default:
  - reverb: "reverb send" sets how much of the voice goes in; room, damp and level shape it.
  - delay: "delay send" sets how much goes in; decay, level, "delay to reverb" and "delay to dry"
    route it. delay sync is "1" by default, so the delay lasts one beat of the norns clock and
    follows its tempo, whether that is set in params, by link, by midi or by crow. pick a division
    from 1/16 to 8 beats, capped at 8 seconds. choose "free" to set delay time yourself, in seconds.
  - audio input: "input to reverb", "input to delay" and "input to carter's" send norns' audio input
    through the same effects, so a modular patched back into norns can blend with the voice. each
    runs 0 to 1 and starts at 0. the dry input is not sent to the output here: it stays on
    LEVELS > monitor in the norns menu, where it would otherwise be doubled.
    careful: if the modular also receives norns' output, the loop can feed back.
  - carter's delay: a granular delay (from schicksalslied 2) that stays unallocated until the
    "carter's delay" switch is on. "send to delay" feeds it and "delay level" sets its volume.
    "carter's to reverb" sends a share of it into the reverb as well. the
    granular switches are freeze, octaves, fifths & 4ths, sub-octaves and reverse. a feedback
    patch (amp, balance, hpf, and noise and sine injection) writes back into the delay. grain
    delay scale takes effect the next time the switch goes off and on.

## good to know

- with no tablet, the screen says "plug in the tablet". plugging it in or out while the script
  runs is fine.
- loading another script lets go of every note and drops the crow gate.

mit license. made by william hazard.
