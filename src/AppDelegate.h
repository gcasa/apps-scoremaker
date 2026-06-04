#import <AppKit/AppKit.h>
#import "ScoreView.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
    NSWindow *_window;
    NSScrollView *_scrollView;
    ScoreView *_scoreView;
    NSString *_currentPath;
}
@property(nonatomic, retain) NSWindow *window;
@property(nonatomic, retain) NSScrollView *scrollView;
@property(nonatomic, retain) ScoreView *scoreView;
@property(nonatomic, retain) NSString *currentPath;
- (void)openDocument:(id)sender;
- (void)saveDocumentAs:(id)sender;
- (void)openScoreAtPath:(NSString *)path;
@end
