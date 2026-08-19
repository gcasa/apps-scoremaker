# ScoreMaker User Manual

ScoreMaker is a macOS application for writing, editing, playing, recording, and publishing musical scores. It can open MIDI, MusicXML, MusicKit scorefiles, and native ScoreMaker projects. This manual describes the macOS version; the GNUstep port is experimental and does not provide every macOS audio feature.

## 1. Getting started

### Create a score

1. Choose **File > New** (`Command-N`).
2. To begin with a standard ensemble, choose **Score > Templates**, then select **Piano**, **Choir (SATB)**, **String Quartet**, **Concert Band**, or **Orchestra**.
3. Set the tempo and time signature in the inspector on the right.
4. Add notes with the inspector, the notation palette, the computer keyboard, the on-screen piano, or a MIDI controller.
5. Save the score as a `.scoremaker` project to retain the complete ScoreMaker document model.

### Open an existing score

Choose **File > Open…** (`Command-O`) and select one of these formats:

- `.scoremaker` — native ScoreMaker project
- `.score` — MusicKit-style text scorefile
- `.mid` or `.midi` — Standard MIDI file
- `.musicxml` or `.xml` — uncompressed MusicXML

Recently opened files appear under **File > Open Recent**. The repository's `examples` directory contains scores suitable for learning and testing.

> **Format advice:** Use `.scoremaker` while actively editing. Use MIDI, MusicXML, or `.score` when exchanging material with other software. Interchange formats may not represent every ScoreMaker feature.

## 2. The score window

The main window has three working areas:

- **Score sheet:** the engraved score. Click notes to select them, drag notes to edit them, or drop items from the palette.
- **Inspector:** transport, score settings, note entry, parts, instruments, MIDI input, notation details, palette items, and score notes. Scroll the inspector to reach controls below the visible area.
- **Playback monitor:** an 88-key piano and per-voice velocity meters. Middle C is labeled C4. Click a piano key to audition or enter a pitch.

Use **View** to select 50%, 75%, 100%, 125%, 150%, or 200% zoom. **Fit Width** (`Command-0`) fits the score horizontally; **Fit Page** (`Command-9`) shows a complete page.

## 3. Entering and editing music

### Add a note or rest with the inspector

1. In **Add Note**, choose **Note** or **Rest**.
2. Choose a rhythmic value from whole through 1/32.
3. For a note, enter a pitch such as `C4`, `F#4`, or `Bb3`.
4. Enter the start position in beats and choose the destination part.
5. Click **Add**.

The duration field follows the selected rhythmic value. Click **+** beside the Part menu to add a part.

### Enter pitches from the computer keyboard

Click the score so it has keyboard focus, then type `A` through `G`. A new note is placed after the selected note, using a nearby octave. With no selection, entry begins at the end of the score with a quarter-note duration.

### Use the notation palette

Drag a note, rest, accidental, slur, tie, tuplet, dynamic, articulation, grace/cue mark, ornament, tremolo, hairpin, pedal mark, or octave line from the inspector's **Palette** onto the score. Available note and rest values range from whole to 1/32.

### Select and edit notes directly

- Click a note to select it.
- Shift-click another note to select the inclusive range between them.
- Drag a note vertically to change pitch, horizontally to change its start time, or onto another displayed part. Time snaps to a sixteenth-note grid.
- Press Up or Down Arrow to move selected notes by one semitone.
- Press Left or Right Arrow to move selected notes by one sixteenth note.
- Press Delete or Backspace to remove the selection.
- Use **Edit > Cut**, **Copy**, and **Paste** (`Command-X`, `Command-C`, and `Command-V`) for notes and ranges.
- Choose **Score > Transpose Up Semitone**, **Transpose Down Semitone**, or **Quantize Selection** for bulk edits.

Every document edit supports **Undo** (`Command-Z`) and **Redo** (`Command-Shift-Z`).

### Edit notation details

Select a note or measure, then use **Selected Note / Measure** in the inspector. Controls include:

- major and minor key signatures
- repeat starts and endings
- tie starts and endings
- tuplets, dynamics, and articulations
- lyrics, ornaments, tremolos, grace notes, and cue notes
- rehearsal marks, volta-ending text, and expression text
- automatic, upper, or lower cross-staff placement
- forced system and page starts

Some notation can also be applied by dragging its palette item onto the score.

### Parts and voices

Choose the active part in the inspector. **Separate Part Staves** displays parts independently. Use **Score > Voices to Parts** to turn the selected part's notation voices into separate parts, or **Score > Parts to Voices** to combine parts as voices. Both operations can be undone.

For complete part management, open **Score > Routing Matrix…**. See section 7.

## 4. Playback and navigation

Use the transport buttons at the top of the inspector or the **Score** menu:

- **Play** (`Space`) starts playback.
- **Pause/Resume** temporarily suspends or continues playback.
- **Stop** (`Command-.`) ends playback.
- **Rewind** (`Command-[`) returns to the beginning.
- **Play from Selection** (`Command-Return`) starts at the selected note.
- Double-click a note to begin playback at that position.
- **Go to Measure…** (`Command-G`) jumps directly to a measure.

During playback, sounding notes are highlighted on the score, on the virtual piano, in the velocity meters, and—when open—in the score source editor.

### Use the metronome

Choose **Score > Metronome** to start or stop the practice metronome. It follows the score's current tempo and time-signature numerator. The playback monitor shows an animated pendulum and beat counter; the downbeat is highlighted in red. Changing the tempo while the metronome is running updates both its click and animation. The recording count-in uses the same visual indicator automatically.

### Loop a passage

1. Click the first note of the passage.
2. Shift-click the last note.
3. Enable **Score > Loop Selection**.
4. Start playback.

The highlighted range is inclusive and can cross systems. Disable **Loop Selection** to return to normal playback.

## 5. MIDI input and recording

MIDI input is supported through CoreMIDI on macOS.

### Audition and step entry

1. Choose a connected controller from **MIDI Input** in the inspector.
2. Play the controller to audition notes without changing the score.
3. Click the on-screen piano or use the configured input for note entry where applicable.
4. Use the octave menu to transpose incoming notes by up to four octaves in software.

**Shade Keys** shows the selected controller's detected range on the virtual keyboard. The device list updates when hardware is connected or removed.

### Record a performance

1. Select the destination part.
2. Choose a MIDI input device.
3. Set the quantization **Grid** to 1/8, 1/16, or 1/32.
4. Set **Input Routing**:
   - **Selected Part** sends every MIDI channel to the active part.
   - **MIDI Channel → Part** maps channel 1 to Part 1, channel 2 to Part 2, and so on.
5. Click **Record**. ScoreMaker provides a one-measure count-in.
6. Perform, then click **Stop**.

The completed take is quantized to the chosen grid and inserted as one undoable action. Velocity, chord timing, sustain-pedal behavior, and note lengths are preserved. MIDI input changes the score only while recording is active.

## 6. Instruments and sound design

### Choose a sound quickly

In the inspector, select the notation voice with **V1–V16**, then choose an item from **Instrument**:

- a General MIDI program
- a complete ScoreMaker Synth patch
- **Choose Audio Unit…**

The voice selector matters: different voices in the same part can use different internal patches.

### Edit an internal synthesizer patch

Choose **Score > Internal Synth Patch Editor…**. The editor controls the selected part and voice. You can adjust:

- sine, triangle, saw, or square oscillator
- amplitude ADSR envelope
- delayed pitch LFO
- resonant filter, filter ADSR, and envelope amount
- velocity-to-amplitude and velocity-to-filter response
- patch gain, filter, compressor, delay, and reverb

Use **Preview** to audition the patch, **Reset Patch** to restore its starting state, and **Save Patch…** to store a named user patch. **Browse Patches…** filters factory and user patches by category; **Audition Phrase** previews without changing the score, while **Use Patch** assigns the selection to the current voice.

### Audio Units

Choose **Score > Choose Audio Unit Instrument…** to use an installed AUv2 or AUv3 music device. Related commands let you open the vendor or generic editor, manage presets, relink a missing unit, choose a substitute, or view the compatibility report. Audio Units are hosted out of process for isolation.

If a saved unit is unavailable, ScoreMaker retains its identity so that it can be relinked later. Availability and compatibility depend on the installed plug-in.

### Effects and real-time DSP

**Score > Effects…** edits the shared effects chain. **Use Real-Time DSP** enables ScoreMaker's real-time processing path. Part and patch effects are preserved in native projects and are also used for supported offline rendering paths.

## 7. Parts, mixing, and MIDI output routing

Open **Score > Routing Matrix…** to manage the complete ensemble in one window. You can:

- rename, reorder, duplicate, and remove parts
- group parts and show or hide their staves
- mute, solo, set volume, and set pan
- choose a General MIDI program
- route each part to the built-in synthesizer or a physical CoreMIDI output
- select a MIDI channel and inspect connection state
- choose a fallback when a saved device is unavailable

Select multiple rows to apply a device in bulk, assign sequential channels, or reset routes. Duplicate device/channel assignments are flagged. Missing hardware assignments remain saved and can reconnect when the device returns; fallback choices include the built-in synth, muting the part, or another MIDI device.

## 8. Editing MusicKit score source

Choose **Score > Edit Score Source…** or click **Edit Source…** in the inspector. Each score has its own syntax-highlighted source window.

- **Apply** parses the editor buffer and replaces the visual score only if parsing succeeds. A successful apply is one undoable edit.
- **Regenerate from Score** discards the editor buffer and rebuilds it from the current visual score.
- Moving the caret into a note statement selects and reveals the corresponding engraved note.
- Playback highlights all currently sounding source statements without moving the caret.
- A ranged syntax error is reported with line and column information, underlined in red, and scrolled into view.

Edits in this window are isolated until **Apply** succeeds. Comments and compatible source statements are preserved when an authoritative `.score` source is saved.

## 9. Page layout, printing, and publication

### Page layout

Choose **Score > Page Layout…** to set paper size, margins, staff scale, system spacing, running headers, footers, and page numbers. Use **System** or **Page** in the selected-measure controls to override automatic system and page starts.

Use **Score > Edit Title…** to change the title shown on the score independently of the filename. **Choose Title Font…** opens the macOS font panel for the title.

### Print or export PDF

- Choose **File > Print…** (`Command-P`) to use the standard macOS print panel.
- Choose **Score > Export PDF…** to export either the full conductor score or the current part. A part is reflowed independently rather than cropped from the full score.

### Render audio

Choose **Score > Render Internal DSP Audio…**, then select **Full Mix** or **Current Part Stem**. Save the result as WAV, AIFF, or CAF. This command renders through ScoreMaker's internal DSP path; external hardware routes do not become recorded audio automatically.

## 10. Saving and exchanging files

Choose **File > Save** (`Command-S`) to update the current file or **File > Save As…** (`Command-Shift-S`) to choose a name and format.

| Format | Extension | Best use |
| --- | --- | --- |
| ScoreMaker Project | `.scoremaker` | Complete editable project, including ScoreMaker-specific structure and settings |
| MusicKit Scorefile | `.score` | Text-based MusicKit workflow and source editing |
| Standard MIDI | `.mid`, `.midi` | Playback and exchange of performance-oriented note data |
| MusicXML | `.musicxml`, `.xml` | Exchange of conventional notation with scoring applications |

Before exchanging a file, use **Score > Export Compatibility Report…** and select the target format. The report helps identify features that may be changed or omitted. Saving to a different extension selects the corresponding exporter.

ScoreMaker uses the macOS document system for autosave-in-place and recovery. It is still good practice to save a native `.scoremaker` copy before exporting to an interchange format.

## 11. Keyboard shortcut reference

| Action | Shortcut |
| --- | --- |
| New | `Command-N` |
| Open | `Command-O` |
| Save | `Command-S` |
| Save As | `Command-Shift-S` |
| Print | `Command-P` |
| Undo / Redo | `Command-Z` / `Command-Shift-Z` |
| Cut / Copy / Paste | `Command-X` / `Command-C` / `Command-V` |
| Play | `Space` |
| Play from Selection | `Command-Return` |
| Stop | `Command-.` |
| Rewind | `Command-[` |
| Go to Measure | `Command-G` |
| Fit Width / Fit Page | `Command-0` / `Command-9` |
| Move selected note(s) by semitone | Up / Down Arrow |
| Move selected note(s) by sixteenth note | Left / Right Arrow |
| Delete selected note(s) | Delete or Backspace |
| Enter pitch near selection | `A`–`G` |

## 12. Troubleshooting

### There is no sound

- Confirm that the part is not muted and that no unintended solo is active.
- Check the part's output in **Routing Matrix…**.
- If an external MIDI device is missing, choose a working fallback or the built-in synthesizer.
- If using an Audio Unit, open its editor or compatibility report and relink it if necessary.
- Confirm that the selected part and voice have a valid instrument or patch.

### A MIDI controller does not appear

- Reconnect or power-cycle the device; the menu should update after a CoreMIDI device change.
- Confirm that the controller is visible to macOS Audio MIDI Setup.
- Reopen the document if the device list does not refresh.

### Recording does not start

- Select a real device under **MIDI Input**; Record is unavailable while **None (Step Entry Off)** is selected.
- Confirm the desired part, routing mode, and grid before pressing Record.

### A score looks different after import or export

Interchange formats do not carry every ScoreMaker-specific feature. Review **Export Compatibility Report…**, retain a `.scoremaker` master, and use MusicXML for notation-oriented exchange or MIDI for performance-oriented exchange.

### Score source will not apply

Read the error shown in the source editor. ScoreMaker reports the line and column and marks the failing range. Correct the marked statement and click **Apply** again; the visible score remains unchanged after a failed parse.

### The inspector controls are missing

The inspector is vertically scrollable. Scroll within the right side of the score window to reach notation, palette, and score-note controls.

## 13. Platform notes and limits

- macOS is the release-supported platform. GNUstep support is experimental and requires a separately supplied AVFoundation-compatible framework.
- MIDI files using SMPTE time division are not supported.
- MusicXML import expects uncompressed `.musicxml` or `.xml`, not compressed `.mxl`.
- ScoreMaker maps common MusicKit instrument declarations to available General MIDI sounds, but it does not execute arbitrary Objective-C MusicKit SynthPatch classes or DSP56001 programs.
- Very large or deeply generated scorefiles are subject to parser safety limits. Include cycles are errors.
