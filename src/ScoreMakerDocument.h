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
    NSButton *_addNoteButton;
    NSButton *_playButton;
    NSButton *_pauseButton;
    NSButton *_stopButton;
    NSPopUpButton *_midiInputPopUp;
    NSPopUpButton *_midiQuantizePopUp;
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
