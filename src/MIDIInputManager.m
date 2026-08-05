#import "MIDIInputManager.h"

#if defined(__APPLE__)
#import <CoreMIDI/CoreMIDI.h>

static NSString *MIDIInputEndpointName(MIDIEndpointRef endpoint)
{
    CFStringRef value = NULL;
    if (MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value) != noErr || !value)
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &value);
    if (!value) return @"MIDI Input";
    return [(NSString *)value autorelease];
}

static void MIDIInputRead(const MIDIPacketList *packets, void *readRefCon, void *sourceRefCon)
{
    (void)sourceRefCon;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    MIDIInputManager *manager = (MIDIInputManager *)readRefCon;
    const MIDIPacket *packet = &packets->packet[0];
    for (UInt32 packetIndex = 0; packetIndex < packets->numPackets; packetIndex++) {
        NSUInteger index = 0;
        while (index < packet->length) {
            unsigned char byte = packet->data[index++];
            unsigned char status = byte;
            if (byte & 0x80) {
                if (byte >= 0xf0) continue;
                manager->_runningStatus = byte;
            } else {
                status = manager->_runningStatus;
                index--;
            }
            if (!status) break;
            unsigned char type = status & 0xf0;
            NSUInteger dataLength = (type == 0xc0 || type == 0xd0) ? 1 : 2;
            if (index + dataLength > packet->length) break;
            unsigned char data1 = packet->data[index++];
            unsigned char data2 = dataLength == 2 ? packet->data[index++] : 0;
            if (type != 0x80 && type != 0x90 && type != 0xb0) continue;
            NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithUnsignedChar:type], @"type",
                [NSNumber numberWithUnsignedChar:(status & 0x0f)], @"channel",
                [NSNumber numberWithUnsignedChar:data1], @"data1",
                [NSNumber numberWithUnsignedChar:data2], @"data2",
                [NSNumber numberWithDouble:[NSDate timeIntervalSinceReferenceDate]], @"time", nil];
            if (manager->_action)
                [manager->_target performSelectorOnMainThread:manager->_action withObject:event waitUntilDone:NO];
        }
        packet = MIDIPacketNext(packet);
    }
    [pool drain];
}
#endif

@implementation MIDIInputManager
- (void)setTarget:(id)target { _target = target; }
- (void)setAction:(SEL)action { _action = action; }

- (NSArray *)availableSources
{
#if defined(__APPLE__)
    NSMutableArray *sources = [NSMutableArray array];
    ItemCount count = MIDIGetNumberOfSources();
    for (ItemCount index = 0; index < count; index++) {
        MIDIEndpointRef endpoint = MIDIGetSource(index);
        if (!endpoint) continue;
        [sources addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            MIDIInputEndpointName(endpoint), @"name",
            [NSNumber numberWithUnsignedInt:endpoint], @"endpoint", nil]];
    }
    return sources;
#else
    return [NSArray array];
#endif
}

- (BOOL)connectToSource:(unsigned int)source
{
#if defined(__APPLE__)
    [self disconnect];
    if (!source) return YES;
    MIDIClientRef client = 0;
    MIDIPortRef port = 0;
    if (MIDIClientCreate(CFSTR("ScoreMaker MIDI Input"), NULL, NULL, &client) != noErr) return NO;
    if (MIDIInputPortCreate(client, CFSTR("ScoreMaker Input Port"), MIDIInputRead, self, &port) != noErr) {
        MIDIClientDispose(client);
        return NO;
    }
    if (MIDIPortConnectSource(port, (MIDIEndpointRef)source, NULL) != noErr) {
        MIDIPortDispose(port); MIDIClientDispose(client); return NO;
    }
    _client = (unsigned int)client;
    _inputPort = (unsigned int)port;
    _source = source;
    _runningStatus = 0;
    return YES;
#else
    (void)source;
    return NO;
#endif
}

- (void)disconnect
{
#if defined(__APPLE__)
    if (_inputPort && _source) MIDIPortDisconnectSource((MIDIPortRef)_inputPort, (MIDIEndpointRef)_source);
    if (_inputPort) MIDIPortDispose((MIDIPortRef)_inputPort);
    if (_client) MIDIClientDispose((MIDIClientRef)_client);
    _client = 0; _inputPort = 0; _source = 0; _runningStatus = 0;
#endif
}

- (void)dealloc { [self disconnect]; [super dealloc]; }
@end
