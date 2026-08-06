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
#import "ScoreView.h"
#import "PlaybackMonitorView.h"
#import "MIDIInputManager.h"
#if defined(__APPLE__)
#import <AudioToolbox/AudioToolbox.h>
#import <CoreMIDI/CoreMIDI.h>
#endif

@interface ScoreMakerDocument : NSDocument <NSTextFieldDelegate>
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
  NSButton *_addPartButton;
  NSButton *_separatePartsButton;
  NSButton *_addNoteButton;
  NSPopUpButton *_keySignaturePopUp;
  NSButton *_repeatStartButton;
  NSButton *_repeatEndButton;
  NSButton *_tieStartButton;
  NSButton *_tieEndButton;
  NSPopUpButton *_tupletPopUp;
  NSPopUpButton *_dynamicPopUp;
  NSPopUpButton *_articulationPopUp;
  NSButton *_playButton;
  NSButton *_pauseButton;
  NSButton *_stopButton;
  NSPopUpButton *_midiInputPopUp;
  NSPopUpButton *_midiQuantizePopUp;
  NSPopUpButton *_midiRoutingPopUp;
  NSButton *_recordButton;
  NSTextView *_annotationTextView;
  NSSound *_playbackSound;
  id _midiPlayer;
  NSSound *_auditionSound;
  id _auditionPlayer;
  NSTimer *_auditionResetTimer;
  MIDIInputManager *_midiInputManager;
  NSMutableDictionary *_midiActiveNotes;
  NSMutableSet *_midiHeldStepNotes;
  NSMutableSet *_midiSustainedNotes;
  NSTimer *_midiMetronomeTimer;
  NSSound *_midiMetronomeSound;
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
  BOOL _playbackPaused;
  BOOL _updatingInspector;
#if defined(__APPLE__)
  MIDIEndpointRef _midiOutputEndpoint;
  NSString *_midiOutputName;
  BOOL _useBuiltInMIDIOutput;
  MusicSequence _externalMusicSequence;
  MusicPlayer _externalMusicPlayer;
  MusicTimeStamp _externalPlaybackTime;
#endif
}
- (NSWindow *)window;
- (void)setWindow:(NSWindow *)window;
- (NSWindowController *)windowController;
- (void)setWindowController:(NSWindowController *)windowController;
- (NSScrollView *)scrollView;
- (void)setScrollView:(NSScrollView *)scrollView;
- (ScoreView *)scoreView;
- (void)setScoreView:(ScoreView *)scoreView;
- (ScoreDocument *)scoreDocument;
- (void)setScoreDocument:(ScoreDocument *)document;
- (NSView *)inspectorView;
- (void)setInspectorView:(NSView *)inspectorView;
- (void)syncInspectorMetadataMarkingChange:(BOOL)markChange;
- (void)scoreMetadataDidChange:(id)sender;
- (void)tempoSliderDidChange:(id)sender;
- (void)addNote:(id)sender;
- (void)stopCurrentPlayback;
- (void)stopPlayback:(id)sender;
- (void)pausePlayback:(id)sender;
- (void)playScore:(id)sender;
- (void)printDocument:(id)sender;
- (void)editScoreTitle:(id)sender;
- (void)chooseTitleFont:(id)sender;
- (void)changeFont:(id)sender;
- (void)chooseMIDIOutput:(id)sender;
@end
