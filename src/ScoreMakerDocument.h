#import <AppKit/AppKit.h>
#import "ScoreView.h"

@interface ScoreMakerDocument : NSDocument <NSTextFieldDelegate>
{
    NSWindow *_window;
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
    NSTextField *_noteTrackField;
    NSButton *_addNoteButton;
    NSTextView *_annotationTextView;
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
@end
