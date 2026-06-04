#import <AppKit/AppKit.h>
#import "ScoreView.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTextFieldDelegate>
{
    NSWindow *_window;
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
    NSString *_currentPath;
}
- (NSWindow *)window;
- (void)setWindow:(NSWindow *)window;
- (NSScrollView *)scrollView;
- (void)setScrollView:(NSScrollView *)scrollView;
- (ScoreView *)scoreView;
- (void)setScoreView:(ScoreView *)scoreView;
- (NSView *)inspectorView;
- (void)setInspectorView:(NSView *)inspectorView;
- (NSString *)currentPath;
- (void)setCurrentPath:(NSString *)currentPath;
- (void)openDocument:(id)sender;
- (void)saveDocumentAs:(id)sender;
- (void)openScoreAtPath:(NSString *)path;
- (void)scoreMetadataDidChange:(id)sender;
- (void)addNote:(id)sender;
@end
