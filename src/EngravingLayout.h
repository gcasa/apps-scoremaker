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

#import <AppKit/AppKit.h>
#import "NotationModel.h"

@interface ScoreEngravingSystem : NSObject
{
  NSUInteger _startTick, _endTick, _firstMeasureIndex, _lastMeasureIndex;
  NSArray *_ticks, *_fractions;
}
@property (nonatomic) NSUInteger startTick;
@property (nonatomic) NSUInteger endTick;
@property (nonatomic) NSUInteger firstMeasureIndex;
@property (nonatomic) NSUInteger lastMeasureIndex;
@property (nonatomic, copy) NSArray *ticks;
@property (nonatomic, copy) NSArray *fractions;
- (CGFloat)fractionForTick:(NSUInteger)tick;
@end

@interface ScoreEngravingLayout : NSObject
{
  NSArray *_systems, *_notationElements;
}
@property (nonatomic, copy) NSArray *systems;
@property (nonatomic, copy) NSArray *notationElements;
- (ScoreEngravingSystem *)systemContainingTick:(NSUInteger)tick;
@end

@interface ScoreEngraver : NSObject
{
  NSDictionary *_displayedAccidentals;
  ScoreDocument *_accidentalDocument;
}
- (CGFloat)widthForMeasure:(ScoreMeasure *)measure
                  document:(ScoreDocument *)document
                   minimum:(CGFloat)minimum;
- (ScoreEngravingLayout *)layoutDocument:(ScoreDocument *)document
                              musicWidth:(CGFloat)musicWidth
                     minimumMeasureWidth:(CGFloat)minimumMeasureWidth;
@end
