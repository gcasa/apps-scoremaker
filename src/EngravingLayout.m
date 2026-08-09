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

#import "EngravingLayout.h"
#import <math.h>

@implementation ScoreEngravingSystem
@synthesize startTick = _startTick, endTick = _endTick;
@synthesize firstMeasureIndex = _firstMeasureIndex, lastMeasureIndex = _lastMeasureIndex;
@synthesize ticks = _ticks, fractions = _fractions;
- (void)dealloc
{
  [_ticks release];
  [_fractions release];
  [super dealloc];
}
- (CGFloat)fractionForTick:(NSUInteger)tick
{
  if (tick <= _startTick)
    return 0.0;
  if (tick >= _endTick)
    return 1.0;
  for (NSUInteger i = 0; i + 1 < [_ticks count]; i++)
    {
      NSUInteger a = [[_ticks objectAtIndex:i] unsignedIntegerValue],
                 b = [[_ticks objectAtIndex:i + 1] unsignedIntegerValue];
      if (tick < a || tick > b)
        continue;
      CGFloat fa = [[_fractions objectAtIndex:i] doubleValue],
              fb = [[_fractions objectAtIndex:i + 1] doubleValue];
      return fa + (b > a ? (CGFloat)(tick - a) / (CGFloat)(b - a) : 0.0) * (fb - fa);
    }
  return (CGFloat)(tick - _startTick) / (CGFloat)MAX ((NSUInteger)1, _endTick - _startTick);
}
@end

@implementation ScoreEngravingLayout
@synthesize systems = _systems, notationElements = _notationElements;
- (void)dealloc
{
  [_systems release];
  [_notationElements release];
  [super dealloc];
}
- (ScoreEngravingSystem *)systemContainingTick:(NSUInteger)tick
{
  for (ScoreEngravingSystem *system in _systems)
    if (tick >= [system startTick] && tick < [system endTick])
      return system;
  return [_systems lastObject];
}
@end

@implementation ScoreEngraver
- (void)dealloc
{
  [_displayedAccidentals release];
  [_accidentalDocument release];
  [super dealloc];
}
- (void)prepareAccidentalsForDocument:(ScoreDocument *)document
{
  if (_accidentalDocument == document && _displayedAccidentals)
    return;
  [_accidentalDocument release];
  _accidentalDocument = [document retain];
  [_displayedAccidentals release];
  _displayedAccidentals = [ScoreDisplayedAccidentalMapForDocument (document) copy];
}
- (CGFloat)widthForMeasure:(ScoreMeasure *)measure
                  document:(ScoreDocument *)document
                   minimum:(CGFloat)minimum
{
  [self prepareAccidentalsForDocument:document];
  NSMutableDictionary *notesByOnset = [NSMutableDictionary dictionary];
  NSUInteger end = [measure startTick] + [measure durationTicks];
  for (ScoreNote *note in [document notes])
    if ([note startTick] >= [measure startTick] && [note startTick] < end)
      {
        NSNumber *onset = [NSNumber numberWithUnsignedInteger:[note startTick]];
        NSMutableArray *notes = [notesByOnset objectForKey:onset];
        if (!notes)
          {
            notes = [NSMutableArray array];
            [notesByOnset setObject:notes forKey:onset];
          }
        [notes addObject:note];
      }
  CGFloat contentWidth = 42.0;
  NSUInteger measureIndex = [[document measures] indexOfObjectIdenticalTo:measure];
  if (measureIndex > 0 && measureIndex != NSNotFound)
    {
      ScoreMeasure *previous = [[document measures] objectAtIndex:measureIndex - 1];
      if ([previous keySignatureFifths] != [measure keySignatureFifths] ||
          ![[previous keyMode] isEqualToString:[measure keyMode]])
        contentWidth += 8.0 * (labs ([previous keySignatureFifths]) +
                               labs ([measure keySignatureFifths])) + 12.0;
    }
  for (NSArray *notes in [notesByOnset allValues])
    {
      NSUInteger accidentals = 0;
      CGFloat annotationWidth = 0.0;
      for (ScoreNote *note in notes)
        {
          if ([[self->_displayedAccidentals objectForKey:[NSValue valueWithPointer:note]]
                integerValue] != NSIntegerMax)
            accidentals++;
          annotationWidth = MAX (annotationWidth, (CGFloat)[[note dynamic] length] * 7.0);
        }
      CGFloat chordWidth = 17.0 + MAX ((CGFloat)0.0, ((CGFloat)[notes count] - 1.0) * 4.5);
      CGFloat accidentalWidth = accidentals ? 10.0 + (CGFloat)(accidentals - 1) * 8.0 : 0.0;
      contentWidth += MAX (chordWidth + accidentalWidth, annotationWidth + 8.0);
    }
  return MAX (minimum, contentWidth);
}
- (ScoreEngravingSystem *)systemForDocument:(ScoreDocument *)document
                                      first:(NSUInteger)first
                                       last:(NSUInteger)last
{
  NSArray *measures = [document measures];
  ScoreMeasure *a = [measures objectAtIndex:first], *b = [measures objectAtIndex:last];
  NSUInteger start = [a startTick], end = [b startTick] + [b durationTicks];
  NSMutableSet *tickSet =
    [NSMutableSet setWithObjects:[NSNumber numberWithUnsignedInteger:start],
                                 [NSNumber numberWithUnsignedInteger:end], nil];
  for (NSUInteger i = first; i <= last; i++)
    [tickSet addObject:[NSNumber numberWithUnsignedInteger:[[measures objectAtIndex:i] startTick]]];
  for (ScoreNote *note in [document notes])
    if ([note startTick] >= start && [note startTick] < end)
      [tickSet addObject:[NSNumber numberWithUnsignedInteger:[note startTick]]];
  NSArray *ticks = [[tickSet allObjects] sortedArrayUsingSelector:@selector (compare:)];
  NSMutableArray *weights = [NSMutableArray array];
  CGFloat total = 0;
  for (NSUInteger i = 0; i + 1 < [ticks count]; i++)
    {
      NSUInteger ta = [[ticks objectAtIndex:i] unsignedIntegerValue],
                 tb = [[ticks objectAtIndex:i + 1] unsignedIntegerValue];
      NSUInteger count = 0;
      for (ScoreNote *note in [document notes])
        if ([note startTick] == ta)
          count++;
      CGFloat w = MAX (
        10.0
          + 18.0
              * sqrt ((double)(tb - ta) / (double)MAX ((NSUInteger)1, [document ticksPerQuarter])),
        15.0 + count * 3.5);
      [weights addObject:[NSNumber numberWithDouble:w]];
      total += w;
    }
  NSMutableArray *fractions = [NSMutableArray arrayWithObject:@0.0];
  CGFloat sum = 0;
  for (NSNumber *w in weights)
    {
      sum += [w doubleValue];
      [fractions addObject:[NSNumber numberWithDouble:total ? sum / total : 1]];
    }
  ScoreEngravingSystem *system = [[[ScoreEngravingSystem alloc] init] autorelease];
  [system setStartTick:start];
  [system setEndTick:end];
  [system setFirstMeasureIndex:first];
  [system setLastMeasureIndex:last];
  [system setTicks:ticks];
  [system setFractions:fractions];
  return system;
}
- (ScoreEngravingLayout *)layoutDocument:(ScoreDocument *)document
                              musicWidth:(CGFloat)musicWidth
                     minimumMeasureWidth:(CGFloat)minimum
{
  if ([[document measures] count] == 0)
    [document buildDefaultMeasures];
  NSMutableArray *systems = [NSMutableArray array];
  NSArray *measures = [document measures];
  if ([measures count])
    {
      NSUInteger first = 0;
      CGFloat used = 0;
      for (NSUInteger i = 0; i < [measures count]; i++)
        {
          CGFloat width = [self widthForMeasure:[measures objectAtIndex:i]
                                       document:document
                                        minimum:minimum];
          if (i > first && used + width > musicWidth)
            {
              [systems addObject:[self systemForDocument:document first:first last:i - 1]];
              first = i;
              used = 0;
            }
          used += MIN (width, musicWidth);
        }
      [systems addObject:[self systemForDocument:document first:first last:[measures count] - 1]];
    }
  ScoreEngravingLayout *layout = [[[ScoreEngravingLayout alloc] init] autorelease];
  [layout setSystems:systems];
  [layout setNotationElements:[ScoreNotationModel elementsForDocument:document]];
  return layout;
}
@end
