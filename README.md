# ScoreMaker

ScoreMaker is a small Objective-C AppKit score viewer for macOS and GNUstep. It opens Standard MIDI files and MusicKit-style `.score` scorefiles, renders their pitched notes on simple treble and bass staves, and can save the current score back out as a `.score` file.

The renderer is intentionally lightweight. It focuses on extracting timing, pitch, tempo, and time-signature data well enough to inspect a score visually; it is not a full notation editor or MusicKit synthesis environment.

## Features

- Open `.mid` and `.midi` Standard MIDI files.
- Import uncompressed MusicXML `.musicxml` and `.xml` files.
- Open MusicKit text scorefiles with the `.score` extension.
- Save the currently loaded score as a MusicKit-style `.score` file.
- Edit each score's MusicKit source in its own syntax-highlighted window, validate and apply it
  atomically, and preserve applied comments and statements when saving `.score` files.
- Export scores as uncompressed MusicXML.
- Render notes across treble and bass staves with measure lines.
- Read MIDI tempo and time-signature metadata when available.
- Add pitched notes and edit score notes, tempo, and time signature from the inspector next to the sheet.
- Play the current score through AVFoundation on macOS or GNUstep.
- Route individual parts to different physical CoreMIDI output devices on macOS, with persistent
  per-part assignments and built-in-synth fallback when a saved device is unavailable.
- Show active notes on an 88-key piano with middle C marked as C4, display live MIDI-velocity meters for each voice during playback, and audition and enter notes by clicking the piano keys.
- Accept live CoreMIDI keyboard input on macOS for velocity-sensitive step entry and quantized real-time recording with chord detection, count-in, metronome, and sustain-pedal handling.
- Support document-level Undo/Redo, single-action undo for complete MIDI takes, CoreMIDI hot-plug updates, and routing either to the selected part or from MIDI channels to parts.
- Loop an audition passage by selecting its first note, Shift-clicking its last note, and enabling **Score > Loop Selection**.
- Print the rendered score from the standard print panel.
- Support common MusicKit scorefile timing, variable, `freq`, `keyNum`, `noteOn`, `noteOff`, `noteUpdate`, and duration-note patterns.
- Map common scorefile instrument, patch, sound, preset, and program declarations to General MIDI sounds for playback.
- Host AUv2 and AUv3 music devices out of process, with vendor and generic editors, user presets,
  missing-unit relinking, substitution tracking, validation timeouts, recovery, and blacklisting.
- Apply persistent per-part gain, low-pass, compressor, delay, and reverb chains during real-time
  internal synthesis and offline rendering; compatible native effects also process Audio Unit output.
- Create per-part, per-voice internal synthesizer patches in a dedicated editor, with sine,
  triangle, saw, and square oscillators, a graphical ADSR amplitude envelope, and a delayed pitch
  LFO. Each patch also has a resonant synth filter with an independent ADSR envelope and separate
  velocity-to-amplitude and velocity-to-filter modulation. Give each patch its own gain, filter,
  compressor, delay, and reverb chain; save named patches globally and reuse them in any score.
- Run opt-in compatibility validation for every installed Audio Unit instrument with
  `make test-plugins`; results are written to `build/tests/audio-unit-compatibility.json`.

The native macOS plug-in format is currently sufficient for the supported macOS host. VST3 is
therefore not enabled by default; it requires the Steinberg VST3 SDK and a separate host adapter
before ScoreMaker targets systems or vendors that do not supply Audio Units.
- Preserve independent note voices and explicit measure boundaries, including pickup measures and per-measure time signatures.
- Reflow measures across systems and printed pages according to notation density, with collision-aware onset spacing, displaced seconds in chords, and staggered accidental columns.
- Import, export, preserve, and render major/minor key signatures, including mid-system changes,
  cancellation naturals, contextual measure accidentals, ties, tuplets, dynamics, common
  articulations, and repeat barlines.

## Screenshots

### macOS
<img width="2303" height="1397" alt="msuic2" src="https://github.com/user-attachments/assets/57c758d3-eb8c-46e6-9bb5-527605c512ad" />

### GNUstep
<img width="2178" height="1029" alt="Untitled" src="https://github.com/user-attachments/assets/27c01b26-ff4f-47bb-987e-f0cce37d01bf" />

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
The bundled `examples/key-signature-change.score` is a short engraving example that changes
from G major to E-flat major, demonstrating an opening signature, cancellation naturals, and a
mid-score flat signature.
The bundled `examples/time-rotor-study.score` is an original CC0 electronic science-fiction title study in 6/8. It is intentionally not an arrangement of any television theme.
The bundled `examples/mozart-requiem/` collection contains fourteen independently openable complete multi-track scores, one for each commonly separated movement of Mozart's Requiem, K. 626.
The bundled `examples/brandenburg-concertos/` collection contains all six of J. S. Bach's Brandenburg Concertos, BWV 1046–1051, as eighteen independently openable movement scores.

Use the inspector on the right side of the sheet to add pitched notes, add freeform score notes, change the tempo in BPM, or change the time signature.
The inspector scrolls vertically when the window is not tall enough to show its complete palette and score-notes editor.

Choose **Edit Source...** in the inspector or **Score > Edit Score Source...** to open the source
editor belonging to that score. Changes remain isolated in the editor until **Apply** successfully
parses them; **Regenerate from Score** discards the editor buffer and recreates it from the visual
score. Applying source is undoable as one document edit. Placing the source-editor caret inside a
note statement selects that note in the rendered score and scrolls it into view. During playback,
the editor highlights and follows the source statements for all currently sounding notes; this
temporary highlight does not move the insertion caret or modify the source. Highlight colors use
the same per-voice palette as the rendered score, velocity meters, and virtual keyboard.
If **Apply** encounters a ranged syntax error, the editor reports its line and column, underlines
the offending source in red, and scrolls the diagnostic into view.

Choose a connected device under **MIDI Input** for live entry. With recording stopped, played notes are entered at the inspector's Start position and simultaneous held notes form a chord. Choose a Grid value and press **Record** for a one-measure count-in followed by real-time recording; press **Stop** to quantize and insert the captured performance. MIDI velocity and sustain-pedal note lengths are preserved.
The input menu updates when MIDI devices are connected or removed. **Selected Part** routing sends all channels to the inspector's current part; **MIDI Channel → Part** maps channel 1 to Part 1, channel 2 to Part 2, and so on. Use **Edit → Undo/Redo** or Command-Z/Command-Shift-Z to reverse and restore edits; one recording take is one undo operation.

Choose `Score > Play` or the Play button in the inspector to hear the current score. ScoreMaker sends the generated MIDI data directly to AVFoundation, using the platform AVFoundation implementation on macOS or GNUstep.

On macOS, select a part in the inspector and choose **Score > Part MIDI Output...** to send that
part to the built-in synthesizer or a connected CoreMIDI destination. Assignments are saved in
ScoreMaker project files. Multiple physical destinations can play together; if an assigned device
is disconnected, that part falls back to the built-in synthesizer. GNUstep builds preserve these
project assignments but continue to use their configured system MIDI player.

Choose **Score > Internal Synth Patch Editor...** to design the internal sound for the selected part and notation voice. Each voice explicitly selects a named patch, and each patch carries its own oscillator, amplitude envelope, pitch LFO, resonant filter, independent filter envelope, velocity modulation, and effects. Use **Filter...** for cutoff, resonance, filter ADSR, envelope amount, and velocity routing. Editing a named patch creates a custom voice patch until it is saved under a name. Voice-to-patch assignments are preserved in ScoreMaker project files; named patches saved with **Save Patch...** are stored in user preferences and can be selected in any score. The separate **Score > Effects...** chain remains the shared master bus.

Use **Browse Patches...** to explore the 24 bundled factory sounds and saved user sounds by Lead, Bass, Pad, Pluck, Keys, Effects, or Uncategorized. The browser shows each patch's description, auditions a short velocity-sensitive phrase without changing the score, and assigns the chosen patch to the editor's selected score voice only when **Use Patch** is pressed. Factory patches are always available; saving under the same name creates a user override without modifying the built-in library.

The inspector's **Instrument** menu provides the fast sound-selection path. Its adjacent **V1–V16** selector chooses the notation voice, and the grouped menu offers General MIDI programs, complete ScoreMaker Synth patches, and Audio Unit selection. Choosing a synth entry assigns its oscillator, envelopes, modulation, and effects together; the patch editor remains the detailed sound-design interface.

To rehearse or inspect a passage repeatedly, select its first note, Shift-click its last note, enable **Score > Loop Selection**, and start playback. The inclusive loop range is tinted on the score and may span systems.

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

ScoreMaker maps common MusicKit-style instrument declarations to General MIDI programs for playback. Its internal patch editor supplies its own oscillator, envelope, and LFO model, but does not emulate arbitrary MusicKit synthesis engines, wave tables, or source DSP patches. When saving `.score` files, it writes the renderable note data and track program mappings from the current document rather than preserving every original source statement or comment; internal patch settings are stored in ScoreMaker project files.

ScoreMaker keeps `.score` note statements compatible with MusicKit-style readers. Voice assignments and explicit measure structure are stored in an additional `ScoreMaker Structure V2` JSON metadata comment; older readers can ignore that comment and continue reading pitches, timing, parts, and programs. Files without V2 structure metadata open as voice 1 with measures derived from their time signature.

MIDI parsing supports Standard MIDI files with tick-based timing. SMPTE time-division MIDI files are not supported.

## Clean

Remove generated build artifacts with:

```sh
make clean
```
