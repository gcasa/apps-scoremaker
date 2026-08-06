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
    NSMutableDictionary *_liveNotes;
    NSInteger _selectedTrack;
    NSMutableSet *_pinnedTracks;
    BOOL _rackVisible;
}
- (void)setDocument:(ScoreDocument *)document;
- (void)setPlaybackTick:(NSUInteger)tick;
- (void)clearPlayback;
- (void)setTarget:(id)target;
- (void)setAction:(SEL)action;
- (NSInteger)inputPitch;
- (void)setInputPitch:(NSInteger)pitch;
- (void)resetInputPitch;
- (void)liveNoteOn:(NSInteger)pitch voice:(NSInteger)voice velocity:(NSUInteger)velocity;
- (void)liveNoteOff:(NSInteger)pitch;
- (void)clearLiveNotes;
- (void)setSelectedTrack:(NSInteger)track;
@end
