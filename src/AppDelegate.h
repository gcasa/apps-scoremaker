#import <AppKit/AppKit.h>
#import "ScoreView.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
    NSWindow *_window;
    NSScrollView *_scrollView;
    ScoreView *_scoreView;
    NSString *_currentPath;
}
- (NSWindow *)window;
- (void)setWindow:(NSWindow *)window;
- (NSScrollView *)scrollView;
- (void)setScrollView:(NSScrollView *)scrollView;
- (ScoreView *)scoreView;
- (void)setScoreView:(ScoreView *)scoreView;
- (NSString *)currentPath;
- (void)setCurrentPath:(NSString *)currentPath;
- (void)openDocument:(id)sender;
- (void)saveDocumentAs:(id)sender;
- (void)openScoreAtPath:(NSString *)path;
@end
