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

#import "NotationModel.h"

@implementation ScoreNotationElement
@synthesize kind = _kind, startTick = _startTick, endTick = _endTick;
@synthesize track = _track, notationVoice = _notationVoice, value = _value, source = _source;
- (void)dealloc
{
  [_value release];
  [super dealloc];
}
@end

@implementation ScoreNotationModel
+ (ScoreNotationElement *)element:(ScoreNotationKind)kind
                            start:(NSUInteger)start
                              end:(NSUInteger)end
                            track:(NSInteger)track
                            voice:(NSInteger)voice
                            value:(NSString *)value
                           source:(id)source
{
  ScoreNotationElement *element = [[[ScoreNotationElement alloc] init] autorelease];
  [element setKind:kind];
  [element setStartTick:start];
  [element setEndTick:end];
  [element setTrack:track];
  [element setNotationVoice:voice];
  [element setValue:value];
  [element setSource:source];
  return element;
}

+ (NSArray *)elementsForDocument:(ScoreDocument *)document
{
  NSMutableArray *elements = [NSMutableArray array];
  for (ScoreMeasure *measure in [document measures])
    {
      NSUInteger start = [measure startTick], end = start + [measure durationTicks];
      if ([measure keySignatureFifths] != 0)
        [elements
          addObject:[self
                      element:ScoreNotationKeySignature
                        start:start
                          end:end
                        track:-1
                        voice:0
                        value:[NSString stringWithFormat:@"%ld", (long)[measure keySignatureFifths]]
                       source:measure]];
      if ([measure repeatStart])
        [elements addObject:[self element:ScoreNotationRepeat
                                    start:start
                                      end:start
                                    track:-1
                                    voice:0
                                    value:@"start"
                                   source:measure]];
      if ([measure repeatEnd])
        [elements addObject:[self element:ScoreNotationRepeat
                                    start:end
                                      end:end
                                    track:-1
                                    voice:0
                                    value:@"end"
                                   source:measure]];
      if ([[measure rehearsalMark] length])
        [elements addObject:[self element:ScoreNotationRehearsalMark start:start end:start
                                   track:-1 voice:0 value:[measure rehearsalMark] source:measure]];
      if ([[measure endingText] length])
        [elements addObject:[self element:ScoreNotationEnding start:start end:end
                                   track:-1 voice:0 value:[measure endingText] source:measure]];
    }
  for (ScoreNote *note in [document notes])
    {
      NSUInteger start = [note startTick], end = start + [note durationTicks];
      [elements addObject:[self element:[note isRest] ? ScoreNotationRest : ScoreNotationNote
                                  start:start
                                    end:end
                                  track:[note track]
                                  voice:[note voice]
                                  value:nil
                                 source:note]];
      if ([note accidental])
        [elements
          addObject:[self element:ScoreNotationAccidental
                            start:start
                              end:start
                            track:[note track]
                            voice:[note voice]
                            value:[NSString stringWithFormat:@"%ld", (long)[note accidental]]
                           source:note]];
      if ([note slurStart] || [note slurEnd])
        [elements addObject:[self element:ScoreNotationSlur
                                    start:start
                                      end:end
                                    track:[note track]
                                    voice:[note voice]
                                    value:[note slurStart] ? @"start" : @"end"
                                   source:note]];
      if ([note tieStart] || [note tieEnd])
        [elements addObject:[self element:ScoreNotationTie
                                    start:start
                                      end:end
                                    track:[note track]
                                    voice:[note voice]
                                    value:[note tieStart] ? @"start" : @"end"
                                   source:note]];
      if ([note tupletActual])
        [elements
          addObject:[self element:ScoreNotationTuplet
                            start:start
                              end:end
                            track:[note track]
                            voice:[note voice]
                            value:[NSString stringWithFormat:@"%lu:%lu",
                                                             (unsigned long)[note tupletActual],
                                                             (unsigned long)[note tupletNormal]]
                           source:note]];
      if ([[note dynamic] length])
        [elements addObject:[self element:ScoreNotationDynamic
                                    start:start
                                      end:start
                                    track:[note track]
                                    voice:[note voice]
                                    value:[note dynamic]
                                   source:note]];
      if ([[note articulation] length])
        [elements addObject:[self element:ScoreNotationArticulation
                                    start:start
                                      end:start
                                    track:[note track]
                                    voice:[note voice]
                                    value:[note articulation]
                                   source:note]];
      if ([[note lyric] length])
        [elements addObject:[self element:ScoreNotationLyric start:start end:start
                                   track:[note track] voice:[note voice]
                                   value:[note lyric] source:note]];
      if ([[note ornament] length])
        [elements addObject:[self element:ScoreNotationOrnament start:start end:start
                                   track:[note track] voice:[note voice]
                                   value:[note ornament] source:note]];
      if ([note isGrace])
        [elements addObject:[self element:ScoreNotationGrace start:start end:start
                                   track:[note track] voice:[note voice] value:nil source:note]];
      if ([note isCue])
        [elements addObject:[self element:ScoreNotationCue start:start end:end
                                   track:[note track] voice:[note voice] value:nil source:note]];
      if ([note tremoloStrokes])
        [elements addObject:[self element:ScoreNotationTremolo start:start end:end
                                   track:[note track] voice:[note voice]
                                   value:[NSString stringWithFormat:@"%lu",
                                          (unsigned long)[note tremoloStrokes]] source:note]];
      if ([[note hairpinStart] length] || [note hairpinEnd])
        [elements addObject:[self element:ScoreNotationHairpin start:start end:end
                                   track:[note track] voice:[note voice]
                                   value:[note hairpinStart] ?: @"end" source:note]];
      if ([note pedalStart] || [note pedalEnd])
        [elements addObject:[self element:ScoreNotationPedal start:start end:end
                                   track:[note track] voice:[note voice]
                                   value:[note pedalStart] ? @"start" : @"end" source:note]];
      if ([note octaveShiftStart] || [note octaveShiftEnd])
        [elements addObject:[self element:ScoreNotationOctaveShift start:start end:end
                                   track:[note track] voice:[note voice]
                                   value:[note octaveShiftStart] > 0 ? @"8va"
                                         : ([note octaveShiftStart] < 0 ? @"8vb" : @"end")
                                  source:note]];
      if ([[note directionText] length])
        [elements addObject:[self element:ScoreNotationText start:start end:start
                                   track:[note track] voice:[note voice]
                                   value:[note directionText] source:note]];
    }
  return elements;
}
@end
