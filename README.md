# just draw

a one-voice instrument for norns, played on a wacom one pen tablet. the tablet plugs straight
into norns. nothing else is needed.

the voice is a just friends-style oscillator. it glides in pitch as the pen moves up and down,
gets louder with pressure, and goes from a clean sine to a noisy, folded sound as the pen
moves to the right. it can also play a midi synth and a modular through crow, alone or together.

## install

copy this folder to `/home/we/dust/code/justdraw/` on the norns. once the repo is public,
`;install https://github.com/williamthazard/justdraw` in maiden does the same.

the first install needs a norns restart, so the new engine registers.

## the pen

- the pen's height on the tablet is pitch. it glides across the dots; there are no steps.
- the pen's side to side position is the sound: sine on the left, noisy on the right.
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
- root and octave
- flip 180: turns the tablet around
- tablet: auto, or a hid port 1 to 4
- outputs: engine, midi, crow, just friends, w/syn
- midi: device, channel, bend range, x cc, send cc
- just friends mode (normal or synthesis); w/syn voices, lpg time, lpg symmetry, hold or pluck
- effects (engine only): reverb and delay. delay sync is "1" by default, so the delay lasts one
  beat of the norns clock and follows its tempo, whether that is set in params, by link, by midi
  or by crow. pick a division from 1/16 to 8 beats, capped at 8 seconds. choose "free" to set
  delay time yourself, in seconds.

## good to know

- with no tablet, the screen says "plug in the tablet". plugging it in or out while the script
  runs is fine.
- loading another script lets go of every note and drops the crow gate.
- the check list for a first run is in `docs/norns-check.md`.

mit license. made by william hazard.
