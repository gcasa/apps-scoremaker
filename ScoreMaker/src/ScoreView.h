#import <AppKit/AppKit.h>
#import "ScoreModel.h"

@interface ScoreView : NSView
{
    ScoreDocument *_document;
}
@property(nonatomic, retain) ScoreDocument *document;
@end
