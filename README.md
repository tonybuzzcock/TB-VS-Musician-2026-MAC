# HH VS Musician (Reverb) — modern Mac version

The same plugin as [HH-VS-Musician](https://github.com/tonybuzzcock/HH-VS-Musician)
(same amp model, panel and presets), built for current Macs:

- **CLAP, VST3 and AU (AUv2)**: Reaper, FL Studio, Logic, GarageBand, Ableton Live and others
- **Universal**: native on Apple Silicon and Intel, **macOS 11 Big Sur and later**
- Built and tested on GitHub Actions, including Apple's `auval`, `pluginval` and `clap-validator`

The plugin is written once as a CLAP (`Source/Plugin`); [clap-wrapper](https://github.com/free-audio/clap-wrapper)
builds the VST3 and AU from the same code, so all three behave identically.
The settings are saved with your DAW session, and the plugin reports its latency
(40 samples) and its reverb tail to the host.

## Install

Download the latest green run under **Actions → Artifacts → HH-VS-Musician-Reverb-mac**
(or a Release), unzip it, and follow `INSTALL.txt`. Copy the formats you want
into the `VST3`, `Components` or `CLAP` folder. Those are in
`/Library/Audio/Plug-Ins/` (the main Library) or `~/Library/Audio/Plug-Ins/`
(your user Library); use whichever one your other plugins are in. Then run the
short Terminal lines `INSTALL.txt` gives for that folder. The plugins are ad-hoc
signed, not notarised, so those lines clear macOS's download tags and re-sign
the plugins on your Mac.

## Controls

The first 14 parameters follow the front panel (`Docs/front_panel.jpg`) left to right.
Channel numbering follows the owner's amp: **Channel 1** is the Volume channel and
**Channel 2** is the Gain (V-S) channel. The service drawing numbers them the other
way round (Volume = AS00017 "CH 2", Gain = AS00016 "CH 1"), and the source code
keeps the drawing's names.

| # | Name | Panel control | Range |
|---|------|---------------|-------|
| 1 | 1 Volume | Ch 1 Volume | 0 – 10 |
| 2 | 1 Bass | Ch 1 Bass | −5 · 0 · +5 |
| 3 | 1 Treble | Ch 1 Treble | −5 · 0 · +5 |
| 4 | 1 Reverb | Ch 1 Reverb switch | Off / On |
| 5 | 2 Gain | Ch 2 Gain | 0 – 10 |
| 6 | 2 Bass | Ch 2 Bass | −5 · 0 · +5 |
| 7 | Middle | Middle | −5 · 0 · +5 |
| 8 | 2 Treble | Ch 2 Treble | −5 · 0 · +5 |
| 9 | Presence | Presence | −5 · 0 · +5 |
| 10 | 2 Reverb | Ch 2 Reverb switch | Off / On |
| 11 | Voice | Voice | Light / Heavy |
| 12 | ValveSnd | Valve Sound | Off / On |
| 13 | M Reverb | Master Reverb | 0 – 10 |
| 14 | M Volume | Master Volume | 0 – 10 |
| 15 | Channel | *plugin only*: which input the guitar feeds | 1 / 2 / 1+2 |
| 16 | Speaker | *plugin only*: miked 2x12, or the speaker-terminal signal for your own IR | On / Off |
| 17 | Input | *plugin only*: input trim | ±12 dB |
| 18 | Output | *plugin only*: output trim | ±24 dB |

## The panel

On the Mac the plugin opens its own panel (1200 × 330): an original design laid
out like the amp's controls, with the plugin-only controls in a strip along the
bottom. Drag knobs up/down (hold Shift for fine control), double-click a knob to
reset it, or use the scroll wheel. Rocker switches: press the top half for On,
the bottom half for Off. The green readout in the bottom strip shows the control
you last touched.

**Presets:** click **SAVE**, then one of the slots **1–8**, to store every setting
(including Channel, Speaker, Input and Output). Click a slot to recall it. Saved
slots are dark, the slot in use lights green. Presets are kept in
`~/Library/Application Support/TB/HH VS Musician (Reverb)/Presets.txt`, shared by
every copy of the plugin, every session and all three formats.

## What is modelled, and how

**From the component values on the drawing** (nodal circuit solver, 4x oversampled,
741 op-amps with 1 MHz gain-bandwidth, 0.5 V/µs slew and ±14 V swing):

- Gain channel (Ch 2 here, AS00016): 2N5089 long-tail pair + 741 gain stage with the dual-action Gain pot,
  R22 switched in by Voice (S1B) for Heavy, the passive Baxandall Bass/Treble,
  and the 741 with 1M5 feedback whose clipping gives the V-S sustain
- Volume channel (Ch 1 here, AS00017): 741 gain stage with dual-action Volume, Baxandall Bass/Treble, 741 with 1M5 feedback
- Reverb driver and recovery stages (AS00018) and the Master Reverb pot
- Power amp (AS00014/4): closed-loop gain ×39 with its input and feedback-leg
  low-cut, slew limit, clipping against ±48 V rails that sag through the 80 VA
  transformer and 4700 µF reservoirs, and the Q4/Q5 V-I current limiter, all
  working into the real speaker load through L1/R29 and the Zobel
- The speaker load: an electrical model of the two 12" drivers (voice-coil
  resistance and inductance, cone resonance). With Speaker on, the output is
  the cone's acceleration, so the low end and the amp-speaker interaction come
  from that model

**From behaviour, because they are not circuits on the drawing:**

- The AS00015/A V-S tone correction module (Middle, Presence, the module side
  of Voice, and Valve Sound): only its pins are shown
- The 4C spring tank (a two-spring dispersive delay model)
- Cone breakup and cabinet colouration above about 1 kHz

## Readings and assumptions to check

- **Volume channel C7** is 1,000 pF on the drawing (the Gain channel uses 0.1 µF in the same
  place). As drawn, the Volume channel came out a little thin next to the real amp, so the model uses 2,200 pF.
  Going to 4,700 pF would fill it out further.
- "25K R/LOG" Gain and Volume pots are taken as reverse-log.
- The Volume channel is played through Input 1 with Input 2 empty (its jack grounds R2).
- L1 has no value on the sheet; 3 µH is used (it only matters above the audio band).
- The 12" drivers' parameters are typical for 1970s 12" guitar speakers, not measured.

## Building

```
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

On a Mac this builds all three formats into `build/plugins` as universal binaries;
on Linux it builds the CLAP and the tests. The CLAP, VST3 and AudioUnit SDKs are
downloaded automatically. Tests: `build/preset_test`, `build/clap_host_test <clap>`,
`build/musician_test <render dir>`, and on the Mac `build/panel_test <clap> <png dir>`.

## Licences

This project's code is the owner's. It uses the CLAP SDK and clap-wrapper (MIT),
the VST 3 SDK (MIT; "VST" is a trademark of Steinberg Media Technologies GmbH) and
Apple's AudioUnitSDK (Apache 2.0). It is an independent model made for personal use
and is not affiliated with H/H Electronic.
