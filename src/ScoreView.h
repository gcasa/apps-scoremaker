#import <AppKit/AppKit.h>
#import "ScoreModel.h"

extern NSString * const ScoreViewDidEditScoreNotification;
extern NSString * const ScorePalettePasteboardType;

@interface ScoreView : NSView
{
    ScoreDocument *_document;
    ScoreNote *_selectedNote;
}
- (ScoreDocument *)document;
- (void)setDocument:(ScoreDocument *)document;
- (void)reloadDocument;
- (ScoreNote *)selectedNote;
- (BOOL)insertPaletteItem:(NSString *)item atPoint:(NSPoint)point pitch:(NSInteger)pitch durationTicks:(NSUInteger)durationTicks track:(NSInteger)track;
@end
