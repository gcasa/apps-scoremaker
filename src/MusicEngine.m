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

#import "MusicEngine.h"

@implementation ScoreScheduledEvent
@synthesize tick = _tick, time = _time, note = _note, noteOff = _noteOff;
- (void)dealloc
{
  [_note release];
  [super dealloc];
}
@end

@implementation ScoreScheduler
- (id)initWithDocument:(ScoreDocument *)document
{
  if ((self = [super init]))
    _document = [document retain];
  return self;
}
- (NSArray *)orderedTempoEvents
{
  return [[_document tempoEvents] sortedArrayUsingComparator:^NSComparisonResult (id a, id b) {
    if ([a tick] < [b tick])
      return NSOrderedAscending;
    if ([a tick] > [b tick])
      return NSOrderedDescending;
    return NSOrderedSame;
  }];
}
- (NSTimeInterval)timeForTick:(NSUInteger)tick
{
  NSUInteger previousTick = 0;
  NSUInteger tempo = [_document tempoMicrosecondsPerQuarter];
  NSTimeInterval result = 0.0;
  for (ScoreTempoEvent *event in [self orderedTempoEvents])
    {
      if ([event tick] > tick)
        break;
      result += (double)([event tick] - previousTick) * tempo
                / (1000000.0 * MAX ((NSUInteger)1, [_document ticksPerQuarter]));
      previousTick = [event tick];
      tempo = [event microsecondsPerQuarter];
    }
  result += (double)(tick - previousTick) * tempo
            / (1000000.0 * MAX ((NSUInteger)1, [_document ticksPerQuarter]));
  return result;
}
- (NSUInteger)tickForTime:(NSTimeInterval)time
{
  NSUInteger low = 0, high = MAX ((NSUInteger)1, [_document totalTicks]);
  while (low < high)
    {
      NSUInteger middle = low + (high - low) / 2;
      if ([self timeForTick:middle] < time)
        low = middle + 1;
      else
        high = middle;
    }
  return low;
}
- (NSArray *)eventsFromTick:(NSUInteger)startTick throughTick:(NSUInteger)endTick
{
  NSMutableArray *events = [NSMutableArray array];
  for (ScoreNote *note in [_document notes])
    {
      if ([note isRest])
        continue;
      NSUInteger offTick = [note startTick] + [note durationTicks];
      if ([note startTick] >= startTick && [note startTick] <= endTick)
        {
          ScoreScheduledEvent *event = [[[ScoreScheduledEvent alloc] init] autorelease];
          event.tick = [note startTick];
          event.time = [self timeForTick:event.tick];
          event.note = note;
          [events addObject:event];
        }
      if (offTick >= startTick && offTick <= endTick)
        {
          ScoreScheduledEvent *event = [[[ScoreScheduledEvent alloc] init] autorelease];
          event.tick = offTick;
          event.time = [self timeForTick:offTick];
          event.note = note;
          event.noteOff = YES;
          [events addObject:event];
        }
    }
  return [events sortedArrayUsingComparator:^NSComparisonResult (id a, id b) {
    if ([a tick] < [b tick])
      return NSOrderedAscending;
    if ([a tick] > [b tick])
      return NSOrderedDescending;
    if ([a noteOff] != [b noteOff])
      return [a noteOff] ? NSOrderedAscending : NSOrderedDescending;
    return NSOrderedSame;
  }];
}
- (void)dealloc
{
  [_document release];
  [super dealloc];
}
@end

@implementation ScoreMIDIRouter
- (id)initWithDocument:(ScoreDocument *)document
{
  if ((self = [super init]))
    _document = [document retain];
  return self;
}
- (NSArray *)destinationsForSource:(NSString *)source
                           channel:(NSInteger)channel
                             pitch:(NSInteger)pitch
                          velocity:(NSUInteger)velocity
{
  NSMutableArray *destinations = [NSMutableArray array];
  for (ScoreMIDIRoute *route in [_document midiRoutes])
    if ([route enabled]
        && ([[route sourceIdentifier] isEqualToString:source] || ![route sourceIdentifier])
        && ([route sourceChannel] < 0 || [route sourceChannel] == channel))
      {
        NSInteger routedPitch
          = MIN ((NSInteger)127, MAX ((NSInteger)0, pitch + [route transposition]));
        NSUInteger routedVelocity
          = MIN ((NSUInteger)127, (NSUInteger)llround (velocity * [route velocityScale]));
        [destinations
          addObject:[NSDictionary
                      dictionaryWithObjectsAndKeys:[route destinationPartIdentifier],
                                                   @"partIdentifier",
                                                   [NSNumber
                                                     numberWithInteger:[route destinationChannel]],
                                                   @"channel",
                                                   [NSNumber numberWithInteger:routedPitch],
                                                   @"pitch",
                                                   [NSNumber
                                                     numberWithUnsignedInteger:routedVelocity],
                                                   @"velocity", nil]];
      }
  return destinations;
}
- (void)dealloc
{
  [_document release];
  [super dealloc];
}
@end

@implementation ScoreInstrumentRegistry
+ (ScoreInstrumentRegistry *)sharedRegistry
{
  static ScoreInstrumentRegistry *registry = nil;
  if (!registry)
    registry = [[ScoreInstrumentRegistry alloc] init];
  return registry;
}
- (id)init
{
  if ((self = [super init]))
    _backends = [[NSMutableDictionary alloc] init];
  return self;
}
- (void)registerBackend:(id<ScoreInstrumentBackend>)backend
{
  if ([[backend identifier] length])
    [_backends setObject:backend forKey:[backend identifier]];
}
- (id<ScoreInstrumentBackend>)backendForIdentifier:(NSString *)identifier
{
  return [_backends objectForKey:identifier];
}
- (void)dealloc
{
  [_backends release];
  [super dealloc];
}
@end

@implementation ScoreSynthesisCompiler
+ (NSArray *)processingOrderForGraph:(ScoreSynthesisGraph *)graph error:(NSError **)error
{
  if (![graph validateWithError:error])
    return nil;
  NSMutableDictionary *nodes = [NSMutableDictionary dictionary];
  NSMutableDictionary *incoming = [NSMutableDictionary dictionary];
  for (ScoreSynthesisNode *node in [graph nodes])
    {
      [nodes setObject:node forKey:[node identifier]];
      [incoming setObject:@0 forKey:[node identifier]];
    }
  for (ScoreSynthesisConnection *connection in [graph connections])
    [incoming
      setObject:[NSNumber
                  numberWithInteger:[[incoming objectForKey:[connection destinationNodeIdentifier]]
                                      integerValue]
                                    + 1]
         forKey:[connection destinationNodeIdentifier]];
  NSMutableArray *ready = [NSMutableArray array];
  for (NSString *identifier in incoming)
    if ([[incoming objectForKey:identifier] integerValue] == 0)
      [ready addObject:identifier];
  NSMutableArray *order = [NSMutableArray array];
  while ([ready count])
    {
      NSString *identifier = [[[ready objectAtIndex:0] retain] autorelease];
      [ready removeObjectAtIndex:0];
      [order addObject:[nodes objectForKey:identifier]];
      for (ScoreSynthesisConnection *connection in [graph connections])
        if ([[connection sourceNodeIdentifier] isEqualToString:identifier])
          {
            NSString *destination = [connection destinationNodeIdentifier];
            NSInteger count = [[incoming objectForKey:destination] integerValue] - 1;
            [incoming setObject:[NSNumber numberWithInteger:count] forKey:destination];
            if (count == 0)
              [ready addObject:destination];
          }
    }
  if ([order count] != [[graph nodes] count])
    {
      if (error)
        *error =
          [NSError errorWithDomain:@"ScoreMakerSynthesisGraph"
                              code:3
                          userInfo:[NSDictionary
                                     dictionaryWithObject:@"Synthesis graphs cannot contain cycles."
                                                   forKey:NSLocalizedDescriptionKey]];
      return nil;
    }
  return order;
}
@end

@implementation ScoreCompositionEvaluator
+ (BOOL)evaluateProgram:(ScoreCompositionProgram *)program
             inDocument:(ScoreDocument *)document
                  error:(NSError **)error
{
  [[program diagnostics] removeAllObjects];
  NSArray *lines =
    [[program source] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  NSInteger track = 0, voice = 1;
  NSUInteger tick = 0;
  for (NSUInteger index = 0; index < [lines count]; index++)
    {
      NSString *line = [[lines objectAtIndex:index]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      if (![line length] || [line hasPrefix:@"#"])
        continue;
      NSArray *words =
        [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      NSMutableArray *tokens = [NSMutableArray array];
      for (NSString *word in words)
        if ([word length])
          [tokens addObject:word];
      NSString *command = [tokens objectAtIndex:0];
      if ([command isEqualToString:@"part"] && [tokens count] >= 3)
        {
          track = [[tokens objectAtIndex:1] integerValue];
          [document setName:[tokens objectAtIndex:2] forTrack:track];
        }
      else if ([command isEqualToString:@"voice"] && [tokens count] == 2)
        voice = MAX ((NSInteger)1, [[tokens objectAtIndex:1] integerValue]);
      else if (([command isEqualToString:@"note"] || [command isEqualToString:@"rest"]) &&
               [tokens count] >= 3)
        {
          ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
          [note setTrack:track];
          [note setChannel:track % 16];
          [note setVoice:voice];
          [note setStartTick:tick];
          [note setRest:[command isEqualToString:@"rest"]];
          [note setPitch:[note isRest] ? 60 : [[tokens objectAtIndex:1] integerValue]];
          NSUInteger duration = (NSUInteger)[[tokens objectAtIndex:2] integerValue];
          [note setDurationTicks:duration];
          [[document notes] addObject:note];
          tick += duration;
          [document setTotalTicks:MAX ([document totalTicks], tick)];
        }
      else
        {
          NSString *message = [NSString
            stringWithFormat:@"Line %lu: invalid composition command.", (unsigned long)(index + 1)];
          [[program diagnostics] addObject:message];
        }
    }
  if ([[program diagnostics] count])
    {
      if (error)
        *error = [NSError
          errorWithDomain:@"ScoreMakerComposition"
                     code:1
                 userInfo:[NSDictionary dictionaryWithObject:[[program diagnostics]
                                                               componentsJoinedByString:@"\n"]
                                                      forKey:NSLocalizedDescriptionKey]];
      return NO;
    }
  [document rebuildStructuredPartsFromLegacyTracks];
  return YES;
}
@end
