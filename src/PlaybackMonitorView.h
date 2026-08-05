#import <AppKit/AppKit.h>
#import "ScoreModel.h"

@interface PlaybackMonitorView : NSView
{
    ScoreDocument *_document;
    NSUInteger _playbackTick;
    BOOL _showPlayback;
    NSInteger _inputPitch;
    id _target;
    SEL _action;
}
- (void)setDocument:(ScoreDocument *)document;
- (void)setPlaybackTick:(NSUInteger)tick;
- (void)clearPlayback;
- (void)setTarget:(id)target;
- (void)setAction:(SEL)action;
- (NSInteger)inputPitch;
- (void)setInputPitch:(NSInteger)pitch;
- (void)resetInputPitch;
@end
