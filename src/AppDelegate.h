#import <AppKit/AppKit.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
{
    NSMenu *_recentDocumentsMenu;
    BOOL _receivedOpenRequest;
}
@end
