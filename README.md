# ScoreMaker

ScoreMaker is a small Objective-C AppKit score viewer for macOS and GNUstep. It opens Standard MIDI files and MusicKit-style `.score` scorefiles, renders their pitched notes on simple treble and bass staves, and can save the current score back out as a `.score` file.

The renderer is intentionally lightweight. It focuses on extracting timing, pitch, tempo, and time-signature data well enough to inspect a score visually; it is not a full notation editor or MusicKit synthesis environment.

## Features

- Open `.mid` and `.midi` Standard MIDI files.
- Import uncompressed MusicXML `.musicxml` and `.xml` files.
- Open MusicKit text scorefiles with the `.score` extension.
- Save the currently loaded score as a MusicKit-style `.score` file.
- Export scores as uncompressed MusicXML.
- Render notes across treble and bass staves with measure lines.
- Read MIDI tempo and time-signature metadata when available.
- Add pitched notes and edit score notes, tempo, and time signature from the inspector next to the sheet.
- Play the current score through AVFoundation on macOS or GNUstep.
- Show active notes on an 88-key piano with middle C marked as C4, display live MIDI-velocity meters for each voice during playback, and audition and enter notes by clicking the piano keys.
- Accept live CoreMIDI keyboard input on macOS for velocity-sensitive step entry and quantized real-time recording with chord detection, count-in, metronome, and sustain-pedal handling.
- Support document-level Undo/Redo, single-action undo for complete MIDI takes, CoreMIDI hot-plug updates, and routing either to the selected part or from MIDI channels to parts.
- Print the rendered score from the standard print panel.
- Support common MusicKit scorefile timing, variable, `freq`, `keyNum`, `noteOn`, `noteOff`, `noteUpdate`, and duration-note patterns.
- Map common scorefile instrument, patch, sound, preset, and program declarations to General MIDI sounds for playback.
- Host AUv2 and AUv3 music devices out of process, with vendor and generic editors, user presets,
  missing-unit relinking, substitution tracking, validation timeouts, recovery, and blacklisting.
- Apply persistent per-part gain, low-pass, compressor, delay, and reverb chains during real-time
  internal synthesis and offline rendering; compatible native effects also process Audio Unit output.
- Run opt-in compatibility validation for every installed Audio Unit instrument with
  `make test-plugins`; results are written to `build/tests/audio-unit-compatibility.json`.

The native macOS plug-in format is currently sufficient for the supported macOS host. VST3 is
therefore not enabled by default; it requires the Steinberg VST3 SDK and a separate host adapter
before ScoreMaker targets systems or vendors that do not supply Audio Units.
- Preserve independent note voices and explicit measure boundaries, including pickup measures and per-measure time signatures.
- Reflow measures across systems and printed pages according to notation density, with collision-aware onset spacing, displaced seconds in chords, and staggered accidental columns.
- Import, export, preserve, and render key signatures, ties, tuplets, dynamics, common articulations, and repeat barlines.

## Screenshots

### macOS
<img width="1555" height="1081" alt="scoremaker" src="https://github.com/user-attachments/assets/4fdb1678-1407-4168-a3e5-f73f4fa958d8" />

### GNUstep
<img width="1572" height="1105" alt="scoremaker-gnustep" src="https://github.com/user-attachments/assets/d338857c-d2fa-4711-ad0d-8f0963ff4d41" />

## Build

To open the project in GNUstep ProjectCenter, open `PC.project`. The checked-in
GNUmakefile remains usable directly from the command line.

On macOS:

```sh
make
open build/macos/ScoreMaker.app
```

On GNUstep:

```sh
make
gopen ScoreMaker.app
```

The GNUstep build expects `gnustep-config`, GNUstep GUI libraries, and an Objective-C compiler to be installed.

## Use

Open the app, then choose `File > Open...` to load a `.mid`, `.midi`, or `.score` file.

The bundled `examples/neon-causeway.score` is an original, copyright-free synthwave composition demonstrating bass, pad, lead, chords, accidentals, parts, and playback.
The bundled `examples/time-rotor-study.score` is an original CC0 electronic science-fiction title study in 6/8. It is intentionally not an arrangement of any television theme.
The bundled `examples/mozart-requiem/` collection contains fourteen independently openable complete multi-track scores, one for each commonly separated movement of Mozart's Requiem, K. 626.

Use the inspector on the right side of the sheet to add pitched notes, add freeform score notes, change the tempo in BPM, or change the time signature.
The inspector scrolls vertically when the window is not tall enough to show its complete palette and score-notes editor.

Choose a connected device under **MIDI Input** for live entry. With recording stopped, played notes are entered at the inspector's Start position and simultaneous held notes form a chord. Choose a Grid value and press **Record** for a one-measure count-in followed by real-time recording; press **Stop** to quantize and insert the captured performance. MIDI velocity and sustain-pedal note lengths are preserved.
The input menu updates when MIDI devices are connected or removed. **Selected Part** routing sends all channels to the inspector's current part; **MIDI Channel → Part** maps channel 1 to Part 1, channel 2 to Part 2, and so on. Use **Edit → Undo/Redo** or Command-Z/Command-Shift-Z to reverse and restore edits; one recording take is one undo operation.

Choose `Score > Play` or the Play button in the inspector to hear the current score. ScoreMaker sends the generated MIDI data directly to AVFoundation, using the platform AVFoundation implementation on macOS or GNUstep.

Choose `File > Print...` to print the complete rendered score.

To save the displayed score as a MusicKit-style scorefile, choose `File > Save Score As...`.

You can also pass a file path directly when launching the built macOS app:

```sh
build/macos/ScoreMaker.app/Contents/MacOS/ScoreMaker path/to/song.mid
build/macos/ScoreMaker.app/Contents/MacOS/ScoreMaker path/to/song.score
```

## Project Layout

- `src/AppDelegate.*`: App lifecycle, menus, open/save panels, and file dispatch.
- `src/MidiParser.*`: Standard MIDI parser.
- `src/ScorefileParser.*`: MusicKit `.score` reader and writer.
- `src/ScoreModel.*`: Shared score and note model.
- `src/NotationModel.*`: Normalized semantic notation elements used across rendering and future playback/export work.
- `src/EngravingLayout.*`: Deterministic system breaking and rhythmic horizontal-position pipeline.
- `src/ScoreView.*`: AppKit score rendering.
- `Info.plist`: macOS app metadata and document type declarations.
- `Makefile`: macOS and GNUstep build targets.

## Limitations

ScoreMaker maps common MusicKit-style instrument declarations to General MIDI programs for playback, but it does not emulate MusicKit synthesis engines, envelopes, wave tables, or DSP patch settings. When saving `.score` files, it writes the renderable note data and track program mappings from the current document rather than preserving every original source statement or comment.

ScoreMaker keeps `.score` note statements compatible with MusicKit-style readers. Voice assignments and explicit measure structure are stored in an additional `ScoreMaker Structure V2` JSON metadata comment; older readers can ignore that comment and continue reading pitches, timing, parts, and programs. Files without V2 structure metadata open as voice 1 with measures derived from their time signature.

MIDI parsing supports Standard MIDI files with tick-based timing. SMPTE time-division MIDI files are not supported.

## Clean

Remove generated build artifacts with:

```sh
make clean
```
