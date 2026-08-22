/*
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This file is part of ScoreMaker.
 *
 * ScoreMaker is free software: you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or (at
 * your option) any later version.
 *
 * ScoreMaker is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
 * License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with ScoreMaker.  If not, see <https://www.gnu.org/licenses/>.
 */

#import <AppKit/AppKit.h>

/** Posted with the ScoreMakerDocument as its object after playback reaches the score's end. */
FOUNDATION_EXPORT NSString * const ScoreMakerDocumentPlaybackDidFinishNotification;
#import "ScoreView.h"
#import "PlaybackMonitorView.h"
#import "MIDIInputManager.h"
#import "RealtimeDSP.h"
#if defined(__APPLE__)
#import <AudioToolbox/AudioToolbox.h>
#import <CoreMIDI/CoreMIDI.h>
#endif

/**
 * Owns a ScoreDocument and coordinates its windows, inspector, playback,
 * recording, routing, synthesis, source editing, printing, and persistence.
 */
@interface ScoreMakerDocument : NSDocument <NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate>
{
  NSWindow *_documentWindow;
  NSWindowController *_windowController;
  ScoreDocument *_scoreDocument;
  NSScrollView *_scrollView;
  ScoreView *_scoreView;
  NSScrollView *_inspectorScrollView;
  NSView *_inspectorView;
  PlaybackMonitorView *_playbackMonitorView;
  NSTextField *_tempoField;
  NSSlider *_tempoSlider;
  NSTextField *_timeNumeratorField;
  NSTextField *_timeDenominatorField;
  NSTextField *_notePitchField;
  NSTextField *_noteStartField;
  NSTextField *_noteDurationField;
  NSPopUpButton *_noteTypePopUp;
  NSPopUpButton *_noteValuePopUp;
  NSPopUpButton *_partPopUp;
  NSPopUpButton *_instrumentPopUp;
  NSPopUpButton *_instrumentVoicePopUp;
  NSButton *_addPartButton;
  NSButton *_separatePartsButton;
  NSButton *_addNoteButton;
  NSPopUpButton *_keySignaturePopUp;
  NSButton *_transposeScoreButton;
  NSButton *_repeatStartButton;
  NSButton *_repeatEndButton;
  NSButton *_tieStartButton;
  NSButton *_tieEndButton;
  NSPopUpButton *_tupletPopUp;
  NSPopUpButton *_dynamicPopUp;
  NSPopUpButton *_articulationPopUp;
  NSTextField *_lyricField;
  NSPopUpButton *_ornamentPopUp;
  NSButton *_graceButton;
  NSButton *_cueButton;
  NSPopUpButton *_tremoloPopUp;
  NSTextField *_rehearsalMarkField;
  NSTextField *_endingTextField;
  NSButton *_systemBreakButton;
  NSButton *_pageBreakButton;
  NSPopUpButton *_staffAssignmentPopUp;
  NSTextField *_directionTextField;
  NSButton *_playButton;
  NSButton *_pauseButton;
  NSButton *_stopButton;
  NSPopUpButton *_midiInputPopUp;
  NSPopUpButton *_midiQuantizePopUp;
  NSPopUpButton *_midiRoutingPopUp;
  NSButton *_recordButton;
  NSButton *_midiRangeShadeButton;
  NSPopUpButton *_midiOctavePopUp;
  NSTextView *_annotationTextView;
  NSWindow *_scoreSourceEditorWindow;
  NSTextView *_scoreSourceTextView;
  NSTextField *_scoreSourceStatusLabel;
  NSString *_scoreSourceText;
  BOOL _scoreSourceIsAuthoritative;
  BOOL _scoreSourceEditorDirty;
  BOOL _updatingScoreSourceEditor;
  BOOL _applyingScoreSource;
  NSMutableDictionary *_scoreSourceNoteRangeCache;
  NSArray *_scoreSourceRangeMappings;
  NSArray *_scoreSourcePlaybackRanges;
  NSString *_scoreSourcePlaybackSignature;
  NSValue *_scoreSourceErrorRange;
  NSMutableSet *_scoreSourceActivePlaybackNotes;
  NSUInteger _scoreSourcePlaybackNoteIndex;
  NSUInteger _scoreSourceLastPlaybackTick;
  NSSound *_playbackSound;
  id _midiPlayer;
  NSSound *_auditionSound;
  id _auditionPlayer;
  NSTimer *_auditionResetTimer;
  MIDIInputManager *_midiInputManager;
  NSMutableDictionary *_midiActiveNotes;
  NSMutableSet *_midiHeldStepNotes;
  NSMutableDictionary *_midiHeldStepScoreNotes;
  NSMutableSet *_midiSustainedNotes;
  NSMutableDictionary *_midiAuditionPitches;
  NSTimer *_midiMetronomeTimer;
  NSSound *_midiMetronomeSound;
  NSTimer *_practiceMetronomeTimer;
  NSSound *_practiceMetronomeSound;
  NSUInteger _practiceMetronomeBeat;
  BOOL _practiceMetronomeActive;
  NSTimeInterval _midiRecordStartTime;
  NSUInteger _midiRecordStartTick;
  NSUInteger _midiStepStartTick;
  NSUInteger _midiCountInBeatsRemaining;
  BOOL _midiRecording;
  BOOL _midiCountingIn;
  BOOL _midiSustainDown;
  BOOL _midiRecordedNotes;
  ScoreDocument *_undoBaseline;
  ScoreDocument *_midiRecordingUndoSnapshot;
  BOOL _restoringUndo;
  NSTimer *_playbackTimer;
  NSTimeInterval _playbackStartTime;
  NSTimeInterval _playbackPausedElapsed;
  NSTimeInterval _playbackMIDIOriginTime;
  BOOL _playbackPaused;
  BOOL _loopSelectionEnabled;
  BOOL _writtenPitch;
  BOOL _updatingInspector;
  ScoreRealtimeDSP *_realtimeDSP;
  BOOL _useRealtimeDSP;
  BOOL _playbackUsesRealtimeDSP;
  NSInteger _realtimeDSPPitch;
  NSInteger _realtimeDSPVoice;
  NSInteger _audioUnitPartTrack;
  NSWindow *_audioUnitEditorWindow;
  NSMutableDictionary *_audioUnitParameterAddresses;
  NSWindow *_patchEditorWindow;
  NSPopUpButton *_patchWaveformPopUp;
  NSPopUpButton *_patchVoicePopUp;
  NSPopUpButton *_patchPresetPopUp;
  NSMutableDictionary *_patchControls;
  NSMutableDictionary *_patchValueLabels;
  NSMutableDictionary *_patchFilterValues;
  NSView *_patchEnvelopeView;
  BOOL _applyingNamedPatch;
  NSWindow *_patchBrowserWindow;
  NSTableView *_patchBrowserTable;
  NSPopUpButton *_patchBrowserCategoryPopUp;
  NSArray *_patchBrowserRows;
  NSWindow *_routingMatrixWindow;
  NSView *_routingMatrixRowsView;
  NSTextField *_routingMatrixSummaryLabel;
  NSMutableIndexSet *_routingMatrixSelection;
  NSPopUpButton *_routingBulkDevicePopUp;
#if defined(__APPLE__)
  NSMutableArray *_externalMIDIPlaybacks;
  MusicTimeStamp _externalPlaybackTime;
#endif
}
/** Returns the primary document window. */
- (NSWindow *)window;
/** Sets the primary document window. */
- (void)setWindow:(NSWindow *)window;
/** Returns the controller that owns the primary document window. */
- (NSWindowController *)windowController;
/** Sets the controller that owns the primary document window. */
- (void)setWindowController:(NSWindowController *)windowController;
/** Returns the scroll view containing the score. */
- (NSScrollView *)scrollView;
/** Sets the scroll view containing the score. */
- (void)setScrollView:(NSScrollView *)scrollView;
/** Returns the document's rendered score view. */
- (ScoreView *)scoreView;
/** Sets the document's rendered score view. */
- (void)setScoreView:(ScoreView *)scoreView;
/** Returns the editable score model. */
- (ScoreDocument *)scoreDocument;
/** Replaces the editable score model and updates dependent controllers. */
- (void)setScoreDocument:(ScoreDocument *)document;
/** Returns the inspector content view. */
- (NSView *)inspectorView;
/** Sets the inspector content view. */
- (void)setInspectorView:(NSView *)inspectorView;
/** Copies inspector metadata into the model and optionally marks a document edit. */
- (void)syncInspectorMetadataMarkingChange:(BOOL)markChange;
/** Handles an inspector edit to title, composer, meter, or score notes. */
- (void)scoreMetadataDidChange:(id)sender;
/** Applies the tempo slider's value to the document. */
- (void)tempoSliderDidChange:(id)sender;
/** Inserts a note using the current inspector values. */
- (void)addNote:(id)sender;
/** Splits the selected part's notation voices into independent parts. */
- (void)convertVoicesToParts:(id)sender;
/** Combines all score parts as independent voices in one part. */
- (void)convertPartsToVoices:(id)sender;
/** Replaces the current blank score with a standard ensemble template. */
- (void)applyScoreTemplate:(id)sender;
/** Transposes the current note or Shift-click range by the sender's tag. */
- (void)transposeSelection:(id)sender;
/** Prompts for a destination key and transposes every note and measure key signature. */
- (void)transposeScoreToKey:(id)sender;
/** Snaps selected note starts and durations to the inspector's note value. */
- (void)quantizeSelection:(id)sender;
/** Stops every active playback engine without interpreting a sender. */
- (void)stopCurrentPlayback;
/** Closes auxiliary windows and playback resources before application shutdown. */
- (void)prepareForApplicationTermination;
/** Stops playback and restores the transport to the beginning. */
- (void)stopPlayback:(id)sender;
/** Pauses playback while retaining the resume position. */
- (void)pausePlayback:(id)sender;
/** Starts or resumes score playback using current routing. */
- (void)playScore:(id)sender;
/** Starts playback at the selected note, or the beginning when nothing is selected. */
- (void)playFromSelection:(id)sender;
/** Stops playback and returns the score view to the beginning. */
- (void)rewindScore:(id)sender;
/** Prompts for a measure number and reveals it. */
- (void)goToMeasure:(id)sender;
/** Applies a zoom percentage from the sender tag. */
- (void)setScoreZoom:(id)sender;
/** Fits the score page width to the viewport. */
- (void)fitScoreWidth:(id)sender;
/** Fits an entire score page to the viewport. */
- (void)fitScorePage:(id)sender;
/** Enables or disables looping over the ScoreView selection. */
- (void)toggleLoopSelection:(id)sender;
/** Toggles transposing parts between written and concert pitch. */
- (void)toggleWrittenPitch:(id)sender;
/** Starts or stops the audible, animated practice metronome. */
- (void)toggleMetronome:(id)sender;
/** Presents the standard print workflow for the current score. */
- (void)printDocument:(id)sender;
/** Presents publication settings for screen, print, and PDF output. */
- (void)editPageLayout:(id)sender;
/** Exports the full score or selected part as a vector PDF. */
- (void)exportPDF:(id)sender;
/** Presents format-specific interchange and portability diagnostics. */
- (void)showExportCompatibilityReport:(id)sender;
/** Presents an editor for the score title. */
- (void)editScoreTitle:(id)sender;
/** Presents the font panel for the score title. */
- (void)chooseTitleFont:(id)sender;
/** Applies the font manager's current title-font conversion. */
- (void)changeFont:(id)sender;
/** Opens the persistent per-part MIDI routing matrix. */
- (void)chooseMIDIOutput:(id)sender;
/** Imports a Cakewalk .ins file and associates its patch names with a MIDI output. */
- (void)importMIDIInstrumentDefinition:(id)sender;
/** Enables or disables the real-time DSP playback engine. */
- (void)toggleRealtimeDSP:(id)sender;
/** Presents and assigns an installed Audio Unit instrument. */
- (void)chooseAudioUnitInstrument:(id)sender;
/** Opens the per-part, per-voice internal synthesizer patch editor. */
- (void)showInternalSynthPatchEditor:(id)sender;
/** Opens the active Audio Unit's vendor or generic editor. */
- (void)showAudioUnitEditor:(id)sender;
/** Presents user-preset load, save, and removal controls. */
- (void)manageAudioUnitPresets:(id)sender;
/** Presents compatible replacements for a missing Audio Unit. */
- (void)relinkAudioUnitInstrument:(id)sender;
/** Presents persisted Audio Unit validation results and blacklist controls. */
- (void)showAudioUnitCompatibilityReport:(id)sender;
/** Presents the shared master effects-chain editor. */
- (void)editEffects:(id)sender;
/** Presents options and renders the score to an audio file. */
- (void)renderOfflineAudio:(id)sender;
/** Opens the document's syntax-highlighted score-source editor. */
- (void)showScoreSourceEditor:(id)sender;
/** Parses and atomically applies the current source-editor contents. */
- (void)applyScoreSource:(id)sender;
/** Replaces unapplied source edits with source generated from the score model. */
- (void)revertScoreSource:(id)sender;
@end
