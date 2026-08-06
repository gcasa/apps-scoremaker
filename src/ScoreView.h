#import <AppKit/AppKit.h>
#import "ScoreModel.h"
#import "EngravingLayout.h"

extern NSString * const ScoreViewDidEditScoreNotification;
extern NSString * const ScoreViewSelectionDidChangeNotification;
extern NSString * const ScorePalettePasteboardType;

@interface ScoreView : NSView
{
    ScoreDocument *_document;
    ScoreNote *_selectedNote;
    NSUInteger _playbackTick;
    BOOL _showPlayback;
    ScoreEngravingLayout *_engravingLayout;
    BOOL _separateParts;
}
- (ScoreDocument *)document;
- (void)setDocument:(ScoreDocument *)document;
- (void)reloadDocument;
- (ScoreNote *)selectedNote;
- (void)setPlaybackTick:(NSUInteger)tick;
- (void)clearPlayback;
- (void)scrollPlaybackTickToVisible:(NSUInteger)tick;
- (NSSize)printedPageContentSize;
- (BOOL)separateParts;
- (void)setSeparateParts:(BOOL)separate;
- (BOOL)insertPaletteItem:(NSString *)item atPoint:(NSPoint)point pitch:(NSInteger)pitch durationTicks:(NSUInteger)durationTicks track:(NSInteger)track;
@end
