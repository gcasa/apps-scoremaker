#import <AppKit/AppKit.h>
#import "ScoreModel.h"

@interface ScoreView : NSView
{
    ScoreDocument *_document;
}
- (ScoreDocument *)document;
- (void)setDocument:(ScoreDocument *)document;
@end
