#import <Foundation/Foundation.h>

@interface MIDIInputManager : NSObject
{
@public
    id _target;
    SEL _action;
    SEL _changeAction;
#if defined(__APPLE__)
    unsigned int _client;
    unsigned int _inputPort;
    unsigned int _source;
    unsigned char _runningStatus;
#endif
}
- (void)setTarget:(id)target;
- (void)setAction:(SEL)action;
- (void)setChangeAction:(SEL)action;
- (NSArray *)availableSources;
- (BOOL)connectToSource:(unsigned int)source;
- (void)disconnect;
@end
