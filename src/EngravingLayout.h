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

/** Describes the tick, measure, and horizontal-position span of one system. */
@interface ScoreEngravingSystem : NSObject
{
  NSUInteger _startTick, _endTick, _firstMeasureIndex, _lastMeasureIndex;
  BOOL _startsNewPage;
  NSArray *_ticks, *_fractions;
}
/** First tick included in the system. */
@property (nonatomic) NSUInteger startTick;
/** Exclusive ending tick of the system. */
@property (nonatomic) NSUInteger endTick;
/** Zero-based index of the first included measure. */
@property (nonatomic) NSUInteger firstMeasureIndex;
/** Zero-based index of the last included measure. */
@property (nonatomic) NSUInteger lastMeasureIndex;
/** Whether this system was forced to the top of a new page. */
@property (nonatomic) BOOL startsNewPage;
/** Ordered NSNumber tick anchors used for horizontal interpolation. */
@property (nonatomic, copy) NSArray *ticks;
/** Ordered NSNumber horizontal fractions corresponding to the tick anchors. */
@property (nonatomic, copy) NSArray *fractions;
/** Returns the normalized horizontal position for <var>tick</var>. */
- (CGFloat)fractionForTick:(NSUInteger)tick;
@end

/** Returns the zero-based page containing a system, honoring forced page starts. */
FOUNDATION_EXPORT NSUInteger ScorePageIndexForSystem (NSArray *systems,
                                                       NSUInteger systemIndex,
                                                       NSUInteger systemsPerPage);
/** Returns the zero-based vertical position of a system on its assigned page. */
FOUNDATION_EXPORT NSUInteger ScorePositionOnPageForSystem (NSArray *systems,
                                                            NSUInteger systemIndex,
                                                            NSUInteger systemsPerPage);

/** Contains every engraved system and the normalized notation elements. */
@interface ScoreEngravingLayout : NSObject
{
  NSArray *_systems, *_notationElements;
}
/** Ordered array of ScoreEngravingSystem instances. */
@property (nonatomic, copy) NSArray *systems;
/** Array of ScoreNotationElement instances used by the layout. */
@property (nonatomic, copy) NSArray *notationElements;
/** Returns the system spanning <var>tick</var>, or <code>nil</code>. */
- (ScoreEngravingSystem *)systemContainingTick:(NSUInteger)tick;
@end

/** Computes deterministic measure widths, system breaks, and onset spacing. */
@interface ScoreEngraver : NSObject
{
  NSDictionary *_displayedAccidentals;
  ScoreDocument *_accidentalDocument;
}
/** Returns the preferred width for <var>measure</var>, never below <var>minimum</var>. */
- (CGFloat)widthForMeasure:(ScoreMeasure *)measure
                  document:(ScoreDocument *)document
                   minimum:(CGFloat)minimum;
/** Lays out <var>document</var> within the supplied music width. */
- (ScoreEngravingLayout *)layoutDocument:(ScoreDocument *)document
                              musicWidth:(CGFloat)musicWidth
                     minimumMeasureWidth:(CGFloat)minimumMeasureWidth;
@end
