#import <AppKit/AppKit.h>
#import "ScoreModel.h"

@interface PlaybackMonitorView : NSView
{
    ScoreDocument *_document;
    NSUInteger _playbackTick;
    BOOL _showPlayback;
}
- (void)setDocument:(ScoreDocument *)document;
- (void)setPlaybackTick:(NSUInteger)tick;
- (void)clearPlayback;
@end
