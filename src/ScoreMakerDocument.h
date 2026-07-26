#import <AppKit/AppKit.h>
#import "ScoreView.h"

@interface ScoreMakerDocument : NSDocument <NSTextFieldDelegate>
{
    NSWindow *_documentWindow;
    NSWindowController *_windowController;
    ScoreDocument *_scoreDocument;
    NSScrollView *_scrollView;
    ScoreView *_scoreView;
    NSView *_inspectorView;
    NSTextField *_tempoField;
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
    NSButton *_stopButton;
    NSTextView *_annotationTextView;
    NSSound *_playbackSound;
    id _midiPlayer;
    NSTask *_playbackTask;
    NSString *_playbackFilePath;
    NSTimer *_playbackTimer;
    NSTimeInterval _playbackStartTime;
    BOOL _updatingInspector;
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
- (void)addNote:(id)sender;
- (void)stopCurrentPlayback;
- (void)stopPlayback:(id)sender;
- (void)playScore:(id)sender;
- (void)printDocument:(id)sender;
@end
