/*
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This file is part of ScoreMaker.
 *
 * ScoreMaker is free software: you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or (at
 * your option) any later version.
 *
 * ScoreMaker is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
 * License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with ScoreMaker.  If not, see <https://www.gnu.org/licenses/>.
 */

#import "MIDIInputManager.h"

#if defined(__APPLE__)
#import <CoreMIDI/CoreMIDI.h>

static NSString *
MIDIInputEndpointName (MIDIEndpointRef endpoint)
{
  CFStringRef value = NULL;
  if (MIDIObjectGetStringProperty (endpoint, kMIDIPropertyDisplayName, &value) != noErr || !value)
    MIDIObjectGetStringProperty (endpoint, kMIDIPropertyName, &value);
  if (!value)
    return @"MIDI Input";
  return [(NSString *)value autorelease];
}

static void
MIDIInputRead (const MIDIPacketList *packets, void *readRefCon, void *sourceRefCon)
{
  (void)sourceRefCon;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  MIDIInputManager *manager = (MIDIInputManager *)readRefCon;
  const MIDIPacket *packet = &packets->packet[0];
  for (UInt32 packetIndex = 0; packetIndex < packets->numPackets; packetIndex++)
    {
      NSUInteger index = 0;
      while (index < packet->length)
        {
          unsigned char byte = packet->data[index++];
          unsigned char status = byte;
          if (byte & 0x80)
            {
              if (byte >= 0xf0)
                continue;
              manager->_runningStatus = byte;
            }
          else
            {
              status = manager->_runningStatus;
              index--;
            }
          if (!status)
            break;
          unsigned char type = status & 0xf0;
          NSUInteger dataLength = (type == 0xc0 || type == 0xd0) ? 1 : 2;
          if (index + dataLength > packet->length)
            break;
          unsigned char data1 = packet->data[index++];
          unsigned char data2 = dataLength == 2 ? packet->data[index++] : 0;
          if (type != 0x80 && type != 0x90 && type != 0xb0)
            continue;
          NSDictionary *event = [NSDictionary
            dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedChar:type], @"type",
                                         [NSNumber numberWithUnsignedChar:(status & 0x0f)],
                                         @"channel", [NSNumber numberWithUnsignedChar:data1],
                                         @"data1", [NSNumber numberWithUnsignedChar:data2],
                                         @"data2",
                                         [NSNumber
                                           numberWithDouble:[NSDate
                                                              timeIntervalSinceReferenceDate]],
                                         @"time", nil];
          if (manager->_action)
            [manager->_target performSelectorOnMainThread:manager->_action
                                               withObject:event
                                            waitUntilDone:NO];
        }
      packet = MIDIPacketNext (packet);
    }
  [pool drain];
}

static void
MIDIInputNotify (const MIDINotification *message, void *refCon)
{
  MIDIInputManager *manager = (MIDIInputManager *)refCon;
  if ((message->messageID == kMIDIMsgObjectAdded || message->messageID == kMIDIMsgObjectRemoved
       || message->messageID == kMIDIMsgSetupChanged)
      && manager->_changeAction)
    [manager->_target performSelectorOnMainThread:manager->_changeAction
                                       withObject:nil
                                    waitUntilDone:NO];
}
#endif

@implementation MIDIInputManager

- (id)init
{
  self = [super init];
#if defined(__APPLE__)
  if (self)
    {
      MIDIClientRef client = 0;
      if (MIDIClientCreate (CFSTR ("ScoreMaker MIDI Input"), MIDIInputNotify, self, &client)
          == noErr)
        _client = (unsigned int)client;
    }
#endif
  return self;
}

- (void)setTarget:(id)target
{
  _target = target;
}

- (void)setAction:(SEL)action
{
  _action = action;
}

- (void)setChangeAction:(SEL)action
{
  _changeAction = action;
}

- (NSArray *)availableSources
{
#if defined(__APPLE__)
  NSMutableArray *sources = [NSMutableArray array];
  ItemCount count = MIDIGetNumberOfSources ();
  for (ItemCount index = 0; index < count; index++)
    {
      MIDIEndpointRef endpoint = MIDIGetSource (index);
      if (!endpoint)
        continue;
      [sources addObject:[NSDictionary
                           dictionaryWithObjectsAndKeys:MIDIInputEndpointName (endpoint), @"name",
                                                        [NSNumber numberWithUnsignedInt:endpoint],
                                                        @"endpoint", nil]];
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
  if (!source)
    return YES;
  if (!_client)
    return NO;
  MIDIPortRef port = (MIDIPortRef)_inputPort;
  if (!port
      && MIDIInputPortCreate ((MIDIClientRef)_client, CFSTR ("ScoreMaker Input Port"),
                              MIDIInputRead, self, &port)
           != noErr)
    {
      return NO;
    }
  if (MIDIPortConnectSource (port, (MIDIEndpointRef)source, NULL) != noErr)
    {
      if (!_inputPort)
        MIDIPortDispose (port);
      return NO;
    }
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
  if (_inputPort && _source)
    MIDIPortDisconnectSource ((MIDIPortRef)_inputPort, (MIDIEndpointRef)_source);
  _source = 0;
  _runningStatus = 0;
#endif
}

- (void)dealloc
{
  _target = nil;
  _action = NULL;
  _changeAction = NULL;
  [self disconnect];
#if defined(__APPLE__)
  if (_inputPort)
    MIDIPortDispose ((MIDIPortRef)_inputPort);
  if (_client)
    MIDIClientDispose ((MIDIClientRef)_client);
#endif
  [super dealloc];
}
@end
