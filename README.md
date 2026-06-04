# ScoreMaker

ScoreMaker is a small Objective-C AppKit score viewer for macOS and GNUstep. It opens Standard MIDI files and MusicKit-style `.score` scorefiles, renders their pitched notes on simple treble and bass staves, and can save the current score back out as a `.score` file.

The renderer is intentionally lightweight. It focuses on extracting timing, pitch, tempo, and time-signature data well enough to inspect a score visually; it is not a full notation editor or MusicKit synthesis environment.

## Features

- Open `.mid` and `.midi` Standard MIDI files.
- Open MusicKit text scorefiles with the `.score` extension.
- Save the currently loaded score as a MusicKit-style `.score` file.
- Render notes across treble and bass staves with measure lines.
- Read MIDI tempo and time-signature metadata when available.
- Add pitched notes and edit score notes, tempo, and time signature from the inspector next to the sheet.
- Support common MusicKit scorefile timing, variable, `freq`, `keyNum`, `noteOn`, `noteOff`, `noteUpdate`, and duration-note patterns.

## Build

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

Use the inspector on the right side of the sheet to add pitched notes, add freeform score notes, change the tempo in BPM, or change the time signature.

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
- `src/ScoreView.*`: AppKit score rendering.
- `Info.plist`: macOS app metadata and document type declarations.
- `Makefile`: macOS and GNUstep build targets.

## Limitations

ScoreMaker ignores MusicKit synthesis parameters such as instruments, envelopes, wave tables, and DSP patch settings. When saving `.score` files, it writes the renderable note data from the current document rather than preserving every original source statement or comment.

MIDI parsing supports Standard MIDI files with tick-based timing. SMPTE time-division MIDI files are not supported.

## Clean

Remove generated build artifacts with:

```sh
make clean
```
